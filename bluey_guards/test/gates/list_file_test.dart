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
const prefix = 'lib';
const unplaced = <String>['$prefix/a.dart -> unplaced'];
''';

      // act
      List<String>? read() => readLists(source)['unplaced'];

      // assert
      expect(read, throwsA(isA<ListFileRefusal>()));
    });
  });
}
