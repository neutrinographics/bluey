import 'package:bluey/src/features/discovery/domain/advertisement.dart';
import 'package:bluey/src/features/discovery/domain/device.dart';
import 'package:bluey/src/features/discovery/domain/radio_scan.dart';
import 'package:bluey/src/features/discovery/domain/radio_scan_input.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_event.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_id.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

const a = ScannerId(1);
const s1 = ScanId(1);
const s2 = ScanId(2);
const s3 = ScanId(3);
final at = DateTime.utc(2026, 11, 27, 9);
final heart = UUID.short(0x180D);
final battery = UUID.short(0x180F);
final glucose = UUID.short(0x1808);

ScanAsk ask([List<UUID> services = const []]) =>
    ScanAsk(filter: ScanFilter.of(services));

RadioScan after(List<RadioScanInput> inputs) => inputs.fold(
  const RadioScan.quiet(),
  (scan, input) => scan.on(input, at: at).scan,
);

ScanResult showing(List<UUID> services) => ScanResult(
  device: Device(address: const DeviceAddress('AA:BB:CC:DD:EE:01')),
  rssi: -60,
  advertisement: Advertisement(
    serviceUuids: services,
    serviceData: const {},
    isConnectable: true,
  ),
  lastSeen: at,
);

/// Each of [asks] asked by scanner [a] in turn, as scans 1, 2, 3.
RadioScan served(List<ScanAsk> asks) => after([
  const ScannerOpened(a),
  for (var i = 0; i < asks.length; i++) ScanAsked(a, ScanId(i + 1), asks[i]),
]);

/// The scans [scan] delivers [result] to, after checking that hearing it
/// moved nothing and left no duty; a scan ended before it is forgotten, as
/// in every step.
Set<ScanId>? deliveredTo(RadioScan scan, ScanResult result) {
  final step = scan.on(ResultHeard(result), at: at);
  expect(step.duty, isNull);
  expect(step.scan.radio, scan.radio);
  for (final id in [s1, s2, s3]) {
    final before = scan.phaseOf(id);
    expect(step.scan.phaseOf(id), before is Ended ? isNull : before);
  }
  if (step.events.isEmpty) return null;
  expect(step.events, hasLength(1));
  final delivered = step.events.single as ResultDelivered;
  expect(delivered.result, result);
  expect(delivered.at, at);
  return delivered.scans;
}

void main() {
  group('rule 1: an unfiltered scan', () {
    for (final services in [
      <UUID>[],
      [heart],
      [battery, glucose],
    ]) {
      test('gets a result showing ${services.length} services', () {
        // arrange
        final scan = served([ask()]);

        // act
        final scans = deliveredTo(scan, showing(services));

        // assert
        expect(scans, {s1});
      });
    }
  });

  group('rule 2: a filtered scan beside an unfiltered one', () {
    test('gets a result showing its service', () {
      // arrange
      final scan = served([
        ask([heart]),
        ask(),
      ]);

      // act
      final scans = deliveredTo(scan, showing([heart]));

      // assert
      expect(scans, {s1, s2});
    });

    for (final services in [
      <UUID>[],
      [battery],
    ]) {
      test('does not get a result showing ${services.length} other '
          'services', () {
        // arrange
        final scan = served([
          ask([heart]),
          ask(),
        ]);

        // act
        final scans = deliveredTo(scan, showing(services));

        // assert
        expect(scans, {s2});
      });
    }
  });

  group('rule 3: only filtered scans open', () {
    test('a result showing none of their services goes to them all', () {
      // arrange
      final scan = served([
        ask([heart]),
        ask([battery]),
      ]);

      // act
      final scans = deliveredTo(scan, showing([glucose]));

      // assert
      expect(scans, {s1, s2});
    });

    test('a result showing one of their services goes only to its scan', () {
      // arrange
      final scan = served([
        ask([heart]),
        ask([battery]),
      ]);

      // act
      final scans = deliveredTo(scan, showing([heart]));

      // assert
      expect(scans, {s1});
    });

    test('a lone filtered scan trusts the radio for a result showing none', () {
      // arrange
      final scan = served([
        ask([heart]),
      ]);

      // act
      final scans = deliveredTo(scan, showing(const []));

      // assert
      expect(scans, {s1});
    });
  });

  group('scans not served get nothing', () {
    test('a waiting scan and a leaving one', () {
      // arrange
      final scan = after([
        const ScannerOpened(a),
        ScanAsked(a, s1, ask()),
        ScanLeft(s1, const EndedOnRequest()),
        ScanAsked(a, s2, ask()),
      ]);

      // act
      final scans = deliveredTo(scan, showing([heart]));

      // assert
      expect(scan.phaseOf(s1), const Leaving(EndedOnRequest()));
      expect(scan.phaseOf(s2), const Waiting());
      expect(scans, isNull);
    });

    test('a result only the scan that left would have got', () {
      // arrange
      final scan = after([
        const ScannerOpened(a),
        ScanAsked(a, s1, ask([heart])),
        ScanAsked(a, s2, ask([battery])),
        ScanLeft(s2, const EndedOnRequest()),
      ]);

      // act
      final scans = deliveredTo(scan, showing([battery]));

      // assert
      expect(scans, isNull);
    });

    test('an ended scan beside a served one', () {
      // arrange
      final scan = after([
        const ScannerOpened(a),
        ScanAsked(a, s1, ask()),
        ScanAsked(a, s2, ask()),
        ScanLeft(s2, const EndedByTimeout()),
      ]);

      // act
      final scans = deliveredTo(scan, showing([heart]));

      // assert
      expect(scans, {s1});
    });

    test('with no scan at all, nothing is raised', () {
      // arrange
      final scan = after([const ScannerOpened(a)]);

      // act
      final scans = deliveredTo(scan, showing([heart]));

      // assert
      expect(scans, isNull);
    });
  });

  group('ResultDelivered', () {
    test('is equal by value, whatever the order of its scans', () {
      // arrange
      final result = showing([heart]);
      final one = ResultDelivered(result, {s1, s2}, at);

      // act
      final same = ResultDelivered(result, {s2, s1}, at);

      // assert
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(ResultDelivered(result, {s1}, at)));
    });
  });
}
