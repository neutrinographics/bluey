import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

const _path = 'bluey/test/architecture/known_violations.dart';

/// Weighs a `<source> -> lib/src/<folder>/...` entry as one debt of its
/// source into its folder, as a boundary rule might.
({String debt, int amount}) _byFolder(String entry) {
  final [source, target] = entry.split(' -> ');
  return (debt: '$source into ${target.split('/')[2]}', amount: 1);
}

/// Weighs a `<path> -> <N> lines` entry as its path, by its lines, as a size
/// rule might.
({String debt, int amount}) _byLines(String entry) {
  final [path, lines] = entry.split(' -> ');
  return (debt: path, amount: int.parse(lines.split(' ').first));
}

void main() {
  group('a list whose entries a rule weighs', () {
    test('holds when an entry is rewritten for the same debt', () {
      // arrange
      final base = {
        'boundaries': ['lib/src/peer/a.dart -> lib/src/connection/x.dart'],
      };
      final head = {
        'boundaries': ['lib/src/peer/a.dart -> lib/src/connection/y.dart'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'boundaries': _byFolder},
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
    });

    test('names each entry of a debt the base did not owe', () {
      // arrange
      final base = {
        'boundaries': ['lib/src/peer/a.dart -> lib/src/connection/x.dart'],
      };
      final head = {
        'boundaries': [
          'lib/src/peer/a.dart -> lib/src/connection/x.dart',
          'lib/src/peer/a.dart -> lib/src/gatt_client/y.dart',
        ],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'boundaries': _byFolder},
      );

      // assert
      expect(growth.added, [
        'boundaries: lib/src/peer/a.dart -> lib/src/gatt_client/y.dart',
      ]);
      expect(growth.raised, isEmpty);
    });

    test('names a debt the head owes more of, with its new entries', () {
      // arrange
      final base = {
        'boundaries': ['lib/src/peer/a.dart -> lib/src/connection/x.dart'],
      };
      final head = {
        'boundaries': [
          'lib/src/peer/a.dart -> lib/src/connection/x.dart',
          'lib/src/peer/a.dart -> lib/src/connection/y.dart',
        ],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'boundaries': _byFolder},
      );

      // assert
      expect(growth.raised, [
        'boundaries: lib/src/peer/a.dart into connection, 1 at the base and '
            '2 at the head: lib/src/peer/a.dart -> lib/src/connection/y.dart',
      ]);
      expect(growth.added, isEmpty);
    });

    test('holds when a debt the base owed is owed less', () {
      // arrange
      final base = {
        'oversized': ['lib/a.dart -> 420 lines'],
      };
      final head = {
        'oversized': ['lib/a.dart -> 410 lines'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'oversized': _byLines},
      );

      // assert
      expect(growth.holds, isTrue);
    });

    test('counts a repeated entry once', () {
      // arrange
      final base = {
        'boundaries': ['lib/src/peer/a.dart -> lib/src/connection/x.dart'],
      };
      final head = {
        'boundaries': [
          'lib/src/peer/a.dart -> lib/src/connection/x.dart',
          'lib/src/peer/a.dart -> lib/src/connection/x.dart',
        ],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'boundaries': _byFolder},
      );

      // assert
      expect(growth.holds, isTrue);
    });

    test('holds every list it has no weight for entry by entry', () {
      // arrange
      final base = {
        'layers': ['lib/src/peer/a.dart -> lib/src/connection/x.dart'],
      };
      final head = {
        'layers': ['lib/src/peer/a.dart -> lib/src/connection/y.dart'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'boundaries': _byFolder},
      );

      // assert
      expect(growth.added, [
        'layers: lib/src/peer/a.dart -> lib/src/connection/y.dart',
      ]);
    });
  });

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

    test('names a list the base had that the head file lacks', () {
      // arrange
      final base = {
        'boundaries': ['lib/a.dart -> lib/b.dart'],
        'unplaced': <String>[],
      };
      final head = {'unplaced': <String>[]};

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: head);

      // assert
      expect(growth.gone, ['boundaries']);
      expect(growth.holds, isFalse);
    });

    test('holds when the head no longer has the file', () {
      // arrange
      final base = {
        'boundaries': ['lib/a.dart -> lib/b.dart'],
      };

      // act
      final growth = ListGrowth.between(path: _path, base: base, head: null);

      // assert
      expect(growth.holds, isTrue);
    });

    test('names a rewritten entry of a list it has no weight for', () {
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
      expect(growth.added, ['oversized: lib/a.dart -> 410 lines']);
    });

    test('names a weighed entry whose amount was raised', () {
      // arrange
      final base = {
        'oversized': ['lib/a.dart -> 410 lines'],
      };
      final head = {
        'oversized': ['lib/a.dart -> 420 lines'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'oversized': _byLines},
      );

      // assert
      expect(growth.raised, [
        'oversized: lib/a.dart, 410 at the base and 420 at the head: '
            'lib/a.dart -> 420 lines',
      ]);
      expect(growth.added, isEmpty);
      expect(growth.holds, isFalse);
    });

    test('names a new weighed entry as an entry added', () {
      // arrange
      final base = {'oversized': <String>[]};
      final head = {
        'oversized': ['lib/born.dart -> 301 lines'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        weights: {'oversized': _byLines},
      );

      // assert
      expect(growth.added, ['oversized: lib/born.dart -> 301 lines']);
    });
  });

  group('a list stated for the first time', () {
    test('may hold entries when the base lacks the list', () {
      // arrange
      final base = {'boundaries': <String>[]};
      final head = {
        'boundaries': <String>[],
        'edgeFromBelow': ['lib/src/peer/p.dart -> lib/src/api/c.dart'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        firstStatements: {'edgeFromBelow'},
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
      expect(growth.firstStated, {'edgeFromBelow': 1});
      expect(growth.notes, isEmpty);
    });

    test('says which lists it took as their first statement', () {
      // arrange
      final growth = ListGrowth.between(
        path: _path,
        base: {'boundaries': <String>[]},
        head: {
          'boundaries': <String>[],
          'edgeFromBelow': ['lib/src/peer/p.dart -> lib/src/api/c.dart'],
        },
        firstStatements: {'edgeFromBelow'},
      );

      // act
      final text = growth.describe();

      // assert
      expect(
        text,
        '$_path: no list grew.\n'
        '  edgeFromBelow: not at the base, so its 1 entry is the first '
        'statement of what it holds.\n',
      );
    });

    test('is judged as ever when the base has the list, with a note to '
        'remove the flag', () {
      // arrange
      final base = {'edgeFromBelow': <String>[]};
      final head = {
        'edgeFromBelow': ['lib/src/peer/p.dart -> lib/src/api/c.dart'],
      };

      // act
      final growth = ListGrowth.between(
        path: _path,
        base: base,
        head: head,
        firstStatements: {'edgeFromBelow'},
      );

      // assert
      expect(growth.added, [
        'edgeFromBelow: lib/src/peer/p.dart -> lib/src/api/c.dart',
      ]);
      expect(growth.firstStated, isEmpty);
      expect(growth.notes, [
        '--first-statement=edgeFromBelow no longer applies: the base has '
            'this list; remove the flag',
      ]);
      expect(growth.describe(), contains(growth.notes.single));
    });

    test('refuses a flag naming a list the head lacks', () {
      // act
      ListGrowth judge() => ListGrowth.between(
        path: _path,
        base: {'boundaries': <String>[]},
        head: {'boundaries': <String>[]},
        firstStatements: {'edgeFromBelow'},
      );

      // assert
      expect(judge, throwsArgumentError);
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

    test('names each list that is gone, and what to do', () {
      // arrange
      final growth = ListGrowth.between(
        path: _path,
        base: {'boundaries': <String>[]},
        head: {},
      );

      // act
      final text = growth.describe();

      // assert
      expect(
        text,
        '$_path: 1 list gone. A list file keeps every list it had: put the '
        'list back here, under its name.\n'
        'Gone:\n'
        '  boundaries\n',
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
        weights: {'oversized': _byLines},
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
        '  oversized: lib/a.dart, 410 at the base and 420 at the head: '
        'lib/a.dart -> 420 lines\n',
      );
    });
  });
}
