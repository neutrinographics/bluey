import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/api/discovery/discovery_assembly.dart';
import 'package:bluey/src/features/discovery/infrastructure/adapters/platform_scanning.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';
import '../../fixtures/shared/application/recording_event_publisher.dart';
import '../../fixtures/shared/application/recording_log.dart';

const _heartRate = '0000180d-0000-1000-8000-00805f9b34fb';
const _battery = '0000180f-0000-1000-8000-00805f9b34fb';
final _now = DateTime.utc(2026, 11, 27, 9, 30);

void main() {
  late FakeBlueyPlatform fake;
  late RecordingEventPublisher publisher;
  late DiscoveryAssembly discovery;

  DiscoveryAssembly assembled({DateTime Function()? now}) {
    final log = RecordingLog();
    final clock = now ?? () => _now;
    return DiscoveryAssembly(
      scanning: PlatformScanning(fake, log: log, now: clock),
      publisher: publisher,
      log: log,
      now: clock,
    );
  }

  setUp(() {
    fake = FakeBlueyPlatform();
    publisher = RecordingEventPublisher();
    discovery = assembled();
  });

  tearDown(() => discovery.dispose());

  group('a scan restarted without awaiting the cancel', () {
    test('the second scan delivers results', () async {
      // arrange
      fake.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01', name: 'x');
      final scanner = discovery.scanner();
      final first = scanner.scan().listen((_) {});
      await pumpEventQueue();
      final results = <ScanResult>[];

      // act
      unawaited(first.cancel());
      final second = scanner.scan().listen(results.add);
      await pumpEventQueue();

      // assert
      expect(results, isNotEmpty);
      expect(scanner.isScanning, isTrue);
      await second.cancel();
      scanner.dispose();
    });

    test('the platform scans exactly while the scanner says so', () async {
      // arrange
      fake.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01', name: 'x');
      final scanner = discovery.scanner();
      final first = scanner.scan().listen((_) {});
      await pumpEventQueue();

      // act
      unawaited(first.cancel());
      scanner.scan().listen((_) {});
      await pumpEventQueue();

      // assert
      expect(fake.isScanning, scanner.isScanning);
    });
  });

  test('dispose while scanning stops the platform scan', () async {
    // arrange
    final scanner = discovery.scanner();
    scanner.scan().listen((_) {});
    await pumpEventQueue();
    expect(fake.isScanning, isTrue);

    // act
    scanner.dispose();
    await pumpEventQueue();

    // assert
    expect(fake.isScanning, isFalse);
  });

  test('two scanners with different filters each get their own', () async {
    // arrange
    fake.simulatePeripheral(
      id: 'AA:BB:CC:DD:EE:01',
      name: 'Heart',
      serviceUuids: [_heartRate],
    );
    fake.simulatePeripheral(
      id: 'AA:BB:CC:DD:EE:02',
      name: 'Battery',
      serviceUuids: [_battery],
    );
    final hearts = <String?>[];
    final batteries = <String?>[];

    // act
    discovery
        .scanner()
        .scan(services: [UUID(_heartRate)])
        .listen((result) => hearts.add(result.device.name));
    await pumpEventQueue();
    discovery
        .scanner()
        .scan(services: [UUID(_battery)])
        .listen((result) => batteries.add(result.device.name));
    await pumpEventQueue();

    // assert
    expect(hearts.toSet(), {'Heart'});
    expect(batteries.toSet(), {'Battery'});
  });

  group('a refused scan', () {
    test('ends its stream with ScanFailedException', () async {
      // arrange
      final scanner = discovery.scanner();
      final errors = <Object>[];
      final done = Completer<void>();
      scanner.scan().listen((_) {}, onError: errors.add, onDone: done.complete);
      await pumpEventQueue();

      // act
      fake.simulateScanRefusal(
        platform.PlatformScanFailureReason.registrationFailed,
      );
      await done.future;

      // assert
      expect(errors, [
        isA<ScanFailedException>().having(
          (e) => e.reason,
          'reason',
          ScanFailureReason.registrationFailed,
        ),
      ]);
      expect(scanner.state, ScanState.stopped);
    });

    test('leaves the scanner able to scan again', () async {
      // arrange
      fake.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01', name: 'x');
      final scanner = discovery.scanner();
      scanner.scan().listen((_) {}, onError: (_) {});
      await pumpEventQueue();
      fake.simulateScanRefusal(
        platform.PlatformScanFailureReason.registrationFailed,
      );
      await pumpEventQueue();
      final results = <ScanResult>[];

      // act
      scanner.scan().listen(results.add);
      await pumpEventQueue();

      // assert
      expect(results, isNotEmpty);
      expect(scanner.state, ScanState.scanning);
    });
  });

  test('a time limit ends the stream at exactly its instant', () {
    fakeAsync((async) {
      // arrange
      final timed = assembled(now: () => async.getClock(_now).now());
      final scanner = timed.scanner();
      Duration? endedAfter;
      final started = async.elapsed;

      // act
      scanner
          .scan(timeout: const Duration(milliseconds: 100))
          .listen((_) {}, onDone: () => endedAfter = async.elapsed - started);
      async.elapse(const Duration(milliseconds: 99));
      final openBefore = endedAfter == null;
      async.elapse(const Duration(milliseconds: 1));

      // assert
      expect(openBefore, isTrue);
      expect(endedAfter, const Duration(milliseconds: 100));
      expect(fake.lastScanConfig?.timeoutMs, isNull);
      expect(scanner.isScanning, isFalse);
      unawaited(timed.dispose());
      async.flushMicrotasks();
    });
  });

  group('the events a single scanner publishes', () {
    test('come in the order they always did', () async {
      // arrange
      fake.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01', name: 'x');
      final scanner = discovery.scanner();

      // act
      final scan = scanner.scan().listen((_) {});
      await pumpEventQueue();
      await scan.cancel();
      await pumpEventQueue();

      // assert
      expect(publisher.events.map((e) => e.runtimeType), [
        ScanStartingEvent,
        ScanStartedEvent,
        DeviceDiscoveredEvent,
        ScanStoppingEvent,
        ScanStoppedEvent,
      ]);
    });

    test('are stamped with the clock the assembly is handed', () async {
      // arrange
      fake.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01', name: 'x');
      final scanner = discovery.scanner();

      // act
      final scan = scanner.scan().listen((_) {});
      await pumpEventQueue();
      await scan.cancel();
      await pumpEventQueue();

      // assert
      expect(publisher.events, isNotEmpty);
      expect(publisher.events.map((e) => e.timestamp).toSet(), {_now});
    });
  });

  test('a stop the platform fails throws the translated exception', () async {
    // arrange
    final scanner = discovery.scanner();
    scanner.scan().listen((_) {});
    await pumpEventQueue();
    fake.enqueueFault(
      FakeOp.stopScan,
      const platform.PlatformPermissionDeniedException(
        'stopScan',
        permission: 'BLUETOOTH_SCAN',
      ),
    );

    // act
    final stopping = scanner.stop();

    // assert
    await expectLater(
      stopping,
      throwsA(
        isA<PermissionDeniedException>().having(
          (e) => e.permissions,
          'permissions',
          ['BLUETOOTH_SCAN'],
        ),
      ),
    );
  });
}
