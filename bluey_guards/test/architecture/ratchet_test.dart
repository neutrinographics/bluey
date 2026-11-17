import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

void main() {
  group('ratchet', () {
    test(
      'holds when what was found is exactly what is known, in any order',
      () {
        // act
        final verdict = ratchet(found: ['b', 'a'], known: ['a', 'b']);

        // assert
        expect(verdict.holds, isTrue);
      },
    );

    test('names a violation that is not on the list', () {
      // act
      final verdict = ratchet(found: ['a', 'new'], known: ['a']);

      // assert
      expect(verdict.unlisted, ['new']);
      expect(verdict.stale, isEmpty);
      expect(verdict.holds, isFalse);
    });

    test('names an entry whose file moved, was deleted or was fixed', () {
      // act
      final verdict = ratchet(
        found: ['a'],
        known: ['a', 'lib/src/gone.dart -> unplaced'],
      );

      // assert
      expect(verdict.stale, ['lib/src/gone.dart -> unplaced']);
      expect(verdict.holds, isFalse);
    });

    test('treats a size entry whose count changed as both', () {
      // act
      final verdict = ratchet(
        found: ['lib/a.dart -> 310 lines'],
        known: ['lib/a.dart -> 320 lines'],
      );

      // assert
      expect(verdict.unlisted, ['lib/a.dart -> 310 lines']);
      expect(verdict.stale, ['lib/a.dart -> 320 lines']);
    });
  });

  group('describe', () {
    test('says which rule, what to fix and what to delete', () {
      // arrange
      final verdict = ratchet(found: ['new'], known: ['old']);

      // act
      final text = verdict.describe('boundaries');

      // assert
      expect(
        text,
        'boundaries: 1 not on its list, 1 on its list that no longer holds.\n'
        'Not on the list. Fix it; a list never grows:\n'
        '  new\n'
        'On the list but no longer true. Delete the entry:\n'
        '  old\n',
      );
    });

    test('tells a pair of entries the rule reads as one change apart', () {
      // arrange
      final verdict = ratchet(
        found: ['lib/a.dart -> 420 lines', 'new'],
        known: ['lib/a.dart -> 410 lines', 'old'],
      );
      String? change({required String known, required String found}) =>
          known.startsWith('lib/a.dart') && found.startsWith('lib/a.dart')
              ? 'lib/a.dart changed from "$known" to "$found"'
              : null;

      // act
      final text = verdict.describe('size of .dart files', change: change);

      // assert
      expect(
        text,
        'size of .dart files: 2 not on its list, 2 on its list that no longer '
        'holds.\n'
        'Not on the list. Fix it; a list never grows:\n'
        '  new\n'
        'On the list but no longer true. Delete the entry:\n'
        '  old\n'
        'On the list, but what it names changed:\n'
        '  lib/a.dart changed from "lib/a.dart -> 410 lines" to '
        '"lib/a.dart -> 420 lines"\n',
      );
    });

    test('reads every entry alone when no change is given', () {
      // arrange
      final verdict = ratchet(
        found: ['lib/a.dart -> 420 lines'],
        known: ['lib/a.dart -> 410 lines'],
      );

      // act
      final text = verdict.describe('size of .dart files');

      // assert
      expect(
        text,
        'size of .dart files: 1 not on its list, 1 on its list that no longer '
        'holds.\n'
        'Not on the list. Fix it; a list never grows:\n'
        '  lib/a.dart -> 420 lines\n'
        'On the list but no longer true. Delete the entry:\n'
        '  lib/a.dart -> 410 lines\n',
      );
    });

    test('leaves out a part that is empty', () {
      // arrange
      final verdict = ratchet(found: [], known: ['old']);

      // act
      final text = verdict.describe('boundaries');

      // assert
      expect(text, isNot(contains('Not on the list')));
    });
  });
}
