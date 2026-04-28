import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/android_connection_extensions.dart';
import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../connection/ios_connection_extensions.dart';
import '../connection/lifecycle_client.dart';
import '../gatt_client/gatt.dart' show RemoteService;
import '../lifecycle.dart' as lifecycle;
import '../shared/uuid.dart';
import 'peer.dart';
import 'peer_discovery.dart';
import 'peer_remote_service_view.dart';
import 'server_id.dart';

/// Package-private factory for constructing a [BlueyPeer].
BlueyPeer createBlueyPeer({
  required platform.BlueyPlatform platformApi,
  required ServerId serverId,
  Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
}) {
  return _BlueyPeer(
    platformApi: platformApi,
    serverId: serverId,
    peerSilenceTimeout: peerSilenceTimeout,
  );
}

class _BlueyPeer implements BlueyPeer {
  final platform.BlueyPlatform _platform;
  final Duration _peerSilenceTimeout;

  @override
  final ServerId serverId;

  bool _connecting = false;

  _BlueyPeer({
    required platform.BlueyPlatform platformApi,
    required this.serverId,
    required Duration peerSilenceTimeout,
  })  : _platform = platformApi,
        _peerSilenceTimeout = peerSilenceTimeout;

  @override
  Future<Connection> connect({
    Duration? scanTimeout,
    Duration? timeout,
  }) async {
    if (_connecting) {
      throw StateError('Peer $serverId is already connecting');
    }
    _connecting = true;
    try {
      final effectiveScanTimeout = scanTimeout ?? const Duration(seconds: 5);

      dev.log('upgrade attempt: deviceId=${serverId}', name: 'bluey.peer');

      final discovery = PeerDiscovery(platformApi: _platform);
      final rawConnection = await discovery.connectTo(
        serverId,
        scanTimeout: effectiveScanTimeout,
        timeout: timeout,
      );

      final blueyConnection = rawConnection as BlueyConnection;

      // Discover services on the raw connection (includes control service).
      final allServices = await blueyConnection.services();

      final controlService = allServices
          .where((s) => lifecycle.isControlService(s.uuid.toString()))
          .firstOrNull;
      dev.log(
        controlService != null
            ? 'control service discovered'
            : 'no control service — peer is not a bluey peer',
        name: 'bluey.peer',
      );

      // Start lifecycle heartbeat. The LifecycleClient lives alongside
      // the connection; post-C.6 it is no longer attached to the
      // BlueyConnection itself. C.7 will fold this into a PeerConnection
      // wrapper; for now, the heartbeat still drives unreachable-detection
      // and the caller continues to receive the raw [Connection].
      final lifecycleClient = LifecycleClient(
        platformApi: _platform,
        connectionId: blueyConnection.connectionId,
        peerSilenceTimeout: _peerSilenceTimeout,
        onServerUnreachable: () {
          blueyConnection.disconnect().catchError((_) {});
        },
      );
      lifecycleClient.start(allServices: allServices);

      dev.log('using caller-provided serverId: $serverId', name: 'bluey.peer');

      dev.log(
        'connect complete: deviceId=${blueyConnection.deviceId}',
        name: 'bluey.peer',
      );

      return _BlueyPeerConnectionView(
        connection: blueyConnection,
        lifecycleClient: lifecycleClient,
      );
    } finally {
      _connecting = false;
    }
  }
}

/// Internal [Connection] wrapper returned by `_BlueyPeer.connect`.
///
/// Filters the lifecycle control service out of the service tree so the
/// caller's GATT-level view of the peer matches the user-facing surface
/// they get from `Bluey.connectAsPeer` (which returns a `PeerConnection`).
/// Also tears down the [LifecycleClient] on disconnect, since it is no
/// longer owned by [BlueyConnection] post-C.6.
///
/// C.7 will replace this with a true `PeerConnection` return type from
/// `BlueyPeer.connect`. Until then, this wrapper preserves the
/// pre-existing public contract (`Connection` with the control service
/// hidden + lifecycle-driven disconnect detection) while keeping
/// [BlueyConnection] free of peer-protocol state.
class _BlueyPeerConnectionView implements Connection {
  _BlueyPeerConnectionView({
    required BlueyConnection connection,
    required LifecycleClient lifecycleClient,
  }) : _connection = connection,
       _lifecycle = lifecycleClient,
       _serviceView = PeerRemoteServiceView(connection);

  final BlueyConnection _connection;
  final LifecycleClient _lifecycle;
  final PeerRemoteServiceView _serviceView;

  @override
  UUID get deviceId => _connection.deviceId;

  @override
  ConnectionState get state => _connection.state;

  @override
  Stream<ConnectionState> get stateChanges => _connection.stateChanges;

  @override
  Mtu get mtu => _connection.mtu;

  @override
  Future<List<RemoteService>> services({bool cache = false}) =>
      _serviceView.services(cache: cache);

  @override
  RemoteService service(UUID uuid) => _serviceView.service(uuid);

  @override
  Future<bool> hasService(UUID uuid) => _serviceView.hasService(uuid);

  @override
  Future<Mtu> requestMtu(Mtu mtu) => _connection.requestMtu(mtu);

  @override
  Future<int> readRssi() => _connection.readRssi();

  @override
  Future<void> disconnect() async {
    // Best-effort courtesy: write the lifecycle disconnect command before
    // tearing down the link, mirroring the pre-C.6 behavior. Bound it
    // with a short timeout so an unresponsive peer doesn't block the
    // platform disconnect.
    try {
      await _lifecycle
          .sendDisconnectCommand()
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // Best-effort; proceed regardless.
    }
    _lifecycle.stop();
    await _connection.disconnect();
  }

  @override
  AndroidConnectionExtensions? get android => _connection.android;

  @override
  IosConnectionExtensions? get ios => _connection.ios;
}
