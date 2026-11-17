import 'dart:io';

import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

void main() {
  group('read', () {
    late Directory root;

    void write(String path, String content) =>
        File('${root.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);

    setUp(() {
      root = Directory.systemTemp.createTempSync('bluey_guards');
      write('lib/b.dart', 'b');
      write('lib/src/a.dart', 'a');
      write('lib/src/messages.g.dart', 'generated');
      write('lib/notes.md', 'notes');
      write('test/a_test.dart', 'test');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test(
      'lists the files under the named folders, sorted, by package-relative path',
      () {
        // act
        final tree = SourceTree.read(
          root,
          under: ['lib', 'ios/Classes'],
          extensions: {'.dart'},
        );

        // assert
        expect(tree.files.map((file) => file.path), [
          'lib/b.dart',
          'lib/src/a.dart',
        ]);
        expect(tree.file('lib/src/a.dart')?.content, 'a');
        expect(tree.file('lib/src/messages.g.dart'), isNull);
      },
    );

    test('keeps a generated file when told nothing is generated', () {
      // act
      final tree = SourceTree.read(
        root,
        under: ['lib'],
        extensions: {'.dart'},
        isGenerated: (_) => false,
      );

      // assert
      expect(
        tree.files.map((file) => file.path),
        contains('lib/src/messages.g.dart'),
      );
    });
  });

  group('isGeneratedSource', () {
    test('knows a Pigeon output in each language', () {
      // act
      final dart = isGeneratedSource('lib/src/messages.g.dart');
      final kotlin = isGeneratedSource('android/src/main/kotlin/Messages.g.kt');
      final swift = isGeneratedSource('ios/Classes/Messages.g.swift');
      final otherInfix = isGeneratedSource('ios/Classes/Messages.x.swift');
      final plain = isGeneratedSource('lib/src/gatt.dart');

      // assert
      expect(dart, isTrue);
      expect(kotlin, isTrue);
      expect(swift, isTrue);
      expect(otherInfix, isFalse);
      expect(plain, isFalse);
    });
  });

  group('dartSources', () {
    test('parses the Dart files and no others', () {
      // arrange
      final tree = SourceTree([
        const SourceFile(path: 'lib/a.dart', content: "import 'b.dart';"),
        const SourceFile(path: 'lib/analysis_options.yaml', content: 'linter:'),
      ]);

      // act
      final sources = tree.dartSources;

      // assert
      expect(sources.map((source) => source.path), ['lib/a.dart']);
    });
  });
}
