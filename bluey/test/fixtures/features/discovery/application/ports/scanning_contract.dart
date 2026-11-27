import 'package:bluey/bluey.dart' show Advertisement, Device, DeviceAddress;
import 'package:bluey/src/features/discovery/application/ports/scanning.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_mode.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [scanningContract] needs from the [Scanning] it holds to
/// account: a way to put the radio into each situation the contract describes.
///
/// The in-memory double is its own harness; the platform adapter's harness
/// drives `FakeBlueyPlatform`, so both are held to the same promises.
abstract class ScanningHarness {
  /// The port under contract.
  Scanning get scanning;

  /// The radio hears [result].
  void hear(ScanResult result);

  /// The radio refuses the running scan for [reason].
  void refuse(ScanRefusalReason reason);

  /// Makes the next stop fail.
  void failNextStop();

  /// Makes the next stop settle only when [releaseStop] is called.
  void holdNextStop();

  /// Lets a held stop settle.
  void releaseStop();

  /// The adapter leaves `on` for [outage].
  void outage(RadioOutage outage);

  /// What the radio scans for, or null when it is not scanning.
  ScanCoverage? get scanningFor;
}

const _everything = ScanCoverage(filter: Everything());
const _balanced = ScanCoverage(filter: Everything(), mode: ScanMode.balanced);

ScanResult _result(String address) => ScanResult(
  device: Device(address: DeviceAddress(address), name: 'Device'),
  rssi: -60,
  advertisement: Advertisement(
    serviceUuids: const [],
    serviceData: const {},
    isConnectable: true,
  ),
  lastSeen: DateTime.utc(2026, 11, 27),
);

