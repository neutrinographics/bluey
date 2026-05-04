import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/lifecycle_client.dart';
import '../event_bus.dart';
import '../lifecycle.dart' as lifecycle;
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
import 'peer.dart';
import 'peer_connection.dart';
import 'peer_discovery.dart';
import 'server_id.dart';

/// Package-private factory for constructing a [BlueyPeer].
BlueyPeer createBlueyPeer({
  required platform.BlueyPlatform platformApi,
  required ServerId serverId,
  required ServerId localIdentity,
  required BlueyLogger logger,
  Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  EventPublisher? events,
}) {
  return _BlueyPeer(
    platformApi: platformApi,
    serverId: serverId,
    localIdentity: localIdentity,
    peerSilenceTimeout: peerSilenceTimeout,
    logger: logger,
    events: events,
  );
}

class _BlueyPeer implements BlueyPeer {
  final platform.BlueyPlatform _platform;
  final ServerId _localIdentity;
  final Duration _peerSilenceTimeout;
  final BlueyLogger _logger;
  final EventPublisher? _events;

  @override
  final ServerId serverId;

  bool _connecting = false;

  _BlueyPeer({
    required platform.BlueyPlatform platformApi,
    required this.serverId,
    required ServerId localIdentity,
    required Duration peerSilenceTimeout,
    required BlueyLogger logger,
    EventPublisher? events,
  }) : _platform = platformApi,
       _localIdentity = localIdentity,
       _peerSilenceTimeout = peerSilenceTimeout,
       _logger = logger,
       _events = events;

  @override
  Future<PeerConnection> connect({
    Duration? scanTimeout,
    Duration? probeTimeout,
  }) async {
    if (_connecting) {
      throw StateError('Peer $serverId is already connecting');
    }
    _connecting = true;
    try {
      final effectiveScanTimeout = scanTimeout ?? const Duration(seconds: 5);
      final effectiveProbeTimeout =
          probeTimeout ?? PeerDiscovery.defaultProbeTimeout;

      _logger.log(
        BlueyLogLevel.info,
        'bluey.peer',
        'peer connect entered',
        data: {'serverId': serverId.toString()},
      );

      final discovery = PeerDiscovery(
        platformApi: _platform,
        logger: _logger,
        events: _events,
      );
      final BlueyConnection blueyConnection;
      try {
        final rawConnection = await discovery.connectTo(
          serverId,
          scanTimeout: effectiveScanTimeout,
          probeTimeout: effectiveProbeTimeout,
        );
        blueyConnection = rawConnection as BlueyConnection;
      } catch (e) {
        _logger.log(
          BlueyLogLevel.error,
          'bluey.peer',
          'peer connect failed',
          data: {
            'serverId': serverId.toString(),
            'reason': e.runtimeType.toString(),
          },
          errorCode: e.runtimeType.toString(),
        );
        rethrow;
      }

      // Discover services on the raw connection (includes control service)
      // so the LifecycleClient can locate its characteristics.
      final allServices = await blueyConnection.services();

      // Start lifecycle heartbeat. Drives the unreachable-detection path
      // that triggers a local disconnect when the peer goes silent.
      final lifecycleClient = LifecycleClient(
        platformApi: _platform,
        connectionId: blueyConnection.connectionId,
        localIdentity: _localIdentity,
        peerSilenceTimeout: _peerSilenceTimeout,
        onServerUnreachable: () {
          blueyConnection.disconnect().catchError((_) {});
        },
        logger: _logger,
        servicesChanges: blueyConnection.servicesChanges,
        events: _events,
        deviceId: blueyConnection.deviceId,
      );
      lifecycleClient.start(allServices: allServices);

      _logger.log(
        BlueyLogLevel.info,
        'bluey.peer',
        'peer connect resolved',
        data: {
          'serverId': serverId.toString(),
          'deviceId': blueyConnection.deviceId.toString(),
        },
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
