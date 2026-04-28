import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/lifecycle_client.dart';
import '../lifecycle.dart' as lifecycle;
import 'peer.dart';
import 'peer_connection.dart';
import 'peer_discovery.dart';
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
  Future<PeerConnection> connect({
    Duration? scanTimeout,
    Duration? timeout,
  }) async {
    if (_connecting) {
      throw StateError('Peer $serverId is already connecting');
    }
    _connecting = true;
    try {
      final effectiveScanTimeout = scanTimeout ?? const Duration(seconds: 5);

      dev.log('connect attempt: serverId=$serverId', name: 'bluey.peer');

      final discovery = PeerDiscovery(platformApi: _platform);
      final rawConnection = await discovery.connectTo(
        serverId,
        scanTimeout: effectiveScanTimeout,
        timeout: timeout,
      );

      final blueyConnection = rawConnection as BlueyConnection;

      // Discover services on the raw connection (includes control service)
      // so the LifecycleClient can locate its characteristics.
      final allServices = await blueyConnection.services();

      // Start lifecycle heartbeat. Drives the unreachable-detection path
      // that triggers a local disconnect when the peer goes silent.
      final lifecycleClient = LifecycleClient(
        platformApi: _platform,
        connectionId: blueyConnection.connectionId,
        peerSilenceTimeout: _peerSilenceTimeout,
        onServerUnreachable: () {
          blueyConnection.disconnect().catchError((_) {});
        },
      );
      lifecycleClient.start(allServices: allServices);

      dev.log(
        'connect complete: deviceId=${blueyConnection.deviceId}, '
        'serverId=$serverId',
        name: 'bluey.peer',
      );

      return PeerConnection.create(
        connection: blueyConnection,
        serverId: serverId,
        lifecycleClient: lifecycleClient,
      );
    } finally {
      _connecting = false;
    }
  }
}
