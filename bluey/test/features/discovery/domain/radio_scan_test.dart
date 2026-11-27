import 'package:bluey/src/features/discovery/domain/advertisement.dart';
import 'package:bluey/src/features/discovery/domain/device.dart';
import 'package:bluey/src/features/discovery/domain/radio_phase.dart';
import 'package:bluey/src/features/discovery/domain/radio_scan.dart';
import 'package:bluey/src/features/discovery/domain/radio_scan_input.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_id.dart';
import 'package:bluey/src/features/discovery/domain/scan_mode.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/features/discovery/domain/scanner_phase.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

const a = ScannerId(1);
const b = ScannerId(2);
const s1 = ScanId(1);
const s2 = ScanId(2);
const s3 = ScanId(3);
final at = DateTime.utc(2026, 11, 27, 9);
final heart = UUID.short(0x180D);
final battery = UUID.short(0x180F);
const refusal = ScanRefused(ScanRefusalReason.internalError);
const outage = RadioOutage.off;
const onRequest = EndedOnRequest();
const timedOut = EndedByTimeout();

ScanAsk ask([List<UUID> services = const [], ScanMode? mode]) =>
    ScanAsk(filter: ScanFilter.of(services), mode: mode);

ScanCoverage coverage([List<UUID> services = const [], ScanMode? mode]) =>
    ScanCoverage(filter: ScanFilter.of(services), mode: mode);

RadioScan after(List<RadioScanInput> inputs) => inputs.fold(
  const RadioScan.quiet(),
  (scan, input) => scan.on(input, at: at).scan,
);

/// Scanner [a] open, the radio quiet, and [s1] long since ended.
List<RadioScanInput> quiet() => [
  const ScannerOpened(a),
  ScanAsked(a, s1, ask([heart])),
  ScanLeft(s1, timedOut),
  const RadioStopped(),
];

/// Scanner [a] open and [s1] served for [heart].
List<RadioScanInput> scanning() => [
  const ScannerOpened(a),
  ScanAsked(a, s1, ask([heart])),
];

/// [s1] the last to leave, by its time limit, so the radio is stopping.
List<RadioScanInput> stopping() => [...scanning(), ScanLeft(s1, timedOut)];

/// [s1] ended and the stop failed, so the radio may still be scanning.
List<RadioScanInput> unsure() => [
  ...stopping(),
  const RadioStopFailed(refusal),
];

void expectStep(
  RadioScanStep step, {
  required RadioPhase radio,
  Map<ScanId, ScanPhase?> phases = const {},
  RadioDuty? duty,
}) {
  expect(step.scan.radio, radio);
  for (final MapEntry(key: id, value: phase) in phases.entries) {
    expect(step.scan.phaseOf(id), phase, reason: 'scan ${id.value}');
  }
  expect(step.duty, duty);
}

/// What the next step still shows of [id] in [scan]: a scan already ended is
/// forgotten by then.
ScanPhase? carried(RadioScan scan, ScanId id) {
  final phase = scan.phaseOf(id);
  return phase is Ended ? null : phase;
}

ScanResult heard() => ScanResult(
  device: Device(address: const DeviceAddress('AA:BB:CC:DD:EE:01')),
  rssi: -60,
  advertisement: Advertisement.empty(),
  lastSeen: at,
);

