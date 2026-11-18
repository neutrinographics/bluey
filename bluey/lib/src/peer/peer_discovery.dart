import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../api/connection/borrowed_connection.dart';
import '../api/connection/connection.dart';
import '../shared/domain/device_address.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/infrastructure/bluey_logger.dart';
import '../shared/application/log_level.dart';
import '../shared/exceptions.dart';
import 'server_id.dart';

/// Finds Bluey peers by borrowing each scan candidate's link to read its
/// [ServerId], so a device the app is already linked to is read over the
/// app's link and left as it was, and a link opened for the probe is given
/// back. Internal to the `Bluey` facade.
class PeerDiscovery {
  /// Default probe-connect timeout. A single unresponsive candidate
  /// shouldn't stall the whole discovery session, so each probe is
  /// bounded short. 3 s is a heuristic balance: long enough that a
  /// briefly-asleep peripheral can wake and respond, short enough that
  /// 10 dead candidates only add ~30 s to discovery rather than ~5 min
  /// (the platform default).
  static const Duration defaultProbeTimeout = Duration(seconds: 3);

  final platform.BlueyPlatform _platform;
  final BorrowConnection _borrow;
  final BlueyLogger _logger;

  /// Creates a [PeerDiscovery] that scans through [platformApi] and reaches
  /// each candidate through [borrow].
  PeerDiscovery({
    required platform.BlueyPlatform platformApi,
    required BorrowConnection borrow,
    required BlueyLogger logger,
  }) : _platform = platformApi,
       _borrow = borrow,
       _logger = logger;

  /// Scans for Bluey servers, briefly borrows each one's link to read its
  /// [ServerId], and returns a deduplicated list.
  ///
  /// [timeout] bounds the scan window: only candidates seen inside it are
  /// probed, and the result waits for the probe still in flight when it
  /// closes.
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
    // serialized (one borrowed link at a time): overlapping
    // connect attempts are where mobile BLE stacks get flaky.
    var probeChain = Future<void>.value();
    final windowClosed = Completer<void>();

    Future<void> probe(String address) async {
      if (windowClosed.isCompleted) return;
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
        if (windowClosed.isCompleted) return;
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
      // Queued probes return at once; only the one in flight is awaited.
      await probeChain;
    } finally {
      deadline.cancel();
      // Not awaited — see the matching note in [connectTo].
      unawaited(sub.cancel());
      await _stopScan('discoverPeers');
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
      final BorrowedConnection borrowed;
      try {
        borrowed = await _borrow(DeviceAddress(address), timeout: probeTimeout);
      } catch (_) {
        // Skip candidates that fail to connect.
        return;
      }
      try {
        final id = await _readServerId(borrowed.connection);
        if (!completer.isCompleted && id == expected) {
          // The caller takes this link over, so the borrow ends by
          // handing it to the app rather than closing it.
          borrowed.keep();
          completer.complete(borrowed.connection);
          return;
        }
      } catch (_) {
        // Skip candidates that fail to read.
      }
      await _giveBack(borrowed);
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
      await _stopScan('connectTo');
    }
  }

  /// Stops the scan, logging a failure rather than raising it: by the time
  /// the scan is stopped the caller's answer is already known, and a radio
  /// that refuses to stop must not turn it into an error.
  Future<void> _stopScan(String operation) async {
    try {
      await _platform.stopScan();
    } catch (e) {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.peer.discovery',
        '$operation stopScan failed',
        data: {'exception': e.runtimeType.toString()},
      );
    }
  }

  /// Borrows the link to [address], reads its [ServerId] over it and gives
  /// the link back, so a link the app holds stays exactly as it was.
  Future<ServerId> _probeServerId(String address, Duration probeTimeout) async {
    final borrowed = await _borrow(
      DeviceAddress(address),
      timeout: probeTimeout,
    );
    try {
      return await _readServerId(borrowed.connection);
    } finally {
      await _giveBack(borrowed);
    }
  }

  /// Ends a borrow, logging a close that failed rather than raising it: the
  /// probe's answer does not depend on the link closing, and the link stays
  /// up for whoever needs it next.
  Future<void> _giveBack(BorrowedConnection borrowed) async {
    try {
      await borrowed.giveBack();
    } catch (e) {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.peer.discovery',
        'probe give-back failed',
        data: {
          'deviceId': borrowed.connection.deviceAddress.toString(),
          'exception': e.runtimeType.toString(),
        },
      );
    }
  }

  /// Reads the serverId characteristic of [connection]'s control service,
  /// the way the app would, so services already discovered are reused.
  Future<ServerId> _readServerId(Connection connection) async {
    final services = await connection.services(cache: true);
    final controlService =
        services
            .where((s) => lifecycle.isControlService(s.uuid.toString()))
            .firstOrNull;
    if (controlService == null) {
      throw StateError(
        'peer probe: control service not present on '
        '${connection.deviceAddress}',
      );
    }
    final serverIdChar =
        controlService
            .characteristics()
            .where(
              (c) =>
                  c.uuid.toString().toLowerCase() == lifecycle.serverIdCharUuid,
            )
            .firstOrNull;
    if (serverIdChar == null) {
      throw StateError(
        'peer probe: serverId characteristic not present on '
        '${connection.deviceAddress}',
      );
    }
    final bytes = await serverIdChar.read();
    return lifecycle.lifecycleCodec.decodeAdvertisedIdentity(bytes);
  }
}
