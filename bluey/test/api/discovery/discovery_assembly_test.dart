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
}
