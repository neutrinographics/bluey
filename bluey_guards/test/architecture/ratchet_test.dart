import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

void main() {
  group('judge', () {
    test(
      'holds when what was found is exactly what is known, in any order',
      () {
        // act
        final verdict = Ratchet.judge(found: ['b', 'a'], known: ['a', 'b']);

        // assert
        expect(verdict.holds, isTrue);
      },
    );

    test('names a violation that is not on the list', () {
      // act
      final verdict = Ratchet.judge(found: ['a', 'new'], known: ['a']);

      // assert
      expect(verdict.unlisted, ['new']);
      expect(verdict.stale, isEmpty);
      expect(verdict.holds, isFalse);
    });

    test('names an entry whose file moved, was deleted or was fixed', () {
      // act
      final verdict = Ratchet.judge(
        found: ['a'],
        known: ['a', 'lib/src/gone.dart -> unplaced'],
      );

      // assert
      expect(verdict.stale, ['lib/src/gone.dart -> unplaced']);
      expect(verdict.holds, isFalse);
    });

    test('treats a size entry whose count changed as both', () {
      // act
      final verdict = Ratchet.judge(
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
      final verdict = Ratchet.judge(found: ['new'], known: ['old']);

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

    test('tells a file that grew to shrink, and never to raise its entry', () {
      // arrange
      final verdict = Ratchet.judge(
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
        'A size entry that no longer matches its file:\n'
        '  lib/a.dart grew from 410 to 420 lines: shrink the file to 410 '
        'lines or fewer; never raise the entry\n',
      );
    });

    test('tells a file that shrank to lower its entry to the new count', () {
      // arrange
      final verdict = Ratchet.judge(
        found: ['lib/src/bluey.dart -> 1002 lines', 'new'],
        known: ['lib/src/bluey.dart -> 1040 lines', 'old'],
      );

      // act
      final text = verdict.describe('size of .dart files');

      // assert
      expect(
        text,
        'size of .dart files: 2 not on its list, 2 on its list that no longer '
        'holds.\n'
        'Not on the list. Fix it; a list never grows:\n'
        '  new\n'
        'On the list but no longer true. Delete the entry:\n'
        '  old\n'
        'A size entry that no longer matches its file:\n'
        '  lib/src/bluey.dart shrank from 1040 to 1002 lines: lower its entry '
        'to 1002\n',
      );
    });

    test('reads a size entry alone in one part as any other entry', () {
      // arrange
      final verdict = Ratchet.judge(
        found: ['lib/born.dart -> 301 lines'],
        known: ['lib/gone.dart -> 500 lines'],
      );

      // act
      final text = verdict.describe('size of .dart files');

      // assert
      expect(
        text,
        'size of .dart files: 1 not on its list, 1 on its list that no longer '
        'holds.\n'
        'Not on the list. Fix it; a list never grows:\n'
        '  lib/born.dart -> 301 lines\n'
        'On the list but no longer true. Delete the entry:\n'
        '  lib/gone.dart -> 500 lines\n',
      );
    });

    test('leaves out a part that is empty', () {
      // arrange
      final verdict = Ratchet.judge(found: [], known: ['old']);

      // act
      final text = verdict.describe('boundaries');

      // assert
      expect(text, isNot(contains('Not on the list')));
    });
  });
}
