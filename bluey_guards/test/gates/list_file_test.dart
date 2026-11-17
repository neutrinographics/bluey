import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

void main() {
  group('readLists', () {
    test('reads every top-level list of strings by its name', () {
      // arrange
      const source = '''
/// What the rules find today.
library;

/// The library files not yet in the target layout.
const unplaced = <String>[
  'lib/src/a.dart -> unplaced',
  'lib/src/b.dart -> unplaced',
];

const layers = <String>[];
''';

      // act
      final lists = readLists(source);

      // assert
      expect(lists, {
        'unplaced': [
          'lib/src/a.dart -> unplaced',
          'lib/src/b.dart -> unplaced',
        ],
        'layers': <String>[],
      });
    });

    test('reads an entry written as adjacent strings as one entry', () {
      // arrange
      const source = '''
const oversized = <String>[
  'android/src/main/kotlin/com/example/'
      'Plugin.kt -> 785 lines',
];
''';

      // act
      final lists = readLists(source);

      // assert
      expect(lists['oversized'], [
        'android/src/main/kotlin/com/example/Plugin.kt -> 785 lines',
      ]);
    });

    test('refuses an entry that is not a plain string', () {
      // arrange
      const source = r'''
const unplaced = <String>['$prefix/a.dart -> unplaced'];
''';

      // act
      List<String>? read() => readLists(source)['unplaced'];

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });
  });

  group('a declaration that is not a list of plain strings', () {
    test('is refused: a list built by a call on a list literal', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
const boundaries = <String>[
  'lib/a.dart -> lib/b.dart',
].toList();
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a list built by a constructor', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
final boundaries = List<String>.unmodifiable(['lib/a.dart -> lib/b.dart']);
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a getter', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
List<String> get boundaries => ['lib/a.dart -> lib/b.dart'];
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a function', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
List<String> boundaries() => ['lib/a.dart -> lib/b.dart'];
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a set literal', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
const boundaries = <String>{'lib/a.dart -> lib/b.dart'};
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a variable with no initializer', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
late final List<String> boundaries;
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a file that does not parse', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });

    test('is refused: a class', () {
      // arrange
      const source = '''
const unplaced = <String>['lib/a.dart -> unplaced'];
class Boundaries {}
''';

      // act
      Map<String, List<String>> read() => readLists(source);

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });
  });

  test('names a refused list in one short line, however long the list', () {
    // arrange
    final entries = [for (var i = 0; i < 50; i++) "'lib/a$i.dart -> unplaced'"];
    final source = 'const unplaced = <String>[${entries.join(', ')}].toList();';

    // act
    String refusal() {
      try {
        readLists(source);
      } on ListFileRefusal catch (refusal) {
        return refusal.message;
      }
      return '';
    }

    // assert
    expect(refusal().length, lessThan(160));
    expect(refusal(), startsWith('The list unplaced is not a list literal'));
  });
}
