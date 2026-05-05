import 'dart:async';

import '../connection/connection.dart' show Connection, ConnectionState;
import '../connection/lifecycle_client.dart';
import '../gatt_client/gatt.dart' show RemoteService;
import '../shared/uuid.dart';
import 'peer_remote_service_view.dart';
import 'server_id.dart';

/// A connection to a Bluey peer (a device exposing the lifecycle control
/// service).
///
/// `PeerConnection` is a *composition wrapper* around a raw [Connection].
/// It does not extend or implement [Connection]; instead it exposes the
/// underlying GATT handle via [connection] while adding peer-protocol
/// concerns on top — stable [serverId] identity, lifecycle-protocol
/// disconnect, and (in C.3) a service tree with the lifecycle control
/// service hidden.
///
/// Obtain instances via the upcoming `Bluey.connectAsPeer` /
/// `Bluey.tryUpgrade` APIs (added in C.4). Direct construction via
/// [PeerConnection.create] is internal to the peer module.
abstract class PeerConnection {
  /// Construct a [PeerConnection] wrapping the given [connection].
  ///
  /// Internal use; consumers obtain instances via `Bluey.connectAsPeer`
  /// or `Bluey.tryUpgrade` (added in C.4).
  factory PeerConnection.create({
    required Connection connection,
    required ServerId serverId,
    required LifecycleClient lifecycleClient,
  }) = _BlueyPeerConnection;

  /// The underlying raw GATT [Connection].
  ///
  /// Use this when you need the full service tree (including the
  /// lifecycle control service) or platform-specific extensions
  /// (e.g. `connection.android?.bond()`).
  Connection get connection;

  /// The peer's stable identity, read from the control service at
  /// connect time.
  ServerId get serverId;

  /// Service tree with the lifecycle control service hidden.
  ///
  /// The filter is applied via `PeerRemoteServiceView`; raw access
  /// through [connection] returns the full tree (including the
  /// lifecycle control service).
  Future<List<RemoteService>> services({bool cache = false});

  /// Lookup a service by UUID, scoped to the peer's user-facing tree
  /// (excludes the lifecycle control service). Throws
  /// `ServiceNotFoundException` for the lifecycle control service UUID.
  RemoteService service(UUID uuid);

  /// Whether the peer's user-facing tree contains the given service UUID.
  /// Returns `false` for the lifecycle control service even if the peer
  /// hosts it.
  Future<bool> hasService(UUID uuid);

  /// Disconnect via the peer protocol.
  ///
  /// Writes `0x00` to the lifecycle control characteristic as a
  /// courtesy hint to the server (so the server fires its
  /// disconnect-detection path immediately rather than waiting for
  /// heartbeat-silence timeout), then awaits the platform-level
  /// disconnect.
  ///
  /// The courtesy write is bounded with a short timeout — an
  /// unresponsive peer (the typical disconnect scenario) does not
  /// block the platform disconnect.
  ///
  /// Callers who want a raw GATT disconnect with no peer-protocol
  /// involvement can call `peer.connection.disconnect()` directly.
  ///
  /// **iOS caveat.** On iOS, Core Bluetooth shares a single LL
  /// connection per peer pair across GAP roles. If the same physical
  /// peer is also attached as a client to the local [Server] (i.e. you
  /// hold *both* a `PeerConnection` to it *and* a `PeerClient` for it),
  /// `disconnect()` will tear down the shared link and invalidate the
  /// peripheral-side handle as well. Avoid this by guarding
  /// `connectAsPeer` with `server.isClientConnected(device.address)`
  /// rather than relying on disconnect-side dedup.
  Future<void> disconnect();
}

/// Default [PeerConnection] implementation. Private to this file —
/// consumers construct via [PeerConnection.create].
class _BlueyPeerConnection implements PeerConnection {
  _BlueyPeerConnection({
    required Connection connection,
    required ServerId serverId,
    required LifecycleClient lifecycleClient,
  }) : _connection = connection,
       _serverId = serverId,
       _lifecycle = lifecycleClient,
       _serviceView = PeerRemoteServiceView(connection) {
    // Stop the LifecycleClient as soon as the underlying connection
    // disconnects. Without this, callers that disconnect the raw
    // `connection` directly (instead of going through `peer.disconnect()`)
    // leak heartbeat traffic until the LifecycleClient's own peer-silence
    // timeout fires (~30s).
    _stateSub = _connection.stateChanges.listen((s) {
      if (s == ConnectionState.disconnected) {
        _lifecycle.stop();
        _stateSub?.cancel();
        _stateSub = null;
      }
    });
  }

  final Connection _connection;
  final ServerId _serverId;
  final LifecycleClient _lifecycle;
  final PeerRemoteServiceView _serviceView;
  StreamSubscription<ConnectionState>? _stateSub;

  @override
  Connection get connection => _connection;

  @override
  ServerId get serverId => _serverId;

  // C.3: services / service / hasService delegate through
  // PeerRemoteServiceView to hide the lifecycle control service from the
  // peer-protocol surface. Raw access via `connection` still returns the
  // full tree.
  @override
  Future<List<RemoteService>> services({bool cache = false}) =>
      _serviceView.services(cache: cache);

  @override
  RemoteService service(UUID uuid) => _serviceView.service(uuid);

  @override
  Future<bool> hasService(UUID uuid) => _serviceView.hasService(uuid);

  @override
  Future<void> disconnect() async {
    // Two-step: write 0x00 to the control characteristic via the
    // lifecycle client (courtesy hint for fast server-side detection),
    // then await the platform-level disconnect.
    //
    // The disconnect-command write is bounded with a short timeout so
    // an unresponsive peer (the typical disconnect scenario) doesn't
    // block the platform disconnect for the full per-op timeout.
    try {
      await _lifecycle.sendDisconnectCommand().timeout(
        const Duration(seconds: 1),
      );
    } catch (_) {
      // Best-effort courtesy; proceed to platform disconnect regardless.
    }
    await _connection.disconnect();
  }
}
