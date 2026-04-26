import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../connection/lifecycle_client.dart';
import '../lifecycle.dart' as lifecycle;
import 'peer.dart';
import 'peer_discovery.dart';
import 'server_id.dart';

/// Package-private factory for constructing a [BlueyPeer].
BlueyPeer createBlueyPeer({
  required platform.BlueyPlatform platformApi,
  required ServerId serverId,
  Duration peerSilenceTimeout = const Duration(seconds: 20),
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

      // Start lifecycle heartbeat.
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

      // Upgrade the connection in place so the control service is hidden
      // from the caller's view of services/service/hasService.
      blueyConnection.upgrade(
        lifecycleClient: lifecycleClient,
        serverId: serverId,
      );

      dev.log('upgrade complete: deviceId=${blueyConnection.deviceId}', name: 'bluey.peer');

      return blueyConnection;
    } finally {
      _connecting = false;
    }
  }
}
