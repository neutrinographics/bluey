import 'package:bluey/src/features/discovery/application/open_scan.dart';
import 'package:bluey/src/features/discovery/application/open_scanner.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/discovery/application/radio_scan_rig.dart';

OpenScan opened(Either<ScannerUnusable, OpenScan> answer) => answer.fold(
  (unusable) => fail('the scanner was unusable: ${unusable.phase}'),
  (scan) => scan,
);

void main() {
  group('a time limit', () {
    test('ends the scan by timeout at exactly its limit while another scan '
        'keeps the radio going', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final limited = opened(
          rig.session.openScanner().scan(
            askFor(const [], const Duration(seconds: 5)),
          ),
        );
        final unlimited = opened(rig.session.openScanner().scan(askFor()));
        ScanEnd? end;
        limited.ended.then((value) => end = value);
        final results = <ScanResult>[];
        unlimited.results.listen(results.add);
        async.elapse(const Duration(milliseconds: 4999));
        final endBeforeLimit = end;

        // act
        async.elapse(const Duration(milliseconds: 1));
        final result = advertising([heart]);
        rig.scanning.hear(result);
        async.flushMicrotasks();

        // assert
        expect(endBeforeLimit, isNull);
        expect(end, const EndedByTimeout());
        expect(results, [result]);
        expect(rig.scanning.stopsAsked, 0);
      });
    });

    test('is cancelled when the scan ends first', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scan = opened(
          rig.session.openScanner().scan(
            askFor(const [], const Duration(seconds: 5)),
          ),
        );

        // act
        scan.leave();
        async.flushMicrotasks();

        // assert
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('that runs out while the radio is stopping for the same scan '
        'changes nothing and leaves no timer', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scan = opened(
          rig.session.openScanner().scan(
            askFor(const [], const Duration(seconds: 5)),
          ),
        );
        ScanEnd? end;
        scan.ended.then((value) => end = value);
        rig.scanning.holdNextStop();
        scan.leave();
        async.flushMicrotasks();

        // act
        async.elapse(const Duration(seconds: 5));
        rig.scanning.releaseStop();
        async.flushMicrotasks();

        // assert
        expect(end, const EndedOnRequest());
        expect(rig.scanning.stopsAsked, 1);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('results', () {
    test('close when the scan ends', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scan = opened(rig.session.openScanner().scan(askFor()));
        var done = false;
        scan.results.listen((_) {}, onDone: () => done = true);

        // act
        scan.leave();
        async.flushMicrotasks();

        // assert
        expect(done, isTrue);
      });
    });

    test('cancelled while the scan waits for a stop ends it, and the stop '
        'settles with the radio quiet', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scanner = rig.session.openScanner();
        opened(scanner.scan(askFor()));
        rig.scanning.holdNextStop();
        scanner.stop();
        final waiting = opened(scanner.scan(askFor()));
        ScanEnd? end;
        waiting.ended.then((value) => end = value);
        final subscription = waiting.results.listen((_) {});

        // act
        subscription.cancel();
        async.flushMicrotasks();
        rig.scanning.releaseStop();
        async.flushMicrotasks();

        // assert
        expect(end, const EndedOnRequest());
        expect(rig.scanning.scansAsked, 1);
        expect(rig.scanning.scanningFor, isNull);
      });
    });
  });

  group('leave', () {
    test('a second time asks nothing more of the radio', () {
      fakeAsync((async) {
        // arrange
        final rig = RadioScanRig();
        final scan = opened(rig.session.openScanner().scan(askFor()));
        scan.leave();
        async.flushMicrotasks();

        // act
        scan.leave();
        async.flushMicrotasks();

        // assert
        expect(rig.scanning.stopsAsked, 1);
      });
    });
  });
}
