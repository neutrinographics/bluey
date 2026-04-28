import '../connection/connection.dart' show Connection;
import '../connection/lifecycle_client.dart';
import '../gatt_client/gatt.dart' show RemoteService;
import '../shared/uuid.dart';
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
  /// In C.1 this delegates directly to [Connection.services]; the
  /// control-service filter is wired in C.3 via `PeerRemoteServiceView`.
  Future<List<RemoteService>> services({bool cache = false});

  /// Lookup a service by UUID, scoped to the peer's user-facing tree
  /// (excludes the lifecycle control service when C.3 lands).
  ///
  /// In C.1 this delegates directly to [Connection.service]; the
  /// control-service filter is wired in C.3.
  RemoteService service(UUID uuid);

  /// Whether the peer's user-facing tree contains the given service UUID.
  ///
  /// In C.1 this delegates directly to [Connection.hasService]; the
  /// control-service filter is wired in C.3.
  Future<bool> hasService(UUID uuid);

  /// Disconnect via the peer protocol.
  ///
  /// Writes `0x00` to the lifecycle control characteristic, then awaits
  /// the platform-level disconnect. Lower-level alternative:
  /// [disconnect] (or `connection.disconnect()`).
  Future<void> sendDisconnectCommand();

  /// GATT-level disconnect — equivalent to `connection.disconnect()`.
  ///
  /// Convenience for callers that want to disconnect without going
  /// through the peer protocol.
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
       _lifecycle = lifecycleClient;

  final Connection _connection;
  final ServerId _serverId;
  final LifecycleClient _lifecycle;

  @override
  Connection get connection => _connection;

  @override
  ServerId get serverId => _serverId;

  // C.1: services / service / hasService delegate directly to the
  // wrapped connection. C.3 will wrap them through PeerRemoteServiceView
  // to hide the control service.
  @override
  Future<List<RemoteService>> services({bool cache = false}) =>
      _connection.services(cache: cache);

  @override
  RemoteService service(UUID uuid) => _connection.service(uuid);

  @override
  Future<bool> hasService(UUID uuid) => _connection.hasService(uuid);

  @override
  Future<void> sendDisconnectCommand() async {
    // Two-step: write 0x00 to the control characteristic via the lifecycle
    // client, then await the platform-level disconnect.
    await _lifecycle.sendDisconnectCommand();
    await _connection.disconnect();
  }

  @override
  Future<void> disconnect() => _connection.disconnect();
}
