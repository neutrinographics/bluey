import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanEnd equality by value', () {
    final rows = <(String, ScanEnd, ScanEnd, ScanEnd)>[
      (
        'on request',
        const EndedOnRequest(),
        EndedOnRequest(),
        const EndedByTimeout(),
      ),
      (
        'by timeout',
        const EndedByTimeout(),
        EndedByTimeout(),
        const EndedOnRequest(),
      ),
      (
        'by failure',
        const EndedByFailure(ScanRadioUnavailable()),
        EndedByFailure(ScanRadioUnavailable()),
        const EndedByFailure(ScanPermissionMissing('scan')),
      ),
      (
        'by radio outage',
        const EndedByRadioOutage(RadioOutage.off),
        EndedByRadioOutage(RadioOutage.off),
        const EndedByRadioOutage(RadioOutage.unknown),
      ),
    ];

    for (final (name, end, same, other) in rows) {
      test('$name equals an end of the same values and no other', () {
        // arrange
        final built = same;

        // act
        final equal = end == built;

        // assert
        expect(equal, isTrue);
        expect(end.hashCode, built.hashCode);
        expect(end, isNot(other));
      });
    }
  });

  group('ScanPhase equality by value', () {
    final rows = <(String, ScanPhase, ScanPhase, ScanPhase)>[
      ('waiting', const Waiting(), Waiting(), const Served()),
      ('served', const Served(), Served(), const Waiting()),
      (
        'leaving',
        const Leaving(EndedOnRequest()),
        Leaving(EndedOnRequest()),
        const Leaving(EndedByTimeout()),
      ),
      (
        'ended',
        const Ended(EndedByTimeout()),
        Ended(EndedByTimeout()),
        const Leaving(EndedByTimeout()),
      ),
    ];

    for (final (name, phase, same, other) in rows) {
      test('$name equals a phase of the same values and no other', () {
        // arrange
        final built = same;

        // act
        final equal = phase == built;

        // assert
        expect(equal, isTrue);
        expect(phase.hashCode, built.hashCode);
        expect(phase, isNot(other));
      });
    }
  });
}
