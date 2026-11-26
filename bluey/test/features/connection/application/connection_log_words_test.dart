import 'package:bluey/src/features/connection/application/connection_log_words.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_phase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the context is the one apps filter on', () {
    // assert
    expect(connectionLogContext, 'bluey.connection');
  });

  group('stateWordOf', () {
    // (name, phase, the word logs have always written)
    final rows = <(String, LinkPhase, String)>[
      ('linked', const Linked(), 'ConnectionState.linked'),
      ('ready', const Ready(), 'ConnectionState.ready'),
      (
        'closing',
        const Closing(returnTo: Linked(), by: ClosingBy.radio),
        'ConnectionState.disconnecting',
      ),
      (
        'ended on request',
        const Ended(EndedOnRequest()),
        'ConnectionState.disconnected',
      ),
      (
        'ended by a drop',
        const Ended(EndedByDrop()),
        'ConnectionState.disconnected',
      ),
      (
        'ended by an outage',
        const Ended(EndedByRadioOutage(RadioOutage.unknown)),
        'ConnectionState.invalidated',
      ),
    ];

    for (final (name, phase, word) in rows) {
      test('a link $name is logged as $word', () {
        // act
        final logged = stateWordOf(phase);

        // assert
        expect(logged, word);
      });
    }
  });
}
