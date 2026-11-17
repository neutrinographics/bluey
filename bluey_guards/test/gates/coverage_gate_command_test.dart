import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _measured = 'SF:lib/src/measured.dart\nLF:10\nLH:10\nend_of_record\n';

/// A report where the domain is fully covered and the rest of the package
/// is not, so a floor over the domain alone and one over the whole package
/// answer differently.
const _domainCovered =
    'SF:lib/src/features/a/domain/link.dart\nLF:10\nLH:10\nend_of_record\n'
    'SF:lib/src/measured.dart\nLF:10\nLH:5\nend_of_record\n';

void main() {
  group('the coverage_gate command', () {
    late Directory compiled;
    late String command;
    late Directory package;

    Future<ProcessResult> run(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      [command, ...arguments],
      workingDirectory: package.path,
    );

    void write(String path, String content) {
      File(p.join(package.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    setUpAll(() async {
      compiled = Directory.systemTemp.createTempSync('coverage_gate_command_');
      command = '${compiled.path}/coverage_gate.dill';
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'bin/coverage_gate.dart',
        '-o',
        command,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');
    });

    tearDownAll(() => compiled.deleteSync(recursive: true));

    setUp(() {
      package = Directory.systemTemp.createTempSync('coverage_gate_');
      write('lib/src/measured.dart', 'int one() => 1;\n');
      write('lib/src/state.dart', 'enum State { on, off }\n');
    });

    tearDown(() => package.deleteSync(recursive: true));

    test('exits 0 when the floor is met and every file is measured', () async {
      // arrange
      write('coverage/lcov.info', _measured);

      // act
      final result = await run(['coverage/lcov.info', '90', 'lib']);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
        result.stdout,
        'Line coverage 100.0% (10 of 10 lines). The floor is 90%.\n',
      );
    });

    test('exits 1 naming a file with code no test loaded', () async {
      // arrange
      write('coverage/lcov.info', _measured);
      write('lib/src/unloaded.dart', 'int two() => 2;\n');

      // act
      final result = await run(['coverage/lcov.info', '90', 'lib']);

      // assert
      expect(result.exitCode, 1);
      expect(
        result.stdout,
        'Line coverage 100.0% (10 of 10 lines). The floor is 90%.\n'
        'Not in the report, though each holds code that runs. No test loads '
        'it; write the test that does:\n'
        '  lib/src/unloaded.dart\n',
      );
    });

    test('reads a report that names files by their absolute path', () async {
      // arrange
      final absolute = p.join(package.resolveSymbolicLinksSync(), 'lib');
      write(
        'coverage/lcov.info',
        'SF:$absolute/src/measured.dart\nLF:10\nLH:10\nend_of_record\n',
      );

      // act
      final result = await run(['coverage/lcov.info', '90', 'lib']);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });

    test('exits 1 when the floor is not met', () async {
      // arrange
      write(
        'coverage/lcov.info',
        'SF:lib/src/measured.dart\nLF:10\nLH:8\nend_of_record\n',
      );

      // act
      final result = await run(['coverage/lcov.info', '90', 'lib']);

      // assert
      expect(result.exitCode, 1);
    });

    group('over path patterns', () {
      setUp(() {
        write('lib/src/features/a/domain/link.dart', 'int link() => 1;\n');
      });

      test('holds only the files under the patterns to the floor', () async {
        // arrange
        write('coverage/lcov.info', _domainCovered);

        // act
        final result = await run([
          'coverage/lcov.info',
          '95',
          'lib',
          'lib/src/features/*/domain',
          'lib/src/shared/domain',
        ]);

        // assert
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(
          result.stdout,
          'Line coverage of lib/src/features/*/domain and '
          'lib/src/shared/domain 100.0% (10 of 10 lines). The floor is 95%.\n',
        );
      });

      test(
        'exits 1 when the files under the patterns miss the floor',
        () async {
          // arrange
          write(
            'coverage/lcov.info',
            'SF:lib/src/features/a/domain/link.dart\nLF:10\nLH:9\n'
                'end_of_record\n',
          );

          // act
          final result = await run([
            'coverage/lcov.info',
            '95',
            'lib',
            'lib/src/features/*/domain',
          ]);

          // assert
          expect(result.exitCode, 1);
        },
      );

      test(
        'names an unloaded file only when it is under the patterns',
        () async {
          // arrange
          write('coverage/lcov.info', _domainCovered);
          write('lib/src/unloaded.dart', 'int two() => 2;\n');
          write(
            'lib/src/features/a/domain/unloaded.dart',
            'int three() => 3;\n',
          );

          // act
          final result = await run([
            'coverage/lcov.info',
            '95',
            'lib',
            'lib/src/features/*/domain',
          ]);

          // assert
          expect(result.exitCode, 1);
          expect(
            result.stdout,
            contains('  lib/src/features/a/domain/unloaded.dart\n'),
          );
          expect(result.stdout, isNot(contains('lib/src/unloaded.dart')));
        },
      );

      test('passes, saying so, when no line is under the patterns', () async {
        // arrange
        write('coverage/lcov.info', _measured);

        // act
        final result = await run([
          'coverage/lcov.info',
          '95',
          'lib',
          'lib/src/shared/domain',
        ]);

        // assert
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(
          result.stdout,
          'No line under lib/src/shared/domain is in the report or holds code '
          'that runs, so the 95% floor holds nothing yet.\n',
        );
      });
    });

    test('exits 64 with the usage line without the lib folder', () async {
      // arrange
      write('coverage/lcov.info', _measured);

      // act
      final result = await run(['coverage/lcov.info', '90']);

      // assert
      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains(
          'Usage: dart run bluey_guards:coverage_gate <lcov file> <minimum> '
          '<lib folder> [<path pattern>...]',
        ),
      );
    });
  });
}
