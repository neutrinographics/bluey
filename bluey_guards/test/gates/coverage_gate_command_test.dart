import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _measured = 'SF:lib/src/measured.dart\nLF:10\nLH:10\nend_of_record\n';

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
          '<lib folder>',
        ),
      );
    });
  });
}
