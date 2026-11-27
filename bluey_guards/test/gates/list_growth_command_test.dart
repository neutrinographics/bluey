import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _listFile = 'pkg/test/architecture/known_violations.dart';
const _usage = 'Usage: list_growth_entry <base> <list file>...';

String _lists(List<String> unplaced) =>
    'const unplaced = <String>[\n'
    '${[for (final entry in unplaced) "  '$entry',\n"].join()}'
    '];\n';

String _boundaries(String target) =>
    "const boundaries = <String>['lib/src/peer/peer.dart -> $target'];\n";

void main() {
  group('the list_growth command', () {
    late Directory compiled;
    late String command;
    late Directory repository;

    Future<ProcessResult> git(List<String> arguments) =>
        Process.run('git', arguments, workingDirectory: repository.path);

    Future<ProcessResult> run(List<String> arguments, {String? from}) =>
        Process.run(Platform.resolvedExecutable, [
          command,
          ...arguments,
        ], workingDirectory: from ?? repository.path);

    void write(String path, String content) {
      File(p.join(repository.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    Future<void> commit(String message) async {
      await git(['add', '-A']);
      await git(['commit', '-q', '-m', message]);
    }

    setUpAll(() async {
      compiled = Directory.systemTemp.createTempSync('list_growth_command_');
      command = '${compiled.path}/list_growth.dill';
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'test/gates/support/list_growth_entry.dart',
        '-o',
        command,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');
    });

    tearDownAll(() => compiled.deleteSync(recursive: true));

    setUp(() async {
      repository = Directory.systemTemp.createTempSync('list_growth_');
      await git(['init', '-q', '-b', 'main']);
      await git(['config', 'user.email', 'guard@example.com']);
      await git(['config', 'user.name', 'Guard']);
      write(_listFile, _lists(['lib/a.dart -> unplaced']));
      await commit('base');
      await git(['checkout', '-q', '-b', 'change']);
    });

    tearDown(() => repository.deleteSync(recursive: true));

    test('exits 0 when a list shrank since the merge base', () async {
      // arrange
      write(_listFile, _lists([]));
      await commit('fix a');

      // act
      final result = await run(['main', _listFile]);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, '$_listFile: no list grew.\n');
    });

    test('exits 1 naming an entry added since the merge base', () async {
      // arrange
      write(
        _listFile,
        _lists(['lib/a.dart -> unplaced', 'lib/b.dart -> unplaced']),
      );

      // act
      final result = await run(['main', _listFile]);

      // assert
      expect(result.exitCode, 1);
      expect(result.stdout, contains('  unplaced: lib/b.dart -> unplaced\n'));
    });

    test(
      'compares with the merge base, not with the base as it is now',
      () async {
        // arrange
        await git(['checkout', '-q', 'main']);
        write(_listFile, _lists([]));
        await commit('main fixes a');
        await git(['checkout', '-q', 'change']);

        // act
        final result = await run(['main', _listFile]);

        // assert
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      },
    );

    test('reads a path relative to the folder it runs in', () async {
      // arrange
      write('pkg/pubspec.yaml', 'name: pkg\n');
      write(
        _listFile,
        _lists(['lib/a.dart -> unplaced', 'lib/c.dart -> unplaced']),
      );

      // act
      final result = await run([
        'main',
        'test/architecture/known_violations.dart',
      ], from: p.join(repository.path, 'pkg'));

      // assert
      expect(result.exitCode, 1);
      expect(result.stdout, contains('  unplaced: lib/c.dart -> unplaced\n'));
    });

    test('holds a list file the merge base did not have', () async {
      // arrange
      write('other/known_violations.dart', _lists(['lib/x.dart -> unplaced']));

      // act
      final result = await run(['main', 'other/known_violations.dart']);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('not at the base'));
    });

    test('holds every list entry by entry', () async {
      // arrange
      await git(['checkout', '-q', 'main']);
      write(_listFile, _boundaries('lib/src/connection/a.dart'));
      await commit('main holds a boundary');
      await git(['checkout', '-q', 'change']);
      await git(['merge', '-q', 'main']);
      write(
        _listFile,
        _boundaries('lib/src/features/connection/domain/a.dart'),
      );

      // act
      final result = await run(['main', _listFile]);

      // assert
      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains(
          '  boundaries: lib/src/peer/peer.dart -> '
          'lib/src/features/connection/domain/a.dart\n',
        ),
      );
    });

    test(
      'exits 1 naming the file and why when a list file cannot be read',
      () async {
        // arrange
        write(
          _listFile,
          "const unplaced = <String>['lib/a.dart -> unplaced'].toList();\n",
        );

        // act
        final result = await run(['main', _listFile]);

        // assert
        expect(result.exitCode, 1);
        expect(result.stderr, contains('$_listFile: '));
        expect(
          result.stderr,
          contains('is not a list literal of plain strings'),
        );
      },
    );

    test('exits 1 when the base held a list file it cannot read', () async {
      // arrange
      await git(['checkout', '-q', 'main']);
      write(_listFile, 'List<String> get unplaced => [];\n');
      await commit('main holds a getter');
      await git(['checkout', '-q', 'change']);
      await git(['merge', '-q', 'main']);

      // act
      final result = await run(['main', _listFile]);

      // assert
      expect(result.exitCode, 1);
      expect(result.stderr, contains('$_listFile at the base: '));
    });

    test('exits 1 when the base cannot be found', () async {
      // act
      final result = await run(['no-such-ref', _listFile]);

      // assert
      expect(result.exitCode, 1);
      expect(result.stderr, contains('no-such-ref'));
    });

    test('holds a list the base lacks when a flag states it', () async {
      // arrange
      write(
        _listFile,
        '${_lists(['lib/a.dart -> unplaced'])}'
        "const fresh = <String>['lib/src/peer/p.dart -> lib/src/api/c.dart'];\n",
      );

      // act
      final result = await run(['main', _listFile, '--first-statement=fresh']);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('fresh: not at the base'));
    });

    test('prints a note when the base already has the flagged list', () async {
      // act
      final result = await run([
        'main',
        _listFile,
        '--first-statement=unplaced',
      ]);

      // assert
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
        result.stdout,
        contains(
          '--first-statement=unplaced no longer applies: the base has this '
          'list; remove the flag',
        ),
      );
    });

    test('exits 1 naming a flag no list file at the head declares', () async {
      // act
      final result = await run([
        'main',
        '--first-statement=missing',
        _listFile,
      ]);

      // assert
      expect(result.exitCode, 1);
      expect(result.stderr, contains('--first-statement=missing'));
    });

    test('exits 64 with the usage line when no list file is named', () async {
      // act
      final result = await run(['main']);

      // assert
      expect(result.exitCode, 64);
      expect(result.stderr, contains(_usage));
    });
  });

  test('bluey_guards ships no list_growth command, since a command that '
      'knows no rule judges every entry by its text and fails a rewritten '
      'entry that holds', () {
    // act
    final shipped = File('bin/list_growth.dart').existsSync();

    // assert
    expect(shipped, isFalse);
  });
}
