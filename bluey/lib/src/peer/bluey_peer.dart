import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../connection/lifecycle_client.dart';
import 'peer.dart';
import 'peer_connection.dart';
import 'peer_discovery.dart';
import 'server_id.dart';

/// Package-private factory for constructing a [BlueyPeer].
BlueyPeer createBlueyPeer({
  required platform.BlueyPlatform platformApi,
  required ServerId serverId,
  int maxFailedHeartbeats = 1,
}) {
  return _BlueyPeer(
    platformApi: platformApi,
    serverId: serverId,
    maxFailedHeartbeats: maxFailedHeartbeats,
  );
}

class _BlueyPeer implements BlueyPeer {
  final platform.BlueyPlatform _platform;
  final int _maxFailedHeartbeats;

  @override
  final ServerId serverId;

  bool _connecting = false;

  _BlueyPeer({
    required platform.BlueyPlatform platformApi,
    required this.serverId,
    required int maxFailedHeartbeats,
  })  : _platform = platformApi,
        _maxFailedHeartbeats = maxFailedHeartbeats;

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

      final discovery = PeerDiscovery(platformApi: _platform);
      final rawConnection = await discovery.connectTo(
        serverId,
        scanTimeout: effectiveScanTimeout,
        timeout: timeout,
      );

      // Discover services on the raw connection (includes control service).
      final allServices = await rawConnection.services();

      // Start lifecycle heartbeat.
      final connectionId = (rawConnection as BlueyConnection).connectionId;
      final lifecycle = LifecycleClient(
        platformApi: _platform,
        connectionId: connectionId,
        maxFailedHeartbeats: _maxFailedHeartbeats,
        onServerUnreachable: () {
          rawConnection.disconnect().catchError((_) {});
        },
      );
      lifecycle.start(allServices: allServices);

      // Wrap with PeerConnection so the control service is hidden
      // from the caller's view of services/service/hasService.
      return PeerConnection(rawConnection, serverId, lifecycle: lifecycle);
    } finally {
      _connecting = false;
    }
  }
}
