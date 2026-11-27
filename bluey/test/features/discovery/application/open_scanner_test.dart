import 'package:bluey/src/features/discovery/application/open_scan.dart';
import 'package:bluey/src/features/discovery/application/open_scanner.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/features/discovery/domain/scanner_phase.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/discovery/application/radio_scan_rig.dart';

void main() {
  group('phases', () {
    test('a new scanner is idle', () {
      // arrange
      final rig = RadioScanRig();

      // act
      final scanner = rig.session.openScanner();

      // assert
      expect(scanner.phase, const ScannerIdle());
    });

    test('tell each change once, and close with the scanner', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        final phases = <ScannerPhase>[];
        var done = false;
        scanner.phases.listen(phases.add, onDone: () => done = true);
        final scan = opened(scanner.scan(askFor()));
        scan.leave();
        async.flushMicrotasks();

        // act
        scanner.close();
        async.flushMicrotasks();

        // assert
        expect(phases, const [
          ScannerScanning(),
          ScannerStopping(),
          ScannerIdle(),
          ScannerClosed(),
        ]);
        expect(done, isTrue);
      });
    });
  });

  group('a stop not awaited, then a scan', () {
    test('the scan waits for the stop and is served once it settles', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        opened(scanner.scan(askFor()));
        rig.scanning.holdNextStop();
        scanner.stop();
        final second = opened(scanner.scan(askFor()));
        final phaseWhileHeld = scanner.phase;
        final results = <ScanResult>[];
        second.results.listen(results.add);

        // act
        rig.scanning.releaseStop();
        async.flushMicrotasks();
        final result = advertising([heart]);
        rig.scanning.hear(result);
        async.flushMicrotasks();

        // assert
        expect(phaseWhileHeld, const ScannerStarting());
        expect(scanner.phase, const ScannerScanning());
        expect(rig.scanning.scansAsked, 2);
        expect(results, [result]);
      });
    });
  });

  group('a stop and a scan in the same turn, a thousand times', () {
    test('leaves one scan served, each stop asked once and each restart '
        'scanned once', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        var scan = opened(scanner.scan(askFor()));
        var ended = 0;
        scan.ended.then((_) => ended++);

        // act
        for (var round = 0; round < 1000; round++) {
          scanner.stop();
          scan = opened(scanner.scan(askFor()));
          scan.ended.then((_) => ended++);
          async.flushMicrotasks();
        }
        final results = <ScanResult>[];
        scan.results.listen(results.add);
        final result = advertising([heart]);
        rig.scanning.hear(result);
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.stopsAsked, 1000);
        expect(rig.scanning.scansAsked, 1001);
        expect(ended, 1000);
        expect(scanner.phase, const ScannerScanning());
        expect(results, [result]);
      });
    });
  });

  group('stop', () {
    test('answers once the radio stop it caused settled', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        opened(scanner.scan(askFor()));
        rig.scanning.holdNextStop();
        Either<ScanFailure, void>? answer;
        scanner.stop().then((value) => answer = value);
        async.flushMicrotasks();
        final answerWhileHeld = answer;

        // act
        rig.scanning.releaseStop();
        async.flushMicrotasks();

        // assert
        expect(answerWhileHeld, isNull);
        expect(answer, const Right<ScanFailure, void>(null));
      });
    });

    test('that fails answers the failure, still ends the scan on request, '
        'logs a warning, and the next ask scans again', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        final scan = opened(scanner.scan(askFor()));
        ScanEnd? end;
        scan.ended.then((value) => end = value);
        rig.scanning.failNextStop();
        Either<ScanFailure, void>? answer;

        // act
        scanner.stop().then((value) => answer = value);
        async.flushMicrotasks();
        opened(scanner.scan(askFor()));

        // assert
        expect(answer, isA<Left<ScanFailure, void>>());
        expect(end, const EndedOnRequest());
        expect(
          rig.log.records.where(
            (line) =>
                line.level == BlueyLogLevel.warn && line.context == 'bluey',
          ),
          hasLength(1),
        );
        expect(rig.scanning.scansAsked, 2);
      });
    });
  });

  group('close', () {
    test('of the only scanner while scanning asks the radio to stop once', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        opened(scanner.scan(askFor([heart])));
        opened(scanner.scan(askFor([battery])));

        // act
        scanner.close();
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.stopsAsked, 1);
        expect(scanner.phase, const ScannerClosed());
      });
    });

    test('leaves the scanner unusable', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();

        // act
        scanner.close();
        async.flushMicrotasks();

        // assert
        expect(
          scanner.scan(askFor()),
          const Left<ScannerUnusable, OpenScan>(
            ScannerUnusable(ScannerClosed()),
          ),
        );
      });
    });
  });

  group('an outage', () {
    test('loses every scanner, idle ones included, without stopping the '
        'radio', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanning = rig.session.openScanner();
        final idle = rig.session.openScanner();
        opened(scanning.scan(askFor()));

        // act
        rig.scanning.outage(RadioOutage.off);
        async.flushMicrotasks();

        // assert
        const lost = ScannerLost(RadioOutage.off);
        expect(scanning.phase, lost);
        expect(idle.phase, lost);
        expect(
          idle.scan(askFor()),
          const Left<ScannerUnusable, OpenScan>(ScannerUnusable(lost)),
        );
        expect(rig.scanning.stopsAsked, 0);
      });
    });
  });

  group('ScannerUnusable', () {
    test('says which phase made the scanner unusable', () {
      // arrange
      const unusable = ScannerUnusable(ScannerLost(RadioOutage.unauthorized));

      // act
      final message = unusable.message;

      // assert
      expect(message, contains('lost'));
    });

    test('is equal by value', () {
      // arrange
      const lost = ScannerLost(RadioOutage.off);

      // act
      const first = ScannerUnusable(lost);
      const second = ScannerUnusable(lost);

      // assert
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(const ScannerUnusable(ScannerClosed())));
    });
  });
}
