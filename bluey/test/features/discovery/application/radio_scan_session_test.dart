import 'package:bluey/src/features/discovery/application/open_scan.dart';
import 'package:bluey/src/features/discovery/domain/scan_event.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_id.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/discovery/application/radio_scan_rig.dart';

OpenScan opened(Either<Object, OpenScan> answer) => answer.fold(
  (failure) => fail('the scan was refused: $failure'),
  (scan) => scan,
);

void main() {
  group('one scanner with one scan', () {
    test('the radio is asked once, results flow, and leaving stops the radio '
        'and tells every step at the injected instant', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        final ask = askFor();
        final scan = opened(scanner.scan(ask));
        final results = <ScanResult>[];
        ScanEnd? end;
        scan.results.listen(results.add);
        scan.ended.then((value) => end = value);
        final result = advertising([heart]);
        rig.scanning.hear(result);
        async.flushMicrotasks();

        // act
        scan.leave();
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.scansAsked, 1);
        expect(rig.scanning.stopsAsked, 1);
        expect(results, [result]);
        expect(end, const EndedOnRequest());
        expect(rig.events.raised, [
          ScannerBeganStarting(const ScannerId(1), ask, rigInstant),
          ScannerStarted(const ScannerId(1), ask, rigInstant),
          ResultDelivered(result, {const ScanId(1)}, rigInstant),
          ScannerBeganStopping(const ScannerId(1), rigInstant),
          ScanEnded(const ScanId(1), const EndedOnRequest(), rigInstant),
          ScannerStopped(
            const ScannerId(1),
            const EndedOnRequest(),
            rigInstant,
          ),
        ]);
      });
    });
  });

  group('two scanners with different services', () {
    test('the radio is widened for the second and each gets only its own '
        'results', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final first = opened(rig.session.openScanner().scan(askFor([heart])));
        final second = opened(
          rig.session.openScanner().scan(askFor([battery])),
        );
        final firstResults = <ScanResult>[];
        final secondResults = <ScanResult>[];
        first.results.listen(firstResults.add);
        second.results.listen(secondResults.add);
        final heartRate = advertising([heart]);
        final batteryLevel = advertising([
          battery,
        ], address: 'AA:BB:CC:DD:EE:02');

        // act
        rig.scanning.hear(heartRate);
        rig.scanning.hear(batteryLevel);
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.coverages.map((coverage) => coverage.filter), [
          askFor([heart]).filter,
          askFor([heart, battery]).filter,
        ]);
        expect(firstResults, [heartRate]);
        expect(secondResults, [batteryLevel]);
      });
    });

    test('stopping one leaves the radio running for the other', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final firstScanner = rig.session.openScanner();
        opened(firstScanner.scan(askFor([heart])));
        final second = opened(
          rig.session.openScanner().scan(askFor([battery])),
        );
        final secondResults = <ScanResult>[];
        second.results.listen(secondResults.add);
        final batteryLevel = advertising([battery]);

        // act
        firstScanner.stop();
        async.flushMicrotasks();
        rig.scanning.hear(batteryLevel);
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.stopsAsked, 0);
        expect(secondResults, [batteryLevel]);
      });
    });
  });

  group('a refusal', () {
    test('ends every open scan with the failure and closes their results '
        'without an error', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final first = opened(rig.session.openScanner().scan(askFor([heart])));
        final second = opened(
          rig.session.openScanner().scan(askFor([battery])),
        );
        final errors = <Object>[];
        var closed = 0;
        for (final scan in [first, second]) {
          scan.results.listen(
            (_) {},
            onError: errors.add,
            onDone: () => closed++,
          );
        }
        final ends = <ScanEnd>[];
        first.ended.then(ends.add);
        second.ended.then(ends.add);

        // act
        rig.scanning.refuse(ScanRefusalReason.startedTooOften);
        async.flushMicrotasks();

        // assert
        const failed = EndedByFailure(
          ScanRefused(ScanRefusalReason.startedTooOften),
        );
        expect(ends, [failed, failed]);
        expect(closed, 2);
        expect(errors, isEmpty);
      });
    });

    test('a scan asked afterwards asks the radio again', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        opened(scanner.scan(askFor()));
        rig.scanning.refuse(ScanRefusalReason.internalError);
        async.flushMicrotasks();

        // act
        opened(scanner.scan(askFor()));

        // assert
        expect(rig.scanning.scansAsked, 2);
      });
    });
  });

  group('dispose', () {
    test('while scanning stops the radio once and ends every scan on '
        'request', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final first = opened(rig.session.openScanner().scan(askFor([heart])));
        final second = opened(
          rig.session.openScanner().scan(askFor([battery])),
        );
        final ends = <ScanEnd>[];
        first.ended.then(ends.add);
        second.ended.then(ends.add);
        var disposed = false;

        // act
        rig.session.dispose().then((_) => disposed = true);
        async.flushMicrotasks();

        // assert
        expect(disposed, isTrue);
        expect(rig.scanning.stopsAsked, 1);
        expect(ends, [const EndedOnRequest(), const EndedOnRequest()]);
      });
    });

    test('when quiet asks the radio nothing', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        rig.session.openScanner();

        // act
        rig.session.dispose();
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.scansAsked, 0);
        expect(rig.scanning.stopsAsked, 0);
      });
    });

    test('after a failed stop asks the radio to stop again', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        opened(scanner.scan(askFor()));
        rig.scanning.failNextStop();
        scanner.stop();
        async.flushMicrotasks();

        // act
        rig.session.dispose();
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.stopsAsked, 2);
      });
    });

    test('waits for the stop it caused', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        opened(rig.session.openScanner().scan(askFor()));
        rig.scanning.holdNextStop();
        var disposed = false;
        rig.session.dispose().then((_) => disposed = true);
        async.flushMicrotasks();
        final disposedWhileHeld = disposed;

        // act
        rig.scanning.releaseStop();
        async.flushMicrotasks();

        // assert
        expect(disposedWhileHeld, isFalse);
        expect(disposed, isTrue);
      });
    });

    test('closes every scanner, so none can scan again', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();

        // act
        rig.session.dispose();
        async.flushMicrotasks();

        // assert
        expect(scanner.scan(askFor()), isA<Left<Object, OpenScan>>());
        expect(rig.scanning.scansAsked, 0);
      });
    });
  });
}
