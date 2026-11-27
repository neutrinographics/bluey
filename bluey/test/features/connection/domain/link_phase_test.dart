import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_phase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('equality by value', () {
    // (name, a phase, an equal phase built apart, a phase that differs)
    final rows = <(String, LinkPhase, LinkPhase, LinkPhase)>[
      ('opening', const Opening(), Opening(), const NeverOpened()),
      ('never opened', const NeverOpened(), NeverOpened(), const Opening()),
      ('linked', const Linked(), Linked(), const Ready()),
      ('ready', const Ready(), Ready(), const Linked()),
      (
        'closing, by its way back',
        const Closing(returnTo: Ready(), by: ClosingBy.request),
        Closing(returnTo: Ready(), by: ClosingBy.request),
        const Closing(returnTo: Linked(), by: ClosingBy.request),
      ),
      (
        'closing, by who closes it',
        const Closing(returnTo: Linked(), by: ClosingBy.radio),
        Closing(returnTo: Linked(), by: ClosingBy.radio),
        const Closing(returnTo: Linked(), by: ClosingBy.both),
      ),
      (
        'ended',
        const Ended(EndedByRadioOutage(RadioOutage.off)),
        Ended(EndedByRadioOutage(RadioOutage.off)),
        const Ended(EndedByRadioOutage(RadioOutage.unknown)),
      ),
    ];

    for (final (name, phase, same, other) in rows) {
      test('$name equals a phase of the same values and no other', () {
        // assert
        expect(phase, same);
        expect(phase.hashCode, same.hashCode);
        expect(phase, isNot(other));
      });
    }
  });
}
