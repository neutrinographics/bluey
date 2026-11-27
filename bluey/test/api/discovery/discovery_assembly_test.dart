import 'package:bluey/bluey.dart';
import 'package:bluey/src/api/discovery/discovery_assembly.dart';
import 'package:bluey/src/features/discovery/infrastructure/adapters/platform_scanning.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';
import '../../fixtures/shared/application/recording_event_publisher.dart';
import '../../fixtures/shared/application/recording_log.dart';

void main() {
  late FakeBlueyPlatform fake;
  late RecordingEventPublisher publisher;
  late DiscoveryAssembly discovery;

  setUp(() {
    fake = FakeBlueyPlatform();
    publisher = RecordingEventPublisher();
    final log = RecordingLog();
    DateTime now() => DateTime.utc(2026, 11, 27);
    discovery = DiscoveryAssembly(
      scanning: PlatformScanning(fake, log: log, now: now),
      publisher: publisher,
      log: log,
      now: now,
    );
  });

  test('each scanner it hands out is a new, idle scanner', () {
    // act
    final first = discovery.scanner();
    final second = discovery.scanner();

    // assert
    expect(identical(first, second), isFalse);
    expect(first.state, ScanState.stopped);
    expect(second.state, ScanState.stopped);
  });

  group('dispose', () {
    test('stops the radio a scanner left scanning', () async {
      // arrange
      final scanner = discovery.scanner();
      scanner.scan().listen((_) {});
      await pumpEventQueue();
      expect(fake.isScanning, isTrue);

      // act
      await discovery.dispose();

      // assert
      expect(fake.isScanning, isFalse);
    });

    test('ends every scan and closes every scanner', () async {
      // arrange
      final scanner = discovery.scanner();
      var ended = false;
      scanner.scan().listen((_) {}, onDone: () => ended = true);
      await pumpEventQueue();

      // act
      await discovery.dispose();
      await pumpEventQueue();

      // assert
      expect(ended, isTrue);
      expect(
        () => scanner.scan(),
        throwsA(
          isA<StaleHandleException>().having(
            (e) => e.cause,
            'cause',
            const DisposalInvalidation(),
          ),
        ),
      );
    });

    test('hears nothing the platform reports after it', () async {
      // arrange
      final scanner = discovery.scanner();
      scanner.scan().listen((_) {});
      await pumpEventQueue();
      await discovery.dispose();
      publisher.events.clear();

      // act
      fake.simulateScanResult(
        const platform.PlatformDevice(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'late',
          rssi: -60,
          serviceUuids: [],
          manufacturerDataCompanyId: null,
          manufacturerData: null,
        ),
      );
      await pumpEventQueue();

      // assert
      expect(publisher.events, isEmpty);
    });

    test('is safe to call twice', () async {
      // act
      await discovery.dispose();
      await discovery.dispose();

      // assert
      expect(() => discovery.scanner(), throwsStateError);
    });
  });

  group('devicesAdvertising', () {
    final service = UUID('0000fe00-0000-1000-8000-00805f9b34fb');

    test('listening asks the radio for the service with no stated mode', () async {
      // arrange
      final heard = <DeviceAddress>[];

      // act
      final subscription = discovery.devicesAdvertising(service).listen(
        heard.add,
      );
      await pumpEventQueue();

      // assert
      expect(fake.isScanning, isTrue);
      expect(fake.lastScanConfig?.serviceUuids, [service.toString()]);
      expect(fake.lastScanConfig?.scanMode, isNull);
      await subscription.cancel();
    });

    test('emits the address of each device heard advertising it', () async {
      // arrange
      fake.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'peer',
        serviceUuids: [service.toString()],
      );
      final heard = <DeviceAddress>[];

      // act
      final subscription = discovery.devicesAdvertising(service).listen(
        heard.add,
      );
      await pumpEventQueue();

      // assert
      expect(heard, [const DeviceAddress('AA:BB:CC:DD:EE:01')]);
      await subscription.cancel();
    });

    test('cancelling stops the radio when no other scan is open', () async {
      // arrange
      final subscription = discovery.devicesAdvertising(service).listen((_) {});
      await pumpEventQueue();

      // act
      await subscription.cancel();
      await pumpEventQueue();

      // assert
      expect(fake.isScanning, isFalse);
    });

    test('cancelling leaves another scanner\'s scan running', () async {
      // arrange
      discovery.scanner().scan().listen((_) {});
      final subscription = discovery.devicesAdvertising(service).listen((_) {});
      await pumpEventQueue();

      // act
      await subscription.cancel();
      await pumpEventQueue();

      // assert
      expect(fake.isScanning, isTrue);
    });

    test('two listens are two scanners', () async {
      // arrange
      final first = discovery.devicesAdvertising(service).listen((_) {});
      final second = discovery.devicesAdvertising(service).listen((_) {});
      await pumpEventQueue();

      // act
      await first.cancel();
      await pumpEventQueue();

      // assert
      expect(fake.isScanning, isTrue);
      await second.cancel();
      await pumpEventQueue();
      expect(fake.isScanning, isFalse);
    });

    test('a scan the platform fails adds the translated exception and closes',
        () async {
      // arrange
      fake.simulateScanFailure(StateError('radio refused'));
      final errors = <Object>[];
      var closed = false;

      // act
      discovery
          .devicesAdvertising(service)
          .listen((_) {}, onError: errors.add, onDone: () => closed = true);
      await pumpEventQueue();

      // assert
      expect(errors, hasLength(1));
      expect(errors.single, isA<BlueyException>());
      expect(closed, isTrue);
    });

    test('an outage closes the stream and a new listen works after it',
        () async {
      // arrange
      var closed = false;
      discovery
          .devicesAdvertising(service)
          .listen((_) {}, onDone: () => closed = true);
      await pumpEventQueue();

      // act
      fake.setBluetoothState(platform.BluetoothState.off);
      await pumpEventQueue();
      fake.setBluetoothState(platform.BluetoothState.on);
      await pumpEventQueue();
      final subscription = discovery.devicesAdvertising(service).listen((_) {});
      await pumpEventQueue();

      // assert
      expect(closed, isTrue);
      expect(fake.isScanning, isTrue);
      await subscription.cancel();
    });
  });
}