void main() {
  group('a quiet radio scan', () {
    test('has no scanner, no scan and a quiet radio', () {
      // arrange
      const scan = RadioScan.quiet();

      // act
      final radio = scan.radio;

      // assert
      expect(radio, const RadioQuiet());
      expect(scan.phaseOf(s1), isNull);
      expect(scan.standingOf(a), isNull);
    });

    test('is left as it was by a step', () {
      // arrange
      final scan = after(scanning());

      // act
      scan.on(ScanLeft(s1, onRequest), at: at);

      // assert
      expect(scan.radio, RadioScanning(coverage([heart])));
      expect(scan.phaseOf(s1), const Served());
    });
  });

  group('RadioDuty', () {
    test('is equal by value', () {
      // arrange
      final scanFor = ScanFor(coverage([heart]));

      // act
      final same = ScanFor(coverage([heart]));

      // assert
      expect(scanFor, same);
      expect(scanFor.hashCode, same.hashCode);
      expect(scanFor, isNot(ScanFor(coverage())));
      expect(const StopTheRadio(), const StopTheRadio());
      expect(const StopTheRadio().hashCode, const StopTheRadio().hashCode);
    });
  });

  group('RadioPhase', () {
    test('is equal by value', () {
      // arrange
      final one = RadioScanning(coverage([heart]));

      // act
      final same = RadioScanning(coverage([heart]));

      // assert
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(RadioScanning(coverage())));
      expect(const RadioQuiet().hashCode, const RadioQuiet().hashCode);
      expect(const RadioUnsure().hashCode, const RadioUnsure().hashCode);
      expect(const RadioStopping(), isNot(const RadioStopping(outage: outage)));
      expect(
        const RadioStopping(outage: outage).hashCode,
        const RadioStopping(outage: outage).hashCode,
      );
    });
  });

  group('ScannerOpened', () {
    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioScanning', scanning()),
      ('RadioStopping', stopping()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name adds a scanner with no scans and moves nothing', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(const ScannerOpened(b), at: at);

        // assert
        expectStep(step, radio: scan.radio, phases: {s1: carried(scan, s1)});
        expect(step.scan.standingOf(b), const ScannerIdle());
      });
    }

    test('of a scanner already open is a programming error', () {
      // arrange
      final scan = after(scanning());

      // act
      void reopen() => scan.on(const ScannerOpened(a), at: at);

      // assert
      expect(reopen, throwsStateError);
    });
  });

  group('ScannerDisposed', () {
    test('in RadioScanning, its only scan leaves last and stops the radio', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(const ScannerDisposed(a), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(onRequest)},
        duty: const StopTheRadio(),
      );
      expect(step.scan.standingOf(a), const ScannerClosed());
    });

    test('in RadioScanning, its scans end while another scanner\'s stays', () {
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
      expectStep(
        step,
        radio: RadioScanning(coverage()),
        phases: {
          s1: const Ended(onRequest),
          s2: const Ended(onRequest),
          s3: const Served(),
        },
      );
      expect(step.scan.standingOf(a), const ScannerClosed());
    });

    test('in RadioScanning, of its two scans the second leaves last', () {
      // arrange
      final scan = after([
        ...scanning(),
        ScanAsked(a, s2, ask([battery])),
      ]);

      // act
      final step = scan.on(const ScannerDisposed(a), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Ended(onRequest), s2: const Leaving(onRequest)},
        duty: const StopTheRadio(),
      );
    });

    test('in RadioStopping, its waiting scan ends', () {
      // arrange
      final scan = after([
        ...stopping(),
        const ScannerOpened(b),
        ScanAsked(b, s2, ask()),
      ]);

      // act
      final step = scan.on(const ScannerDisposed(b), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(timedOut), s2: const Ended(onRequest)},
      );
    });

    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name, with no scan open, does nothing', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(const ScannerDisposed(a), at: at);

        // assert
        expectStep(step, radio: scan.radio, phases: {s1: carried(scan, s1)});
      });
    }

    test('of a scanner never opened does nothing', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(const ScannerDisposed(b), at: at);

      // assert
      expectStep(step, radio: scan.radio, phases: {s1: const Served()});
      expect(step.scan.standingOf(b), isNull);
    });
  });

  group('ScanAsked', () {
    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name serves the scan and scans for its ask', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(ScanAsked(a, s2, ask([battery])), at: at);

        // assert
        expectStep(
          step,
          radio: RadioScanning(coverage([battery])),
          phases: {s2: const Served()},
          duty: ScanFor(coverage([battery])),
        );
        expect(step.scan.standingOf(a), const ScannerScanning());
      });
    }

    test('in RadioScanning, covered, serves the scan with no restart', () {
      // arrange
      final scan = after([
        const ScannerOpened(a),
        ScanAsked(a, s1, ask(const [], ScanMode.lowLatency)),
      ]);

      // act
      final step = scan.on(
        ScanAsked(a, s2, ask([heart], ScanMode.lowPower)),
        at: at,
      );

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage(const [], ScanMode.lowLatency)),
        phases: {s1: const Served(), s2: const Served()},
      );
    });

    test('in RadioScanning, for a new service, widens the coverage', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(ScanAsked(a, s2, ask([battery])), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([heart, battery])),
        phases: {s1: const Served(), s2: const Served()},
        duty: ScanFor(coverage([heart, battery])),
      );
    });

    test('in RadioScanning, for a busier mode, widens the coverage', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(
        ScanAsked(a, s2, ask([heart], ScanMode.lowLatency)),
        at: at,
      );

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([heart], ScanMode.lowLatency)),
        phases: {s1: const Served(), s2: const Served()},
        duty: ScanFor(coverage([heart], ScanMode.lowLatency)),
      );
    });

    test('in RadioStopping, the scan waits for the stop', () {
      // arrange
      final scan = after(stopping());

      // act
      final step = scan.on(ScanAsked(a, s2, ask()), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(timedOut), s2: const Waiting()},
      );
      expect(step.scan.standingOf(a), const ScannerStarting());
    });
  });

  group('ScanLeft', () {
    test('in RadioScanning, of one of two, ends it and keeps coverage', () {
      // arrange
      final scan = after([
        ...scanning(),
        ScanAsked(a, s2, ask([battery])),
      ]);

      // act
      final step = scan.on(ScanLeft(s2, onRequest), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([heart, battery])),
        phases: {s1: const Served(), s2: const Ended(onRequest)},
      );
    });

    test('in RadioScanning, of the last, leaves and stops the radio', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(ScanLeft(s1, onRequest), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(onRequest)},
        duty: const StopTheRadio(),
      );
    });

    test('in RadioStopping, of a waiting scan, ends it', () {
      // arrange
      final scan = after([...stopping(), ScanAsked(a, s2, ask())]);

      // act
      final step = scan.on(ScanLeft(s2, onRequest), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(timedOut), s2: const Ended(onRequest)},
      );
    });

    test('in RadioStopping, of the leaving scan, does nothing', () {
      // arrange
      final scan = after(stopping());

      // act
      final step = scan.on(ScanLeft(s1, onRequest), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(timedOut)},
      );
    });

    test('in RadioScanning, of an ended scan, does nothing', () {
      // arrange
      final scan = after([
        ...scanning(),
        ScanAsked(a, s2, ask([battery])),
        ScanLeft(s2, timedOut),
      ]);

      // act
      final step = scan.on(ScanLeft(s2, onRequest), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([heart, battery])),
        phases: {s1: const Served(), s2: null},
      );
    });

    test('in RadioScanning, of a scan never asked, does nothing', () {
      // arrange
      final scan = after(scanning());

      // act
      final step = scan.on(ScanLeft(s3, onRequest), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([heart])),
        phases: {s1: const Served(), s3: null},
      );
    });

    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name, where no scan is open, does nothing', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(ScanLeft(s1, onRequest), at: at);

        // assert
        expectStep(step, radio: scan.radio, phases: {s1: null});
      });
    }
  });

  group('RadioStopped', () {
    test('in RadioStopping, with nothing waiting, quiets the radio', () {
      // arrange
      final scan = after(stopping());

      // act
      final step = scan.on(const RadioStopped(), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioQuiet(),
        phases: {s1: const Ended(timedOut)},
      );
      expect(step.scan.standingOf(a), const ScannerIdle());
    });

    test('in RadioStopping, serves the waiting scans together', () {
      // arrange
      final scan = after([
        ...stopping(),
        ScanAsked(a, s2, ask([battery])),
        const ScannerOpened(b),
        ScanAsked(b, s3, ask([heart])),
      ]);

      // act
      final step = scan.on(const RadioStopped(), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([battery, heart])),
        phases: {
          s1: const Ended(timedOut),
          s2: const Served(),
          s3: const Served(),
        },
        duty: ScanFor(coverage([battery, heart])),
      );
    });

    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioScanning', scanning()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name is a programming error', () {
        // arrange
        final scan = after(before);

        // act
        void settle() => scan.on(const RadioStopped(), at: at);

        // assert
        expect(settle, throwsStateError);
      });
    }
  });

  group('RadioStopFailed', () {
    test('in RadioStopping, with nothing waiting, leaves the radio unsure', () {
      // arrange
      final scan = after(stopping());

      // act
      final step = scan.on(const RadioStopFailed(refusal), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioUnsure(),
        phases: {s1: const Ended(timedOut)},
      );
    });

    test('in RadioStopping, serves the waiting scans as a stop would', () {
      // arrange
      final scan = after([
        ...stopping(),
        ScanAsked(a, s2, ask([battery])),
      ]);

      // act
      final step = scan.on(const RadioStopFailed(refusal), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage([battery])),
        phases: {s1: const Ended(timedOut), s2: const Served()},
        duty: ScanFor(coverage([battery])),
      );
    });

    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioScanning', scanning()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name is a programming error', () {
        // arrange
        final scan = after(before);

        // act
        void settle() => scan.on(const RadioStopFailed(refusal), at: at);

        // assert
        expect(settle, throwsStateError);
      });
    }
  });

  group('RadioRefused', () {
    test('in RadioScanning, ends every open scan and quiets the radio', () {
      // arrange
      final scan = after([
        ...scanning(),
        const ScannerOpened(b),
        ScanAsked(b, s2, ask()),
      ]);

      // act
      final step = scan.on(const RadioRefused(refusal), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioQuiet(),
        phases: {
          s1: const Ended(EndedByFailure(refusal)),
          s2: const Ended(EndedByFailure(refusal)),
        },
      );
    });

    for (final (name, before, phases) in [
      ('RadioQuiet', quiet(), {s1: null}),
      ('RadioUnsure', unsure(), {s1: null}),
      (
        'RadioStopping',
        [...stopping(), ScanAsked(a, s2, ask())],
        {s1: const Leaving(timedOut), s2: const Waiting()},
      ),
    ]) {
      test('in $name, arriving late, does nothing', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(const RadioRefused(refusal), at: at);

        // assert
        expectStep(step, radio: scan.radio, phases: phases);
      });
    }
  });

  group('RadioWentAway', () {
    test('in RadioScanning, ends every scan and quiets the radio', () {
      // arrange
      final scan = after([...scanning(), ScanAsked(a, s2, ask())]);

      // act
      final step = scan.on(const RadioWentAway(outage), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioQuiet(),
        phases: {
          s1: const Ended(EndedByRadioOutage(outage)),
          s2: const Ended(EndedByRadioOutage(outage)),
        },
      );
    });

    test('in RadioStopping, ends waiting and leaving scans alike', () {
      // arrange
      final scan = after([...stopping(), ScanAsked(a, s2, ask())]);

      // act
      final step = scan.on(const RadioWentAway(outage), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(outage: outage),
        phases: {
          s1: const Ended(EndedByRadioOutage(outage)),
          s2: const Ended(EndedByRadioOutage(outage)),
        },
      );
    });

    for (final settled in [
      const RadioStopped(),
      const RadioStopFailed(refusal),
    ]) {
      test('in RadioStopping, quiets the radio once '
          '${settled.runtimeType} settles the stop', () {
        // arrange
        final scan = after([...stopping(), const RadioWentAway(outage)]);

        // act
        final step = scan.on(settled, at: at);

        // assert
        expectStep(step, radio: const RadioQuiet(), phases: {s1: null});
      });
    }

    test('in RadioStopping, a scan asked after it starts once stopped', () {
      // arrange
      final scan = after([
        ...stopping(),
        const RadioWentAway(outage),
        const ScannerOpened(b),
        ScanAsked(b, s2, ask()),
      ]);

      // act
      final step = scan.on(const RadioStopped(), at: at);

      // assert
      expectStep(
        step,
        radio: RadioScanning(coverage()),
        phases: {s2: const Served()},
        duty: ScanFor(coverage()),
      );
    });

    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name quiets the radio', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(const RadioWentAway(outage), at: at);

        // assert
        expectStep(step, radio: const RadioQuiet(), phases: {s1: null});
      });
    }
  });

  group('ResultHeard', () {
    for (final (name, before) in [
      ('RadioQuiet', quiet()),
      ('RadioScanning', scanning()),
      ('RadioStopping', stopping()),
      ('RadioUnsure', unsure()),
    ]) {
      test('in $name moves nothing', () {
        // arrange
        final scan = after(before);

        // act
        final step = scan.on(ResultHeard(heard()), at: at);

        // assert
        expectStep(step, radio: scan.radio, phases: {s1: carried(scan, s1)});
      });
    }
  });

  group('ShutDown', () {
    test('in RadioScanning, ends every scan and stops the radio', () {
      // arrange
      final scan = after([...scanning(), ScanAsked(a, s2, ask())]);

      // act
      final step = scan.on(const ShutDown(), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Ended(onRequest), s2: const Ended(onRequest)},
        duty: const StopTheRadio(),
      );
    });

    test('in RadioUnsure, stops the radio', () {
      // arrange
      final scan = after(unsure());

      // act
      final step = scan.on(const ShutDown(), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: null},
        duty: const StopTheRadio(),
      );
    });

    test('in RadioStopping, ends the waiting scans and leaves the leaver', () {
      // arrange
      final scan = after([...stopping(), ScanAsked(a, s2, ask())]);

      // act
      final step = scan.on(const ShutDown(), at: at);

      // assert
      expectStep(
        step,
        radio: const RadioStopping(),
        phases: {s1: const Leaving(timedOut), s2: const Ended(onRequest)},
      );
    });

    test('in RadioQuiet does nothing', () {
      // arrange
      final scan = after(quiet());

      // act
      final step = scan.on(const ShutDown(), at: at);

      // assert
      expectStep(step, radio: const RadioQuiet(), phases: {s1: null});
    });
  });

  group('a stop then a scan in the same turn', () {
    test('a thousand times, asks one stop and one scan per round', () {
      // arrange
      var scan = after(scanning());
      final duties = <RadioDuty>[];
      var id = 1;

      // act
      for (var round = 0; round < 1000; round++) {
        final next = ScanId(++id);
        for (final input in [
          ScanLeft(ScanId(id - 1), onRequest),
          ScanAsked(a, next, ask([heart])),
          const RadioStopped(),
        ]) {
          final step = scan.on(input, at: at);
          final duty = step.duty;
          if (duty != null) duties.add(duty);
          scan = step.scan;
        }
      }

      // assert
      expect(duties.whereType<StopTheRadio>(), hasLength(1000));
      expect(duties.whereType<ScanFor>(), hasLength(1000));
      expect(scan.radio, RadioScanning(coverage([heart])));
      expect(scan.phaseOf(ScanId(id)), const Served());
      expect(scan.phaseOf(ScanId(id - 1)), const Ended(onRequest));
      expect(scan.standingOf(a), const ScannerScanning());
    });
  });
}
