import 'package:bluey/src/features/discovery/domain/scan_phase.dart';
import 'package:bluey/src/features/discovery/domain/scanner_phase.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ended = Ended(EndedByTimeout());
  const leaving = Leaving(EndedOnRequest());

  group('ScannerPhase.of', () {
    final rows = <(String, List<ScanPhase>, ScannerPhase)>[
      ('no scans', [], const ScannerIdle()),
      ('only ended scans', [ended, ended], const ScannerIdle()),
      ('a waiting scan', [const Waiting()], const ScannerStarting()),
      ('a served scan', [const Served()], const ScannerScanning()),
      ('a leaving scan', [leaving], const ScannerStopping()),
      (
        'a served scan beside a waiting one',
        [const Waiting(), const Served()],
        const ScannerScanning(),
      ),
      (
        'a served scan beside a leaving one',
        [leaving, const Served(), ended],
        const ScannerScanning(),
      ),
      (
        'a waiting scan beside a leaving one',
        [leaving, const Waiting()],
        const ScannerStarting(),
      ),
      (
        'a leaving scan beside ended ones',
        [ended, leaving],
        const ScannerStopping(),
      ),
    ];

    for (final (name, scans, expected) in rows) {
      test('$name is $expected', () {
        // arrange
        final phases = scans;

        // act
        final phase = ScannerPhase.of(phases);

        // assert
        expect(phase, expected);
      });
    }
  });

  group('equality by value', () {
    final rows = <(String, ScannerPhase, ScannerPhase, ScannerPhase)>[
      ('idle', const ScannerIdle(), ScannerIdle(), const ScannerClosed()),
      (
        'starting',
        const ScannerStarting(),
        ScannerStarting(),
        const ScannerIdle(),
      ),
      (
        'scanning',
        const ScannerScanning(),
        ScannerScanning(),
        const ScannerStarting(),
      ),
      (
        'stopping',
        const ScannerStopping(),
        ScannerStopping(),
        const ScannerScanning(),
      ),
      (
        'lost',
        const ScannerLost(RadioOutage.off),
        ScannerLost(RadioOutage.off),
        const ScannerLost(RadioOutage.unknown),
      ),
      ('closed', const ScannerClosed(), ScannerClosed(), const ScannerIdle()),
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
