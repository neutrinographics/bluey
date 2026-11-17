import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

SourceFile _file(String content) =>
    SourceFile(path: 'lib/a.dart', content: content);

void main() {
  group('lineCount', () {
    test('counts each line of text once', () {
      // arrange
      final file = _file('a\nb\n');

      // act
      final lines = file.lineCount;

      // assert
      expect(lines, 2);
    });

    test('counts a last line that has no line break', () {
      // arrange
      final file = _file('a\nb');

      // act
      final lines = file.lineCount;

      // assert
      expect(lines, 2);
    });

    test('counts a Windows line break once', () {
      // arrange
      final file = _file('a\r\nb\r\n');

      // act
      final lines = file.lineCount;

      // assert
      expect(lines, 2);
    });

    test('is zero for an empty file', () {
      // arrange
      final file = _file('');

      // act
      final lines = file.lineCount;

      // assert
      expect(lines, 0);
    });
  });

  group('hasExtension', () {
    test('matches the whole extension', () {
      // arrange
      final file = _file('');

      // act
      final dart = file.hasExtension('.dart');
      final art = file.hasExtension('.art');

      // assert
      expect(dart, isTrue);
      expect(art, isFalse);
    });
  });
}
