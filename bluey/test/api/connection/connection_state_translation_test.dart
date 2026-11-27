import 'package:bluey/src/api/connection/connection_state.dart';
import 'package:bluey/src/api/connection/connection_state_translation.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_phase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connectionStateOf', () {
    // (name, phase, the state an app reads)
    final rows = <(String, LinkPhase, ConnectionState)>[
      ('linked', const Linked(), ConnectionState.linked),
      ('ready', const Ready(), ConnectionState.ready),
      (
        'closing',
        const Closing(returnTo: Ready(), by: ClosingBy.both),
        ConnectionState.disconnecting,
      ),
      (
        'ended on request',
        const Ended(EndedOnRequest()),
        ConnectionState.disconnected,
      ),
      (
        'ended by a drop',
        const Ended(EndedByDrop()),
        ConnectionState.disconnected,
      ),
      (
        'ended by the radio turned off',
        const Ended(EndedByRadioOutage(RadioOutage.off)),
        ConnectionState.invalidated,
      ),
      (
        'ended by the radio refused to the app',
        const Ended(EndedByRadioOutage(RadioOutage.unauthorized)),
        ConnectionState.invalidated,
      ),
    ];

    for (final (name, phase, state) in rows) {
      test('a link $name reads as ${state.name}', () {
        // act
        final read = connectionStateOf(phase);

        // assert
        expect(read, state);
      });
    }
  });
}
