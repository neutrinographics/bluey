import 'package:bluey/src/features/discovery/application/scan_turns.dart';
import 'package:bluey/src/features/discovery/domain/radio_scan_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a decision that throws', () {
    test('is raised to the caller once every queued turn has run', () {
      // arrange
      final ran = <String>[];
      final turns = ScanTurns((input) => ran.add('step'));

      // act
      void decideAll() => turns.decide(() {
        turns.decide(() => throw StateError('a programming error'));
        turns.decide(() => ran.add('later decision'));
        turns.feed(const ShutDown());
      });

      // assert
      expect(decideAll, throwsStateError);
      expect(ran, ['step', 'later decision']);
    });

    test('leaves the turns usable', () {
      // arrange
      final ran = <String>[];
      final turns = ScanTurns((input) => ran.add('step'));
      expect(
        () => turns.decide(() => throw StateError('a programming error')),
        throwsStateError,
      );

      // act
      turns.feed(const ShutDown());

      // assert
      expect(ran, ['step']);
    });
  });
}
