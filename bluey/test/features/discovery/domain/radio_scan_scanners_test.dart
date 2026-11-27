import 'package:bluey/src/features/discovery/domain/radio_scan.dart';
import 'package:bluey/src/features/discovery/domain/radio_scan_input.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_event.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_id.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scanner_phase.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

const a = ScannerId(1);
const b = ScannerId(2);
const c = ScannerId(3);
const s1 = ScanId(1);
const s2 = ScanId(2);
const s3 = ScanId(3);
final at = DateTime.utc(2026, 11, 27, 9);
final later = DateTime.utc(2026, 11, 27, 10);
final heart = UUID.short(0x180D);
final battery = UUID.short(0x180F);
const refusal = ScanRefused(ScanRefusalReason.internalError);
const outage = RadioOutage.off;
const onRequest = EndedOnRequest();
const timedOut = EndedByTimeout();

ScanAsk ask([List<UUID> services = const []]) =>
    ScanAsk(filter: ScanFilter.of(services));

RadioScan after(List<RadioScanInput> inputs) => inputs.fold(
  const RadioScan.quiet(),
  (scan, input) => scan.on(input, at: at).scan,
);

/// Scanner [a] open and [s1] served for [heart].
List<RadioScanInput> scanning() => [
  const ScannerOpened(a),
  ScanAsked(a, s1, ask([heart])),
];

/// [s1] the last to leave, by its time limit, so the radio is stopping.
List<RadioScanInput> stopping() => [...scanning(), ScanLeft(s1, timedOut)];

