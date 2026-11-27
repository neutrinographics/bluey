import 'package:bluey/src/api/discovery/scan_event_translation.dart';
import 'package:bluey/src/api/discovery/scan_events.dart';
import 'package:bluey/src/features/discovery/domain/advertisement.dart';
import 'package:bluey/src/features/discovery/domain/device.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_event.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_id.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/shared/application/recording_event_publisher.dart';

const scanner = ScannerId(1);
final at = DateTime.utc(2026, 11, 27, 10);
final heart = UUID.short(0x180D);
final filtered = ScanAsk(
  filter: ScanFilter.of([heart]),
  timeLimit: const Duration(seconds: 10),
);
const everything = ScanAsk(filter: Everything());

void main() {
  group('PublishedScanEvents', () {
    test('a scanner that began starting is a ScanStartingEvent', () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedScanEvents(
        publisher,
      ).raise(ScannerBeganStarting(scanner, filtered, at));

      // assert
      final event = publisher.events.single as ScanStartingEvent;
      expect(event.serviceFilter, [heart]);
      expect(event.timeout, const Duration(seconds: 10));
      expect(event.source, 'BlueyScanner');
      expect(event.timestamp, at);
    });

    test('a scanner that started is a ScanStartedEvent', () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedScanEvents(
        publisher,
      ).raise(ScannerStarted(scanner, filtered, at));

      // assert
      final event = publisher.events.single as ScanStartedEvent;
      expect(event.serviceFilter, [heart]);
      expect(event.timeout, const Duration(seconds: 10));
      expect(event.source, 'BlueyScanner');
      expect(event.timestamp, at);
    });

    test('a scan for everything names no service filter', () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedScanEvents(
        publisher,
      ).raise(ScannerStarted(scanner, everything, at));

      // assert
      final event = publisher.events.single as ScanStartedEvent;
      expect(event.serviceFilter, isNull);
      expect(event.timeout, isNull);
    });

    test('a scanner that began stopping is a ScanStoppingEvent', () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedScanEvents(publisher).raise(ScannerBeganStopping(scanner, at));

      // assert
      final event = publisher.events.single as ScanStoppingEvent;
      expect(event.source, 'BlueyScanner');
      expect(event.timestamp, at);
    });

    for (final end in <ScanEnd>[
      const EndedOnRequest(),
      const EndedByTimeout(),
      const EndedByFailure(ScanRadioUnavailable()),
    ]) {
      test(
        'a scanner stopped for ${end.runtimeType} is a ScanStoppedEvent',
        () {
          // arrange
          final publisher = RecordingEventPublisher();

          // act
          PublishedScanEvents(
            publisher,
          ).raise(ScannerStopped(scanner, end, at));

          // assert
          final event = publisher.events.single as ScanStoppedEvent;
          expect(event.reason, isNull);
          expect(event.source, 'BlueyScanner');
          expect(event.timestamp, at);
        },
      );
    }

    test('a scanner stopped by an outage publishes nothing', () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedScanEvents(publisher).raise(
        ScannerStopped(scanner, const EndedByRadioOutage(RadioOutage.off), at),
      );

      // assert
      expect(publisher.events, isEmpty);
    });

    test('a delivered result is one DeviceDiscoveredEvent', () {
      // arrange
      final publisher = RecordingEventPublisher();
      final result = ScanResult(
        device: Device(
          address: const DeviceAddress('AA:BB:CC:DD:EE:01'),
          name: 'Heart',
        ),
        rssi: -60,
        advertisement: Advertisement(
          serviceUuids: [heart],
          serviceData: const {},
          isConnectable: true,
        ),
        lastSeen: at,
      );

      // act
      PublishedScanEvents(
        publisher,
      ).raise(ResultDelivered(result, {const ScanId(1), const ScanId(2)}, at));

      // assert
      final event = publisher.events.single as DeviceDiscoveredEvent;
      expect(event.deviceAddress, const DeviceAddress('AA:BB:CC:DD:EE:01'));
      expect(event.name, 'Heart');
      expect(event.rssi, -60);
      expect(event.source, isNull);
      expect(event.timestamp, at);
    });

    test('a scan that ended publishes nothing', () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedScanEvents(
        publisher,
      ).raise(ScanEnded(const ScanId(1), const EndedOnRequest(), at));

      // assert
      expect(publisher.events, isEmpty);
    });
  });
}
