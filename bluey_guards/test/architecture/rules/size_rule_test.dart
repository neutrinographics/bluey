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
}
