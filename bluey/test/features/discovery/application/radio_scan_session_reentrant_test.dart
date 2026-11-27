import 'package:bluey/src/features/discovery/application/open_scan.dart';
import 'package:bluey/src/features/discovery/application/open_scanner.dart';
import 'package:bluey/src/features/discovery/domain/scan_event.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scanner_phase.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/discovery/application/ports/in_memory_scanning.dart';
import '../../../fixtures/features/discovery/application/radio_scan_rig.dart';

/// Each call here is made from inside a step, the way a listener that is
/// told synchronously would make it.
void main() {
  group('called from inside a step', () {
    test('stop waits for the radio stop its leaving caused', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final first = rig.session.openScanner();
        final second = rig.session.openScanner();
        opened(first.scan(askFor()));
        final leaving = opened(second.scan(askFor()));
        rig.scanning.holdNextStop();
        Future<Either<ScanFailure, void>>? stop;
        rig.events.whenRaised = (event) {
          if (event is ScannerStopped) stop ??= first.stop();
        };
        leaving.leave();
        Either<ScanFailure, void>? answer;
        stop?.then((value) => answer = value);
        async.flushMicrotasks();
        final answerWhileHeld = answer;

        // act
        rig.scanning.releaseStop();
        async.flushMicrotasks();

        // assert
        expect(stop, isNotNull);
        expect(answerWhileHeld, isNull);
        expect(answer, const Right<ScanFailure, void>(null));
        expect(rig.scanning.stopsAsked, 1);
      });
    });

    test('close tells the scanner closed before its phases end', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        final phases = <ScannerPhase>[];
        var done = false;
        scanner.phases.listen(phases.add, onDone: () => done = true);
        rig.events.whenRaised = (event) {
          if (event is ScannerStarted) scanner.close();
        };

        // act
        opened(scanner.scan(askFor()));
        async.flushMicrotasks();

        // assert
        expect(phases.last, const ScannerClosed());
        expect(done, isTrue);
        expect(rig.scanning.stopsAsked, 1);
      });
    });

    test('a scan after close is refused as closed', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        Either<ScannerUnusable, OpenScan>? answer;
        rig.events.whenRaised = (event) {
          if (event is ScannerStarted && answer == null) {
            scanner.close();
            answer = scanner.scan(askFor());
          }
        };

        // act
        opened(scanner.scan(askFor()));
        async.flushMicrotasks();

        // assert
        expect(
          answer,
          const Left<ScannerUnusable, OpenScan>(
            ScannerUnusable(ScannerClosed()),
          ),
        );
      });
    });

    test('a scan asked behind an outage ends with the outage, and the '
        'session goes on', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig(
          scanning: InMemoryScanning(outagesAtOnce: true),
        );
        final scanner = rig.session.openScanner();
        Either<ScannerUnusable, OpenScan>? answer;
        rig.events.whenRaised = (event) {
          if (event is ScannerStarted && answer == null) {
            rig.scanning.outage(RadioOutage.off);
            answer = scanner.scan(askFor());
          }
        };
        opened(scanner.scan(askFor()));
        ScanEnd? end;
        answer?.fold((_) {}, (scan) => scan.ended.then((value) => end = value));
        async.flushMicrotasks();

        // act
        rig.events.whenRaised = null;
        final next = rig.session.openScanner().scan(askFor());

        // assert
        expect(end, const EndedByRadioOutage(RadioOutage.off));
        expect(scanner.phase, const ScannerLost(RadioOutage.off));
        expect(next, isA<Right<ScannerUnusable, OpenScan>>());
        expect(rig.scanning.scansAsked, 2);
      });
    });
  });

  group('dispose', () {
    test('a second call answers with the first', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        opened(rig.session.openScanner().scan(askFor()));
        rig.scanning.holdNextStop();
        final first = rig.session.dispose();
        var secondDone = false;

        // act
        final second = rig.session.dispose()..then((_) => secondDone = true);
        async.flushMicrotasks();
        final doneWhileHeld = secondDone;
        rig.scanning.releaseStop();
        async.flushMicrotasks();

        // assert
        expect(identical(first, second), isTrue);
        expect(doneWhileHeld, isFalse);
        expect(secondDone, isTrue);
      });
    });
  });
}
