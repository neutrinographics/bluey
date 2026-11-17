import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _run = '''
{"test":{"id":1,"name":"H2 probes"},"type":"testStart"}
{"testID":1,"error":"Expected: true","isFailure":true,"type":"error"}
{"testID":1,"result":"failure","skipped":false,"hidden":false,"type":"testDone"}
{"success":false,"type":"done","time":1200}
''';

void main() {
  group('the known_defects command', () {
    late Directory compiled;
    late String command;
    late Directory scratch;

    Future<ProcessResult> run(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      [command, ...arguments],
      workingDirectory: scratch.path,
    );

    void write(String path, String content) {
      File(p.join(scratch.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    setUpAll(() async {
      compiled = Directory.systemTemp.createTempSync('known_defects_command_');
      command = '${compiled.path}/known_defects.dill';
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'bin/known_defects.dart',
        '-o',
        command,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');
    });

    tearDownAll(() => compiled.deleteSync(recursive: true));

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('known_defects_');
      write('run.json', _run);
    });

    tearDown(() => scratch.deleteSync(recursive: true));

    test('exits 0 when the run holds exactly its roster, failing', () async {
      // arrange
      write('roster.dart', "const knownDefects = <String>['H2 probes'];\n");

      // act
      final result = await run(['roster.dart', 'run.json']);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('    Expected: true\n'));
    });

    test('exits 1 when the roster names a defect the run lacks', () async {
      // arrange
      write(
        'roster.dart',
        "const knownDefects = <String>['H2 probes', 'H3 finalise'];\n",
      );

      // act
      final result = await run(['roster.dart', 'run.json']);

      // assert
      expect(result.exitCode, 1);
      expect(result.stdout, contains('  H3 finalise\n'));
    });

    test('exits 1 when the roster has no knownDefects list', () async {
      // arrange
      write('roster.dart', "const others = <String>['H2 probes'];\n");

      // act
      final result = await run(['roster.dart', 'run.json']);

      // assert
      expect(result.exitCode, 1);
      expect(result.stderr, contains('roster.dart has no knownDefects list'));
    });

    test('exits 64 with the usage line for an unpaired argument', () async {
      // arrange
      write('roster.dart', "const knownDefects = <String>['H2 probes'];\n");

      // act
      final result = await run(['roster.dart', 'run.json', 'roster.dart']);

      // assert
      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains(
          'Usage: dart run bluey_guards:known_defects '
          '<roster> <json file> [<roster> <json file>]...',
        ),
      );
    });
  });
}