/// The promises every [Scanning] keeps, which the application layer's units
/// are written against, so a unit tested over the double behaves the same
/// over the platform.
void scanningContract(String name, ScanningHarness Function() create) {
  group(name, () {
    late ScanningHarness h;

    setUp(() => h = create());

    test('a result heard after a scan arrives as heard', () async {
      // arrange
      final result = _result('AA:BB:CC:DD:EE:01');
      final reports = h.scanning.reports;
      h.scanning.scan(_everything);

      // act
      h.hear(result);

      // assert
      await expectLater(reports, emits(Heard(result)));
    });

    test('nothing is heard before a scan', () async {
      // arrange
      final heard = <ScanReport>[];
      final subscription = h.scanning.reports.listen(heard.add);

      // act
      h.hear(_result('AA:BB:CC:DD:EE:01'));
      await pumpEventQueue();

      // assert
      expect(heard, isEmpty);
      await subscription.cancel();
    });

    test('nothing is heard after a stop', () async {
      // arrange
      final heard = <ScanReport>[];
      final subscription = h.scanning.reports.listen(heard.add);
      h.scanning.scan(_everything);
      await h.scanning.stop();

      // act
      h.hear(_result('AA:BB:CC:DD:EE:01'));
      await pumpEventQueue();

      // assert
      expect(heard, isEmpty);
      await subscription.cancel();
    });

    test('a second scan replaces the first and results keep arriving on the '
        'same reports', () async {
      // arrange
      final first = _result('AA:BB:CC:DD:EE:01');
      final second = _result('AA:BB:CC:DD:EE:02');
      final reports = h.scanning.reports;
      h.scanning.scan(_everything);
      h.hear(first);

      // act
      h.scanning.scan(_balanced);
      h.hear(second);

      // assert
      expect(h.scanningFor, _balanced);
      await expectLater(reports, emitsInOrder([Heard(first), Heard(second)]));
    });

    test('stop answers success and leaves the radio not scanning', () async {
      // arrange
      h.scanning.scan(_everything);

      // act
      final answer = await h.scanning.stop();

      // assert
      expect(answer, const Right<ScanFailure, void>(null));
      expect(h.scanningFor, isNull);
    });

    test('stop with nothing scanning answers success', () async {
      // arrange
      // (the radio is idle)

      // act
      final answer = await h.scanning.stop();

      // assert
      expect(answer, const Right<ScanFailure, void>(null));
    });

    test('a failed stop answers why', () async {
      // arrange
      h.scanning.scan(_everything);
      h.failNextStop();

      // act
      final answer = await h.scanning.stop();

      // assert
      expect(
        answer,
        isA<Left<ScanFailure, void>>().having(
          (left) => left.value,
          'failure',
          isA<UnexpectedScanFailure>(),
        ),
      );
    });

    test('after a failed stop the radio is still scanning', () async {
      // arrange
      h.scanning.scan(_everything);
      h.failNextStop();

      // act
      await h.scanning.stop();

      // assert
      expect(h.scanningFor, _everything);
    });

    test('a held stop does not answer until it is released', () async {
      // arrange
      h.scanning.scan(_everything);
      h.holdNextStop();
      var answered = false;
      final stop = h.scanning.stop().then((answer) {
        answered = true;
        return answer;
      });

      // act
      await pumpEventQueue();
      final answeredWhileHeld = answered;
      h.releaseStop();

      // assert
      expect(answeredWhileHeld, isFalse);
      expect(await stop, const Right<ScanFailure, void>(null));
    });

    test(
      'a refusal arrives as refused and leaves the radio not scanning',
      () async {
        // arrange
        final reports = h.scanning.reports;
        h.scanning.scan(_everything);

        // act
        h.refuse(ScanRefusalReason.startedTooOften);

        // assert
        await expectLater(
          reports,
          emits(const Refused(ScanRefused(ScanRefusalReason.startedTooOften))),
        );
        expect(h.scanningFor, isNull);
      },
    );

    test('a refusal while idle delivers nothing', () async {
      // arrange
      final heard = <ScanReport>[];
      final subscription = h.scanning.reports.listen(heard.add);

      // act
      h.refuse(ScanRefusalReason.startedTooOften);
      await pumpEventQueue();

      // assert
      expect(heard, isEmpty);
      await subscription.cancel();
    });

    test('nothing is heard after a refusal', () async {
      // arrange
      final heard = <ScanReport>[];
      final subscription = h.scanning.reports.listen(heard.add);
      h.scanning.scan(_everything);
      h.refuse(ScanRefusalReason.startedTooOften);
      await pumpEventQueue();
      heard.clear();

      // act
      h.hear(_result('AA:BB:CC:DD:EE:01'));
      await pumpEventQueue();

      // assert
      expect(heard, isEmpty);
      await subscription.cancel();
    });

    test('a stop after a replaced scan answers success and nothing more is '
        'heard', () async {
      // arrange
      final heard = <ScanReport>[];
      final subscription = h.scanning.reports.listen(heard.add);
      h.scanning.scan(_everything);
      h.scanning.scan(_balanced);
      final answer = await h.scanning.stop();
      await pumpEventQueue();

      // act
      h.hear(_result('AA:BB:CC:DD:EE:01'));
      await pumpEventQueue();

      // assert
      expect(answer, const Right<ScanFailure, void>(null));
      expect(h.scanningFor, isNull);
      expect(heard, isEmpty);
      await subscription.cancel();
    });

    test('the reports never carry an error', () async {
      // arrange
      final errors = <Object>[];
      final subscription = h.scanning.reports.listen(
        (_) {},
        onError: errors.add,
      );
      h.scanning.scan(_everything);

      // act
      h.refuse(ScanRefusalReason.internalError);
      h.failNextStop();
      await h.scanning.stop();
      await pumpEventQueue();

      // assert
      expect(errors, isEmpty);
      await subscription.cancel();
    });

    test('an outage arrives on outages', () async {
      // arrange
      final heard = <RadioOutage>[];
      final subscription = h.scanning.outages.listen(heard.add);

      // act
      h.outage(RadioOutage.off);
      await pumpEventQueue();

      // assert
      expect(heard, [RadioOutage.off]);
      await subscription.cancel();
    });
  });
}
