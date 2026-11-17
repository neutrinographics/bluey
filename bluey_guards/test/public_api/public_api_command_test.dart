import 'dart:io';

import 'package:test/test.dart';

const _library = 'test/public_api/fixtures/shapes.dart';

void main() {
  group('the public_api command', () {
    late Directory compiled;
    late String command;
    late Directory scratch;
    late String dumpPath;

    Future<ProcessResult> run(List<String> arguments) =>
        Process.run(Platform.resolvedExecutable, [command, ...arguments]);

    setUpAll(() async {
      compiled = Directory.systemTemp.createTempSync('public_api_command_');
      command = '${compiled.path}/public_api.dill';
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'bin/public_api.dart',
        '-o',
        command,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');
    });

    tearDownAll(() => compiled.deleteSync(recursive: true));

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('public_api_');
      dumpPath = '${scratch.path}/shapes.api';
    });

    tearDown(() => scratch.deleteSync(recursive: true));

    test('writes the dump with --write and then finds it current', () async {
      // act
      final write = await run([_library, dumpPath, '--write']);
      final check = await run([_library, dumpPath]);

      // assert
      expect(write.exitCode, 0);
      expect(File(dumpPath).readAsStringSync(), contains('class Shape\n'));
      expect(check.exitCode, 0, reason: '${check.stdout}${check.stderr}');
    });

    test(
      'names each changed line and exits 1 when the dump is stale',
      () async {
        // arrange
        await run([_library, dumpPath, '--write']);
        final stale = File(dumpPath).readAsStringSync().replaceFirst(
          '  int get area\n',
          '  int get volume\n',
        );
        File(dumpPath).writeAsStringSync(stale);

        // act
        final check = await run([_library, dumpPath]);

        // assert
        expect(check.exitCode, 1);
        expect(
          check.stdout,
          allOf(
            contains('- class Shape > int get volume\n'),
            contains('+ class Shape > int get area\n'),
            contains(
              'The public API changed. If that was meant, run this command '
              'with --write and review the dump as an API change.',
            ),
          ),
        );
      },
    );

    test(
      'exits 1 naming the error for a library that does not resolve',
      () async {
        // arrange
        final broken = File('${scratch.path}/broken.dart')
          ..writeAsStringSync("export 'missing.dart';\n");

        // act
        final write = await run([broken.path, dumpPath, '--write']);

        // assert
        expect(write.exitCode, 1);
        expect(
          write.stderr,
          allOf(
            contains('Cannot dump the public API of'),
            contains("'missing.dart'"),
            isNot(contains('#0')),
          ),
        );
        expect(File(dumpPath).existsSync(), isFalse);
      },
    );

    test('exits 64 with the usage line for any other arguments', () async {
      // act
      final results = [
        await run([]),
        await run([_library]),
        await run([_library, dumpPath, '--force']),
      ];

      // assert
      for (final result in results) {
        expect(result.exitCode, 64);
        expect(
          result.stderr,
          contains(
            'dart run bluey_guards:public_api <library> <dump> [--write]',
          ),
        );
      }
    });
  });
}
