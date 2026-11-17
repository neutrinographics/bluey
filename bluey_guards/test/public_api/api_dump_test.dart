import 'dart:io';

import 'package:bluey_guards/public_api.dart';
import 'package:test/test.dart';

Future<String> _dump(String fixture) =>
    dumpPublicApi('test/public_api/fixtures/$fixture.dart');

void main() {
  group('dumpPublicApi', () {
    late String dump;
    setUpAll(() async => dump = await _dump('shapes'));

    test(
      'lists a class under its header with the members written in source',
      () {
        // arrange
        const members = [
          '  Shape(String name, {required int sides})',
          '  String describe({bool short = false})',
          '  int get area',
          '  int sides',
          '  static int count()',
        ];

        // assert
        expect(dump, contains('class Shape\n'));
        for (final line in members) {
          expect(dump, contains('$line\n'));
        }
      },
    );

    test('lists an enum with its values and nothing the language added', () {
      // assert
      expect(dump, contains('enum Side\n  Side left\n  Side right\n'));
    });

    test('lists functions, type aliases and top-level values', () {
      // assert
      expect(
        dump,
        allOf(contains('twice('), contains('Measure'), contains('answer')),
      );
    });

    test('marks only a member as static, never a top-level function', () {
      // assert
      expect('\n$dump', contains('\nint twice(int value)\n'));
    });

    test('carries const, final, late and factory as they are declared', () {
      // arrange
      const lines = [
        'const int answer',
        '  factory Shape.square()',
        '  static const int corners',
        '  final String name',
        '  late String label',
        'class Unit\n  const Unit()',
      ];

      // assert
      for (final line in lines) {
        expect('\n$dump', contains('\n$line\n'));
      }
    });

    test('lists a field once, not again as its getter', () {
      // act
      final fieldLines = '  final String name\n'.allMatches(dump);

      // assert
      expect(fieldLines, hasLength(1));
      expect(dump, isNot(contains('get name')));
    });

    test('leaves out what is private and what an export hides', () {
      // arrange
      const absent = ['NotShown', '_Hidden', '_cache', '_forget'];

      // assert
      expect(dump, contains('class Shown\n'));
      for (final name in absent) {
        expect(dump, isNot(contains(name)));
      }
    });

    test('puts the blocks in name order and ends with one line break', () {
      // assert
      expect(
        dump.indexOf('class Shape'),
        lessThan(dump.indexOf('class Shown')),
      );
      expect(
        dump.indexOf('enum Side'),
        greaterThan(dump.indexOf('class Shown')),
      );
      expect(dump, endsWith('\n'));
      expect(dump, isNot(endsWith('\n\n')));
    });

    test(
      'is the same text when declarations and members are reordered',
      () async {
        // act
        final reordered = await _dump('shapes_reordered');

        // assert
        expect(reordered, dump);
      },
    );

    test(
      'differs by exactly the changed member when a signature changes',
      () async {
        // arrange
        final changed = await _dump('shapes_changed');

        // act
        final difference = ApiDifference.between(
          committed: dump,
          current: changed,
        );

        // assert
        expect(difference.removed, [
          'class Shape > String describe({bool short = false})',
        ]);
        expect(difference.added, [
          'class Shape > String describe({bool short = true})',
        ]);
      },
    );
  });

  group('dumpPublicApi on a library that does not resolve', () {
    late Directory scratch;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('public_api_broken_');
    });

    tearDown(() => scratch.deleteSync(recursive: true));

    test('refuses to dump it and names the library and its error', () async {
      // arrange
      final library = File('${scratch.path}/broken.dart')
        ..writeAsStringSync("export 'missing.dart';\n");

      // act
      final dumping = dumpPublicApi(library.path);

      // assert
      await expectLater(
        dumping,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('broken.dart'), contains("'missing.dart'")),
          ),
        ),
      );
    });

    test(
      'refuses an exported file that does not resolve and names its error',
      () async {
        // arrange
        Directory('${scratch.path}/src').createSync();
        File('${scratch.path}/src/a.dart').writeAsStringSync(
          "import 'package:nope/nope.dart';\n\nclass A {\n  A(this.x);\n  final Nope x;\n}\n",
        );
        final library = File('${scratch.path}/probe.dart')
          ..writeAsStringSync("export 'src/a.dart';\n");

        // act
        final dumping = dumpPublicApi(library.path);

        // assert
        await expectLater(
          dumping,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('probe.dart'),
                contains('src/a.dart:1:'),
                contains('package:nope/nope.dart'),
              ),
            ),
          ),
        );
      },
    );

    test('refuses a dump that would name an unresolved type', () async {
      // arrange
      final library = File('${scratch.path}/quiet.dart')..writeAsStringSync(
        "// ignore_for_file: uri_does_not_exist, undefined_class\n"
        "import 'package:nope/nope.dart';\n\nclass A {\n  A(this.x);\n  final Nope x;\n}\n",
      );

      // act
      final dumping = dumpPublicApi(library.path);

      // assert
      await expectLater(
        dumping,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('quiet.dart'), contains('final InvalidType x')),
          ),
        ),
      );
    });
  });
}
