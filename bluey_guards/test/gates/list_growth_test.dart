import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

const _path = 'bluey/test/architecture/known_violations.dart';

void main() {
  group('a list file that existed at the base', () {
    test('holds when every list kept or lost entries', () {
      // arrange
      final base = {
        'unplaced': ['lib/a.dart -> unplaced', 'lib/b.dart -> unplaced'],
        'layers': <String>[],
      };
      final head = {
        'unplaced': ['lib/b.dart -> unplaced'],
        'layers': <String>[],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.holds, isTrue);
    });

    test('names an entry the base did not hold', () {
      // arrange
      final base = {
        'boundaries': ['lib/a.dart -> lib/b.dart'],
      };
      final head = {
        'boundaries': ['lib/a.dart -> lib/b.dart', 'lib/a.dart -> lib/c.dart'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.added, ['boundaries: lib/a.dart -> lib/c.dart']);
      expect(growth.holds, isFalse);
    });

    test('reads an entry moved to another list as an entry added', () {
      // arrange
      final base = {
        'boundaries': ['lib/a.dart -> lib/b.dart'],
        'layers': <String>[],
      };
      final head = {
        'boundaries': <String>[],
        'layers': ['lib/a.dart -> lib/b.dart'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.added, ['layers: lib/a.dart -> lib/b.dart']);
    });

    test('reads a list the base did not have as an empty one', () {
      // arrange
      final base = {
        'boundaries': ['lib/a.dart -> lib/b.dart'],
      };
      final head = {
        'boundaries2': ['lib/a.dart -> lib/b.dart'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.added, ['boundaries2: lib/a.dart -> lib/b.dart']);
    });

    test('holds when a size entry carries a lower count', () {
      // arrange
      final base = {
        'oversized': ['lib/a.dart -> 420 lines'],
      };
      final head = {
        'oversized': ['lib/a.dart -> 410 lines'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.holds, isTrue);
    });

    test('names a size entry whose count was raised', () {
      // arrange
      final base = {
        'oversized': ['lib/a.dart -> 410 lines'],
      };
      final head = {
        'oversized': ['lib/a.dart -> 420 lines'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.raised, [
        'oversized: lib/a.dart raised from 410 to 420 lines',
      ]);
      expect(growth.added, isEmpty);
      expect(growth.holds, isFalse);
    });

    test('names a new size entry as an entry added', () {
      // arrange
      final base = {'oversized': <String>[]};
      final head = {
        'oversized': ['lib/born.dart -> 301 lines'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.added, ['oversized: lib/born.dart -> 301 lines']);
    });
  });

  group('a list file the base did not have', () {
    test('holds, its lists the first statement of what the rules find', () {
      // arrange
      final head = {
        'unplaced': ['lib/a.dart -> unplaced'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: null, head: head);

      // assert
      expect(growth.isNew, isTrue);
      expect(growth.holds, isTrue);
    });
  });

  group('describe', () {
    test('says the file holds and how its lists changed', () {
      // arrange
      final growth = ListGrowth.between(
        path: _path,
        base: {
          'unplaced': ['lib/a.dart -> unplaced', 'lib/b.dart -> unplaced'],
        },
        head: {
          'unplaced': ['lib/b.dart -> unplaced'],
        },
      );

      // act
      final text = growth.describe();

      // assert
      expect(text, '$_path: no list grew.\n');
    });

    test('says a new file is new', () {
      // arrange
      final growth = ListGrowth.between(
        path: _path,
        base: null,
        head: {
          'unplaced': ['lib/a.dart -> unplaced'],
        },
      );

      // act
      final text = growth.describe();

      // assert
      expect(
        text,
        '$_path: not at the base, so its lists are the first statement of '
        'what they hold.\n',
      );
    });

    test('names each entry added and each count raised, and what to do', () {
      // arrange
      final growth = ListGrowth.between(
        path: _path,
        base: {
          'boundaries': <String>[],
          'oversized': ['lib/a.dart -> 410 lines'],
        },
        head: {
          'boundaries': ['lib/a.dart -> lib/c.dart'],
          'oversized': ['lib/a.dart -> 420 lines'],
        },
      );

      // act
      final text = growth.describe();

      // assert
      expect(
        text,
        '$_path: 1 entry added, 1 count raised. A list only shrinks: fix the '
        'code and take the line out of the list.\n'
        'Added:\n'
        '  boundaries: lib/a.dart -> lib/c.dart\n'
        'Raised:\n'
        '  oversized: lib/a.dart raised from 410 to 420 lines\n',
      );
    });
  });
}
