import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _fixture = 'test/architecture/fixtures/held_package.dart';

/// Each test the fixture registered, by its name, with how it finished and
/// the error it reported, if any.
typedef _Outcome = ({String result, String error});

Future<Map<String, _Outcome>> _runFixture({String? anchor}) async {
  final run = await Process.run(
    Platform.resolvedExecutable,
    ['test', _fixture, '--reporter', 'json'],
    environment: {if (anchor != null) 'ANCHOR': anchor},
  );
  final names = <int, String>{};
  final errors = <int, String>{};
  final outcomes = <String, _Outcome>{};
  for (final line in (run.stdout as String).split('\n')) {
    if (!line.startsWith('{')) continue;
    switch (jsonDecode(line)) {
      case {
        'type': 'testStart',
        'test': {'id': final int id, 'name': final String name},
      }:
        names[id] = name;
      case {
        'type': 'error',
        'testID': final int id,
        'error': final String error,
      }:
        errors[id] = error;
      case {
        'type': 'testDone',
        'testID': final int id,
        'result': final String result,
      }:
        if (names[id] case final name?) {
          outcomes[name] = (result: result, error: errors[id] ?? '');
        }
    }
  }
  return outcomes;
}

void main() {
  group('holdToKnownViolations', () {
    test('passes the anchor test when the tree holds the anchor', () async {
      // act
      final outcomes = await _runFixture();

      // assert
      expect(
        outcomes['the architecture of held reads the package from its root']
            ?.result,
        'success',
      );
    });

    test('fails the anchor test when the tree lacks the anchor', () async {
      // act
      final outcomes = await _runFixture(anchor: 'lib/elsewhere.dart');

      // assert
      final anchored =
          outcomes['the architecture of held reads the package from its root'];
      expect(anchored?.result, 'failure');
      expect(anchored?.error, contains('lib/elsewhere.dart'));
    });

    test('passes a rule whose list is what the rule finds', () async {
      // act
      final outcomes = await _runFixture();

      // assert
      expect(
        outcomes['the architecture of held public exports: what the rule '
                'finds is exactly what is known']
            ?.result,
        'success',
      );
    });

    test('fails a rule whose list differs, in the words of the rule', () async {
      // act
      final outcomes = await _runFixture();

      // assert
      final sized =
          outcomes['the architecture of held size of .dart files: what the '
              'rule finds is exactly what is known'];
      expect(sized?.result, 'failure');
      expect(
        sized?.error,
        contains(
          'lib/held.dart shrank from 5 to 4 lines: lower its entry to 4',
        ),
      );
    });
  });
}
