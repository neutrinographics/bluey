import 'package:bluey/src/api/discovery/scan_state.dart';
import 'package:bluey/src/api/discovery/scan_state_translation.dart';
import 'package:bluey/src/features/discovery/domain/scanner_phase.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scanStateOf', () {
    // (name, phase, the state an app reads)
    final rows = <(String, ScannerPhase, ScanState)>[
      ('idle', const ScannerIdle(), ScanState.stopped),
      ('starting', const ScannerStarting(), ScanState.starting),
      ('scanning', const ScannerScanning(), ScanState.scanning),
      ('stopping', const ScannerStopping(), ScanState.stopping),
      (
        'lost to an outage',
        const ScannerLost(RadioOutage.off),
        ScanState.invalidated,
      ),
      ('closed', const ScannerClosed(), ScanState.stopped),
    ];

    for (final (name, phase, state) in rows) {
      test('a scanner $name reads as ${state.name}', () {
        // arrange
        final given = phase;

        // act
        final read = scanStateOf(given);

        // assert
        expect(read, state);
      });
    }
  });
}
