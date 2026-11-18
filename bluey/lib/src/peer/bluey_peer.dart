import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../api/connection/borrowed_connection.dart';
import '../api/connection/connection.dart';
import '../connection/lifecycle_client.dart';
import '../shared/application/event_publisher.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/infrastructure/bluey_logger.dart';
import '../shared/application/log_level.dart';
import 'peer.dart';
import 'peer_connection.dart';
import 'peer_discovery.dart';
import 'server_id.dart';

/// Package-private factory for constructing a [BlueyPeer].
///
/// [borrow] is how the peer reaches candidates while it looks for itself,
/// and [connectionIdOf] names the link of the Connection it found, which
/// the lifecycle client writes with.
BlueyPeer createBlueyPeer({
  required platform.BlueyPlatform platformApi,
  required ServerId serverId,
  required ServerId localIdentity,
  required BlueyLogger logger,
  Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  EventPublisher? events,
  required BorrowConnection borrow,
  required String Function(Connection) connectionIdOf,
}) {
  return _BlueyPeer(
    platformApi: platformApi,
    serverId: serverId,
    localIdentity: localIdentity,
    peerSilenceTimeout: peerSilenceTimeout,
    logger: logger,
    events: events,
    borrow: borrow,
    connectionIdOf: connectionIdOf,
  );
}

class _BlueyPeer implements BlueyPeer {
  final platform.BlueyPlatform _platform;
  final ServerId _localIdentity;
  final Duration _peerSilenceTimeout;
  final BlueyLogger _logger;
  final EventPublisher? _events;
  final BorrowConnection _borrow;
  final String Function(Connection) _connectionIdOf;

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
    required BorrowConnection borrow,
    required String Function(Connection) connectionIdOf,
  }) : _platform = platformApi,
       _localIdentity = localIdentity,
       _peerSilenceTimeout = peerSilenceTimeout,
       _logger = logger,
       _events = events,
       _borrow = borrow,
       _connectionIdOf = connectionIdOf;

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
        borrow: _borrow,
        logger: _logger,
      );
      final Connection connection;
      try {
        connection = await discovery.connectTo(
          serverId,
          scanTimeout: effectiveScanTimeout,
          probeTimeout: effectiveProbeTimeout,
        );
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
      final allServices = await connection.services();

      // Start lifecycle heartbeat. Drives the unreachable-detection path
      // that triggers a local disconnect when the peer goes silent.
      final lifecycleClient = LifecycleClient(
        platformApi: _platform,
        connectionId: _connectionIdOf(connection),
        localIdentity: _localIdentity,
        peerSilenceTimeout: _peerSilenceTimeout,
        onServerUnreachable: () {
          connection.disconnect().catchError((_) {});
        },
        logger: _logger,
        servicesChanges: connection.servicesChanges,
        events: _events,
        deviceAddress: connection.deviceAddress,
        expectedServerId: serverId,
        onIdentityMismatch: (_) {
          connection.disconnect().catchError((_) {});
        },
      );
      lifecycleClient.start(allServices: allServices);

      _logger.log(
        BlueyLogLevel.info,
        'bluey.peer',
        'peer connect resolved',
        data: {
          'serverId': serverId.toString(),
          'deviceId': connection.deviceAddress.toString(),
        },
      );

      return PeerConnection.create(
        connection: connection,
        serverId: serverId,
        lifecycleClient: lifecycleClient,
      );
    } finally {
      _connecting = false;
    }
  }
}
