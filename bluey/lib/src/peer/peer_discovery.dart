import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../lifecycle.dart' as lifecycle;
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
  final platform.BlueyPlatform _platform;

  /// Creates a [PeerDiscovery] backed by the given platform API.
  PeerDiscovery({required platform.BlueyPlatform platformApi})
      : _platform = platformApi;

  /// Scans for Bluey servers, briefly connects to each to read its
  /// [ServerId], and returns a deduplicated list.
  ///
  /// [timeout] bounds the scan phase. After the timeout, the scan is
  /// stopped and the collected candidates are probed sequentially.
  Future<List<ServerId>> discover({required Duration timeout}) async {
    final candidates = await _collectCandidates(timeout);
    final ids = <ServerId>{};
    for (final address in candidates) {
      try {
        final id = await _probeServerId(address);
        ids.add(id);
      } catch (_) {
        // Skip candidates that fail to connect or read.
      }
    }
    return ids.toList();
  }

  /// Scans for Bluey servers and returns an open [Connection] to the
  /// first one whose [ServerId] matches [expected].
  ///
  /// [scanTimeout] bounds the discovery phase. If no match is found
  /// within the scan window, throws [PeerNotFoundException].
  /// [timeout] optionally bounds each individual connect attempt.
  Future<Connection> connectTo(
    ServerId expected, {
    required Duration scanTimeout,
    Duration? timeout,
  }) async {
    final candidates = await _collectCandidates(scanTimeout);
    for (final address in candidates) {
      try {
        final id = await _readServerIdRaw(address);
        if (id == expected) {
          // The probe left the device connected. Build a full
          // BlueyConnection for the caller.
          return BlueyConnection(
            platformInstance: _platform,
            connectionId: address,
            deviceId: deviceIdToUuid(address),
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

  /// Scans broadly (no filter) and collects all device addresses as
  /// candidates. Each candidate is probed individually to check for
  /// the Bluey control service.
  Future<Set<String>> _collectCandidates(Duration timeout) async {
    final addresses = <String>{};
    final scanConfig = platform.PlatformScanConfig(
      serviceUuids: const [],
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
  Future<ServerId> _probeServerId(String address) async {
    final id = await _readServerIdRaw(address);
    await _platform.disconnect(address);
    return id;
  }

  /// Connects, discovers services, reads the serverId characteristic,
  /// and returns the decoded [ServerId]. Leaves the connection open.
  Future<ServerId> _readServerIdRaw(String address) async {
    final config = const platform.PlatformConnectConfig(
      timeoutMs: null,
      mtu: null,
    );
    await _platform.connect(address, config);
    await _platform.discoverServices(address);
    final bytes = await _platform.readCharacteristic(
      address,
      lifecycle.serverIdCharUuid,
    );
    return lifecycle.decodeServerId(bytes);
  }

}
