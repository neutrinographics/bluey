import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

final _rule = SizeRule(limit: 3, extension: '.dart');

void main() {
  group('files of one extension against a limit', () {
    test('lists a file over the limit with its line count', () {
      // arrange
      final files = tree({
        'android/A.kt': 'a\nb\nc\nd\ne\n',
        'lib/a.dart': 'a\nb\nc\nd\n',
        'lib/b.dart': 'a\nb\nc\n',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, ['lib/a.dart -> 4 lines']);
    });

    test('is named for the files it measures', () {
      // act
      final name = _rule.name;

      // assert
      expect(name, 'size of .dart files');
    });
  });

  group('a known entry and a found entry of one file', () {
    test('tells a file that grew to shrink, never to raise its entry', () {
      // arrange
      const known = 'lib/a.dart -> 410 lines';
      const found = 'lib/a.dart -> 420 lines';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(
        change,
        'lib/a.dart grew from 410 to 420 lines: shrink the file to 410 lines '
        'or fewer; never raise the entry',
      );
    });

    test('tells a file that shrank to lower its entry to the new count', () {
      // arrange
      const known = 'lib/src/bluey.dart -> 1040 lines';
      const found = 'lib/src/bluey.dart -> 1002 lines';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(
        change,
        'lib/src/bluey.dart shrank from 1040 to 1002 lines: lower its entry '
        'to 1002',
      );
    });

    test('is no change when the two entries are of different files', () {
      // arrange
      const known = 'lib/gone.dart -> 500 lines';
      const found = 'lib/born.dart -> 301 lines';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(change, isNull);
    });

    test('is no change when an entry is not a size entry', () {
      // arrange
      const known = 'lib/a.dart -> unplaced';
      const found = 'lib/a.dart -> 301 lines';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(change, isNull);
    });
  });

  group('the debt an entry records', () {
    test('is its file, weighed by its lines', () {
      // act
      final debt = _rule.weigh('lib/a.dart -> 420 lines');

      // assert
      expect(debt, (debt: 'lib/a.dart', amount: 420));
    });

    test('is the entry itself, once, for an entry of another shape', () {
      // act
      final debt = _rule.weigh('lib/a.dart -> unplaced');

      // assert
      expect(debt, (debt: 'lib/a.dart -> unplaced', amount: 1));
    });
  });
}