void main() {
  group('ScannerOpened', () {
    test('adds an idle scanner and raises nothing', () {
      // arrange
      const scan = RadioScan.quiet();

      // act
      final step = scan.on(const ScannerOpened(a), at: at);

      // assert
      expect(step.scan.standingOf(a), const ScannerIdle());
      expect(step.events, isEmpty);
    });

    test('of a scanner already open is a programming error', () {
      // arrange
      final scan = after([const ScannerOpened(a)]);

      // act
      void reopen() => scan.on(const ScannerOpened(a), at: at);

      // assert
      expect(reopen, throwsStateError);
    });

    test('after an outage opens a scanner that is not lost', () {
      // arrange
      final scan = after([...stopping(), const RadioWentAway(outage)]);

      // act
      final step = scan.on(const ScannerOpened(b), at: at);

      // assert
      expect(step.scan.standingOf(b), const ScannerIdle());
      expect(step.scan.standingOf(a), const ScannerLost(outage));
    });

    test('after an outage, its ask while the stop is in flight is served '
        'once the stop settles', () {
      // arrange
      final scan = after([
        ...stopping(),
        const RadioWentAway(outage),
        const ScannerOpened(b),
      ]);

      // act
      final asked = scan.on(ScanAsked(b, s2, ask()), at: at);
      final settled = asked.scan.on(const RadioStopped(), at: later);

      // assert
      expect(asked.events, [ScannerBeganStarting(b, ask(), at)]);
      expect(asked.duty, isNull);
      expect(settled.events, [ScannerStarted(b, ask(), later)]);
      expect(settled.duty, ScanFor(ScanCoverage.of([ask()])));
      expect(settled.scan.standingOf(b), const ScannerScanning());
    });
  });

  group('ScanAsked is a programming error', () {
    for (final (name, before, scanner) in [
      ('from a scanner never opened', <RadioScanInput>[], a),
      (
        'from a lost scanner',
        [const ScannerOpened(a), const RadioWentAway(outage)],
        a,
      ),
      (
        'from a closed scanner',
        [const ScannerOpened(a), const ScannerDisposed(a)],
        a,
      ),
      ('for a scan already held', scanning(), a),
      (
        'for a scan another scanner holds',
        [...scanning(), const ScannerOpened(b)],
        b,
      ),
    ]) {
      test(name, () {
        // arrange
        final scan = after(before);

        // act
        void askAgain() => scan.on(ScanAsked(scanner, s1, ask()), at: at);

        // assert
        expect(askAgain, throwsStateError);
      });
    }
  });

  group('a scanner starting', () {
    test('on a quiet radio began starting and started in one step', () {
      // arrange
      final scan = after([const ScannerOpened(a)]);

      // act
      final step = scan.on(ScanAsked(a, s1, ask([heart])), at: at);

      // assert
      expect(step.events, [
        ScannerBeganStarting(a, ask([heart]), at),
        ScannerStarted(a, ask([heart]), at),
      ]);
    });

    test('while the radio stops began starting, and starts when it stops', () {
      // arrange
      final scan = after([...stopping(), const ScannerOpened(b)]);

      // act
      final asked = scan.on(ScanAsked(b, s2, ask([battery])), at: at);
      final settled = asked.scan.on(const RadioStopped(), at: later);

      // assert
      expect(asked.events, [
        ScannerBeganStarting(b, ask([battery]), at),
      ]);
      expect(settled.events, [
        ScanEnded(s1, timedOut, later),
        ScannerStopped(a, timedOut, later),
        ScannerStarted(b, ask([battery]), later),
      ]);
    });

    test('names the ask of its latest scan not ended', () {
      // arrange
      final scan = after([
        ...stopping(),
        ScanAsked(a, s2, ask([battery])),
      ]);

      // act
      final asked = scan.on(ScanAsked(a, s3, ask()), at: at);
      final settled = asked.scan.on(const RadioStopped(), at: later);

      // assert
      expect(asked.events, isEmpty);
      expect(settled.events, [
        ScanEnded(s1, timedOut, later),
        ScannerStarted(a, ask(), later),
      ]);
    });
  });

  group('a scanner stopping', () {
    test('its last scan leaving began stopping; the stop ends the scan', () {
      // arrange
      final scan = after(scanning());

      // act
      final left = scan.on(ScanLeft(s1, onRequest), at: at);
      final settled = left.scan.on(const RadioStopped(), at: later);

      // assert
      expect(left.events, [ScannerBeganStopping(a, at)]);
      expect(settled.events, [
        ScanEnded(s1, onRequest, later),
        ScannerStopped(a, onRequest, later),
      ]);
      expect(settled.scan.standingOf(a), const ScannerIdle());
    });

    test('one of its two scans leaving ends that scan alone', () {
      // arrange
      final scan = after([
        ...scanning(),
        ScanAsked(a, s2, ask([battery])),
      ]);

      // act
      final step = scan.on(ScanLeft(s2, onRequest), at: at);

      // assert
      expect(step.events, [ScanEnded(s2, onRequest, at)]);
      expect(step.scan.standingOf(a), const ScannerScanning());
    });

    test(
      'its only scan leaving while another scanner stays stops it at once',
      () {
        // arrange
        final scan = after([
          ...scanning(),
          const ScannerOpened(b),
          ScanAsked(b, s2, ask([heart])),
        ]);

        // act
        final step = scan.on(ScanLeft(s2, timedOut), at: at);

        // assert
        expect(step.events, [
          ScanEnded(s2, timedOut, at),
          ScannerStopped(b, timedOut, at),
        ]);
        expect(step.duty, isNull);
      },
    );

    test(
      'a refusal ends each open scan and stops each scanner that had one',
      () {
        // arrange
        final scan = after([
          ...scanning(),
          ScanAsked(a, s2, ask([battery])),
          const ScannerOpened(b),
          ScanAsked(b, s3, ask([heart])),
          const ScannerOpened(c),
        ]);

        // act
        final step = scan.on(const RadioRefused(refusal), at: at);

        // assert
        const failed = EndedByFailure(refusal);
        expect(step.events, [
          ScanEnded(s1, failed, at),
          ScanEnded(s2, failed, at),
          ScannerStopped(a, failed, at),
          ScanEnded(s3, failed, at),
          ScannerStopped(b, failed, at),
        ]);
        expect(step.scan.standingOf(c), const ScannerIdle());
      },
    );

    test('Bluey shutting down ends every scan and stops every scanner', () {
      // arrange
      final scan = after([
        ...scanning(),
        const ScannerOpened(b),
        ScanAsked(b, s2, ask([heart])),
      ]);

      // act
      final step = scan.on(const ShutDown(), at: at);

      // assert
      expect(step.events, [
        ScanEnded(s1, onRequest, at),
        ScannerStopped(a, onRequest, at),
        ScanEnded(s2, onRequest, at),
        ScannerStopped(b, onRequest, at),
      ]);
    });
  });

  group('the radio going away', () {
    const lost = EndedByRadioOutage(outage);

    test('while scanning loses every scanner and stops those with scans', () {
      // arrange
      final scan = after([...scanning(), const ScannerOpened(b)]);

      // act
      final step = scan.on(const RadioWentAway(outage), at: at);

      // assert
      expect(step.events, [
        ScanEnded(s1, lost, at),
        ScannerStopped(a, lost, at),
      ]);
      expect(step.scan.standingOf(a), const ScannerLost(outage));
      expect(step.scan.standingOf(b), const ScannerLost(outage));
    });

    test('while stopping ends leaving and waiting scans alike', () {
      // arrange
      final scan = after([
        ...stopping(),
        const ScannerOpened(b),
        ScanAsked(b, s2, ask()),
      ]);

      // act
      final step = scan.on(const RadioWentAway(outage), at: at);

      // assert
      expect(step.events, [
        ScanEnded(s1, lost, at),
        ScannerStopped(a, lost, at),
        ScanEnded(s2, lost, at),
        ScannerStopped(b, lost, at),
      ]);
      expect(step.scan.standingOf(b), const ScannerLost(outage));
    });

    test('while quiet loses an idle scanner and raises nothing', () {
      // arrange
      final scan = after([const ScannerOpened(a)]);

      // act
      final step = scan.on(const RadioWentAway(outage), at: at);

      // assert
      expect(step.events, isEmpty);
      expect(step.scan.standingOf(a), const ScannerLost(outage));
    });
  });

  group('ScannerDisposed', () {
    test('its last scan leaves as ScanLeft would and it is closed', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(const ScannerDisposed(a), at: at);

      // assert
      expect(step.events, [ScannerBeganStopping(a, at)]);
      expect(step.duty, const StopTheRadio());
      expect(step.scan.standingOf(a), const ScannerClosed());
    });

    test('a later stop still ends its leaving scan', () {
      // arrange
      final scan = after([...scanning(), const ScannerDisposed(a)]);

      // act
      final step = scan.on(const RadioStopped(), at: later);

      // assert
      expect(step.events, [
        ScanEnded(s1, onRequest, later),
        ScannerStopped(a, onRequest, later),
      ]);
      expect(step.scan.standingOf(a), const ScannerClosed());
    });

    test('raises what each of its scans leaving raises', () {
      // arrange
      final scan = after([
        ...scanning(),
        ScanAsked(a, s2, ask([battery])),
        const ScannerOpened(b),
        ScanAsked(b, s3, ask()),
      ]);

      // act
      final step = scan.on(const ScannerDisposed(a), at: at);

      // assert
      expect(step.events, [
        ScanEnded(s1, onRequest, at),
        ScanEnded(s2, onRequest, at),
        ScannerStopped(a, onRequest, at),
      ]);
      expect(step.duty, isNull);
    });

    test('of a lost scanner closes it and raises nothing', () {
      // arrange
      final scan = after([...scanning(), const RadioWentAway(outage)]);

      // act
      final step = scan.on(const ScannerDisposed(a), at: at);

      // assert
      expect(step.events, isEmpty);
      expect(step.scan.standingOf(a), const ScannerClosed());
    });
  });

  group('the order of events', () {
    test('within one scanner: began starting, started, began stopping, '
        'stopped', () {
      // arrange
      var scan = after([const ScannerOpened(a)]);
      final events = <ScanEvent>[];

      // act
      for (final input in [
        ScanAsked(a, s1, ask()),
        ScanLeft(s1, onRequest),
        const RadioStopped(),
      ]) {
        final step = scan.on(input, at: at);
        events.addAll(step.events);
        scan = step.scan;
      }

      // assert
      expect(events, [
        ScannerBeganStarting(a, ask(), at),
        ScannerStarted(a, ask(), at),
        ScannerBeganStopping(a, at),
        ScanEnded(s1, onRequest, at),
        ScannerStopped(a, onRequest, at),
      ]);
    });

    test('across scanners: in the order they were opened', () {
      // arrange
      final scan = after([
        const ScannerOpened(b),
        const ScannerOpened(a),
        ScanAsked(a, s1, ask()),
        ScanAsked(b, s2, ask()),
      ]);

      // act
      final step = scan.on(const RadioRefused(refusal), at: at);

      // assert
      const failed = EndedByFailure(refusal);
      expect(step.events, [
        ScanEnded(s2, failed, at),
        ScannerStopped(b, failed, at),
        ScanEnded(s1, failed, at),
        ScannerStopped(a, failed, at),
      ]);
    });
  });

  group('what the radio scan remembers', () {
    test('an ended scan shows in the step that ended it and is then '
        'forgotten', () {
      // arrange
      final ended = after([
        ...scanning(),
        ScanLeft(s1, onRequest),
      ]).on(const RadioStopped(), at: at);

      // act
      final next = ended.scan.on(const ScannerOpened(b), at: at);

      // assert
      expect(ended.scan.phaseOf(s1), const Ended(onRequest));
      expect(next.scan.phaseOf(s1), isNull);
    });

    test('a closed scanner keeps its standing and no scans', () {
      // arrange
      final scan = after([
        ...scanning(),
        const ScannerDisposed(a),
        const RadioStopped(),
      ]);

      // act
      final next = scan.on(const ScannerOpened(b), at: at);

      // assert
      expect(next.scan.standingOf(a), const ScannerClosed());
      expect(next.scan.phaseOf(s1), isNull);
      expect(next.scan.heldScanCount, 0);
    });

    test('a thousand scans asked and left leave few scans held', () {
      // arrange
      var scan = after([
        const ScannerOpened(a),
        ScanAsked(a, s1, ask()),
        const ScannerOpened(b),
      ]);

      // act
      for (var id = 2; id < 1002; id++) {
        for (final input in [
          ScanAsked(b, ScanId(id), ask()),
          ScanLeft(ScanId(id), onRequest),
        ]) {
          scan = scan.on(input, at: at).scan;
        }
      }

      // assert
      expect(scan.heldScanCount, lessThanOrEqualTo(2));
      expect(scan.phaseOf(const ScanId(500)), isNull);
      expect(scan.phaseOf(s1), const Served());
    });
  });

  group('ScanEvent', () {
    test('is equal by value', () {
      // arrange
      final events = [
        ScannerBeganStarting(a, ask(), at),
        ScannerStarted(a, ask(), at),
        ScannerBeganStopping(a, at),
        ScannerStopped(a, onRequest, at),
        ScanEnded(s1, onRequest, at),
      ];

      // act
      final same = [
        ScannerBeganStarting(a, ask(), at),
        ScannerStarted(a, ask(), at),
        ScannerBeganStopping(a, at),
        ScannerStopped(a, onRequest, at),
        ScanEnded(s1, onRequest, at),
      ];

      // assert
      for (var i = 0; i < events.length; i++) {
        expect(events[i], same[i]);
        expect(events[i].hashCode, same[i].hashCode);
        expect(events[i].at, at);
      }
      expect(ScannerBeganStopping(a, at), isNot(ScannerBeganStopping(b, at)));
      expect(ScanEnded(s1, onRequest, at), isNot(ScanEnded(s1, timedOut, at)));
    });
  });
}
