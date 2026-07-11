import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../discovery/device_address.dart';
import '../event_bus.dart';
import '../lifecycle.dart' as lifecycle;
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
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
  /// (the platform default).
  static const Duration defaultProbeTimeout = Duration(seconds: 3);

  final platform.BlueyPlatform _platform;
  final BlueyLogger _logger;
  final EventPublisher? _events;

  /// Creates a [PeerDiscovery] backed by the given platform API.
  ///
  /// [events] is forwarded into the [BlueyConnection] returned by
  /// [connectTo] so GATT-op events fire on the parent `Bluey`'s
  /// stream. Optional — null in test contexts that don't need
  /// emissions.
  PeerDiscovery({
    required platform.BlueyPlatform platformApi,
    required BlueyLogger logger,
    EventPublisher? events,
  }) : _platform = platformApi,
       _logger = logger,
       _events = events;

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
    final ids = <ServerId>{};
    final probed = <String>{};
    // I349 — probe-as-you-scan: candidates are probed while the scan
    // window is still open, so results are ready at window close
    // instead of window-close-plus-N-sequential-probes. Probes stay
    // serialized (one throw-away connection at a time): overlapping
    // connect attempts are where mobile BLE stacks get flaky.
    var probeChain = Future<void>.value();
    final windowClosed = Completer<void>();

    Future<void> probe(String address) async {
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
          data: {'deviceId': address, 'serverId': id.toString()},
        );
      } catch (e) {
        _logger.log(
          BlueyLogLevel.debug,
          'bluey.peer.discovery',
          'discoverPeers probe failure',
          data: {'deviceId': address, 'exception': e.runtimeType.toString()},
        );
        // Skip candidates that fail to connect or read.
      }
    }

    final scanConfig = platform.PlatformScanConfig(
      serviceUuids: [lifecycle.controlServiceUuid],
      timeoutMs: timeout.inMilliseconds,
    );
    final sub = _platform.scan(scanConfig).listen(
      (device) {
        if (!probed.add(device.id)) return;
        probeChain = probeChain.then((_) => probe(device.id));
      },
      onError: (Object e) {
        if (!windowClosed.isCompleted) windowClosed.completeError(e);
      },
      onDone: () {
        if (!windowClosed.isCompleted) windowClosed.complete();
      },
    );
    final deadline = Timer(timeout, () {
      if (!windowClosed.isCompleted) windowClosed.complete();
    });

    try {
      await windowClosed.future;
      // Let any probe already in flight finish before reporting.
      await probeChain;
    } finally {
      deadline.cancel();
      // Not awaited — see the matching note in [connectTo].
      unawaited(sub.cancel());
      await _platform.stopScan();
    }
    _logger.log(
      BlueyLogLevel.info,
      'bluey.peer.discovery',
      'discoverPeers stopped',
      data: {'candidates': probed.length, 'matched': ids.length},
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
    // I349 — probe-as-you-scan: each candidate is probed as the scan
    // emits it, and the first identity match completes the connect
    // immediately (scan cancelled). [scanTimeout] bounds only the
    // failure path; it is no longer a floor on connect latency.
    final completer = Completer<Connection>();
    final probed = <String>{};
    var probeChain = Future<void>.value();

    Future<void> probe(String address) async {
      if (completer.isCompleted) return;
      try {
        final id = await _readServerIdRaw(address, probeTimeout);
        if (!completer.isCompleted && id == expected) {
          // The probe left the device connected. Build a full
          // BlueyConnection for the caller.
          completer.complete(
            BlueyConnection(
              platformInstance: _platform,
              connectionId: address,
              deviceAddress: DeviceAddress(address),
              logger: _logger,
              events: _events,
            ),
          );
          return;
        }
        // Not a match (or a match raced a completed future) — the
        // probe connection is not needed.
        await _platform.disconnect(address);
      } catch (_) {
        // Skip candidates that fail to connect or read.
        try {
          await _platform.disconnect(address);
        } catch (_) {}
      }
    }

    final scanConfig = platform.PlatformScanConfig(
      serviceUuids: [lifecycle.controlServiceUuid],
      timeoutMs: scanTimeout.inMilliseconds,
    );
    final sub = _platform.scan(scanConfig).listen(
      (device) {
        if (!probed.add(device.id)) return;
        probeChain = probeChain.then((_) => probe(device.id));
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    final deadline = Timer(scanTimeout, () {
      // A probe that started inside the window may still be in flight;
      // let it settle before declaring failure.
      probeChain.whenComplete(() {
        if (!completer.isCompleted) {
          completer.completeError(
            PeerNotFoundException(expected, scanTimeout),
          );
        }
      });
    });

    try {
      return await completer.future;
    } finally {
      deadline.cancel();
      // Deliberately not awaited: a broadcast-subscription cancel with
      // no onCancel returns the root-zone null-future, and awaiting it
      // escapes fakeAsync (parking the caller on the real event loop).
      // stopScan is the authoritative radio-stop.
      unawaited(sub.cancel());
      await _platform.stopScan();
    }
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
    final controlService =
        services
            .where((s) => s.uuid.toLowerCase() == lifecycle.controlServiceUuid)
            .firstOrNull;
    if (controlService == null) {
      throw StateError('peer probe: control service not present on $address');
    }
    final serverIdChar =
        controlService.characteristics
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
    return lifecycle.lifecycleCodec.decodeAdvertisedIdentity(bytes);
  }
}
