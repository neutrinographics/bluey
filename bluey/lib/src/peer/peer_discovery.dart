import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../lifecycle.dart' as lifecycle;
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
import '../shared/device_id_coercion.dart';
import '../shared/exceptions.dart';
import 'server_id.dart';

/// Stateless helper that orchestrates scan + connect + serverId read
/// for discovering Bluey peers and connecting to a specific one.
///
/// `PeerDiscovery` operates at the platform layer, creating lightweight
/// platform connections to probe each scan candidate for its [ServerId].
/// It is used internally by the `Bluey` facade and is not part of the
/// public API.
class PeerDiscovery {
  /// Default probe-connect timeout. A single unresponsive candidate
  /// shouldn't stall the whole discovery session, so each probe is
  /// bounded short. 3 s is a heuristic balance: long enough that a
  /// briefly-asleep peripheral can wake and respond, short enough that
  /// 10 dead candidates only add ~30 s to discovery rather than ~5 min
  /// (the platform default — see I056).
  static const Duration defaultProbeTimeout = Duration(seconds: 3);

  final platform.BlueyPlatform _platform;
  final BlueyLogger _logger;

  /// Creates a [PeerDiscovery] backed by the given platform API.
  PeerDiscovery({
    required platform.BlueyPlatform platformApi,
    required BlueyLogger logger,
  })  : _platform = platformApi,
        _logger = logger;

  /// Scans for Bluey servers, briefly connects to each to read its
  /// [ServerId], and returns a deduplicated list.
  ///
  /// [timeout] bounds the scan phase. After the timeout, the scan is
  /// stopped and the collected candidates are probed sequentially.
  /// [probeTimeout] bounds each individual probe-connect attempt;
  /// defaults to [defaultProbeTimeout].
  Future<List<ServerId>> discover({
    required Duration timeout,
    Duration probeTimeout = defaultProbeTimeout,
  }) async {
    _logger.log(
      BlueyLogLevel.info,
      'bluey.peer.discovery',
      'discoverPeers scan started',
      data: {'timeoutMs': timeout.inMilliseconds},
    );
    final candidates = await _collectCandidates(timeout);
    final ids = <ServerId>{};
    for (final address in candidates) {
      _logger.log(
        BlueyLogLevel.debug,
        'bluey.peer.discovery',
        'discoverPeers probe attempt',
        data: {'deviceId': address},
      );
      try {
        final id = await _probeServerId(address, probeTimeout);
        ids.add(id);
        _logger.log(
          BlueyLogLevel.info,
          'bluey.peer.discovery',
          'discoverPeers probe success',
          data: {
            'deviceId': address,
            'serverId': id.toString(),
          },
        );
      } catch (e) {
        _logger.log(
          BlueyLogLevel.debug,
          'bluey.peer.discovery',
          'discoverPeers probe failure',
          data: {
            'deviceId': address,
            'exception': e.runtimeType.toString(),
          },
        );
        // Skip candidates that fail to connect or read.
      }
    }
    _logger.log(
      BlueyLogLevel.info,
      'bluey.peer.discovery',
      'discoverPeers stopped',
      data: {
        'candidates': candidates.length,
        'matched': ids.length,
      },
    );
    return ids.toList();
  }

  /// Scans for Bluey servers and returns an open [Connection] to the
  /// first one whose [ServerId] matches [expected].
  ///
  /// [scanTimeout] bounds the discovery phase. If no match is found
  /// within the scan window, throws [PeerNotFoundException].
  /// [probeTimeout] bounds each individual probe-connect attempt;
  /// defaults to [defaultProbeTimeout].
  Future<Connection> connectTo(
    ServerId expected, {
    required Duration scanTimeout,
    Duration probeTimeout = defaultProbeTimeout,
  }) async {
    final candidates = await _collectCandidates(scanTimeout);
    for (final address in candidates) {
      try {
        final id = await _readServerIdRaw(address, probeTimeout);
        if (id == expected) {
          // The probe left the device connected. Build a full
          // BlueyConnection for the caller.
          return BlueyConnection(
            platformInstance: _platform,
            connectionId: address,
            deviceId: deviceIdToUuid(address),
            logger: _logger,
          );
        }
        // Not a match — disconnect.
        await _platform.disconnect(address);
      } catch (_) {
        // Skip candidates that fail to connect or read.
        try {
          await _platform.disconnect(address);
        } catch (_) {}
      }
    }
    throw PeerNotFoundException(expected, scanTimeout);
  }

  /// Scans for peripherals advertising the Bluey lifecycle control
  /// service UUID and collects their addresses. Filtering at the OS
  /// level is the only way to keep probe time O(matches) rather than
  /// O(nearby BLE devices) — see I055. Servers must opt in via
  /// `Server.startAdvertising(peerDiscoverable: true)` for their
  /// advertisements to surface here.
  Future<Set<String>> _collectCandidates(Duration timeout) async {
    final addresses = <String>{};
    final scanConfig = platform.PlatformScanConfig(
      serviceUuids: [lifecycle.controlServiceUuid],
      timeoutMs: timeout.inMilliseconds,
    );
    await for (final result in _platform.scan(scanConfig).timeout(
          timeout,
          onTimeout: (sink) => sink.close(),
        )) {
      addresses.add(result.id);
    }
    await _platform.stopScan();
    return addresses;
  }

  /// Connects to a peripheral via the raw platform API, discovers
  /// services, reads the serverId characteristic, disconnects, and
  /// returns the decoded [ServerId].
  ///
  /// Uses platform calls directly (not [BlueyConnection]) to avoid
  /// starting lifecycle heartbeats on throw-away probe connections.
  Future<ServerId> _probeServerId(String address, Duration probeTimeout) async {
    final id = await _readServerIdRaw(address, probeTimeout);
    await _platform.disconnect(address);
    return id;
  }

  /// Connects, discovers services, reads the serverId characteristic,
  /// and returns the decoded [ServerId]. Leaves the connection open.
  Future<ServerId> _readServerIdRaw(
    String address,
    Duration probeTimeout,
  ) async {
    final config = platform.PlatformConnectConfig(
      timeoutMs: probeTimeout.inMilliseconds,
      mtu: null,
    );
    await _platform.connect(address, config);
    final services = await _platform.discoverServices(address);
    // Find the serverId characteristic in the control service tree —
    // platform reads are now keyed by handle (D.13), so we resolve
    // here from the discovery output rather than passing UUID.
    final controlService = services
        .where((s) =>
            s.uuid.toLowerCase() == lifecycle.controlServiceUuid)
        .firstOrNull;
    if (controlService == null) {
      throw StateError(
        'peer probe: control service not present on $address',
      );
    }
    final serverIdChar = controlService.characteristics
        .where((c) => c.uuid.toLowerCase() == lifecycle.serverIdCharUuid)
        .firstOrNull;
    if (serverIdChar == null) {
      throw StateError(
        'peer probe: serverId characteristic not present on $address',
      );
    }
    final bytes = await _platform.readCharacteristic(
      address,
      serverIdChar.handle,
    );
    return lifecycle.decodeServerId(bytes);
  }

}
