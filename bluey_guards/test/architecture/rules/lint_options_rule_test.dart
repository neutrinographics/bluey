import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _both =
    'linter:\n  rules:\n    - unawaited_futures\n    - discarded_futures\n';
final _rule = LintOptionsRule(
  roots: const ['lib/src/shared/domain', 'lib/src/features'],
  lints: const {'unawaited_futures', 'discarded_futures'},
);

void main() {
  group('a root that holds Dart', () {
    test('a root that holds Dart needs its options file', () {
      // arrange
      final files = tree({'lib/src/shared/domain/either.dart': ''});

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, ['lib/src/shared/domain -> no analysis_options.yaml']);
    });

    test(
      'the options file must turn on each lint, and a commented line does not',
      () {
        // arrange
        final files = tree({
          'lib/src/features/analysis_options.yaml':
              'linter:\n  rules:\n    - unawaited_futures\n'
              '    # - discarded_futures\n',
          'lib/src/features/connection/domain/link.dart': '',
        });

        // act
        final found = entries(_rule, files);

        // assert
        expect(found, [
          'lib/src/features/analysis_options.yaml -> '
              'does not turn on discarded_futures',
        ]);
      },
    );
  });

  group('roots that hold', () {
    test(
      'a root with both lints holds, and a root with no Dart needs nothing',
      () {
        // arrange
        final files = tree({
          'lib/src/shared/domain/analysis_options.yaml': _both,
          'lib/src/shared/domain/either.dart': '',
          'lib/src/shared/exceptions.dart': '',
        });

        // act
        final found = entries(_rule, files);

        // assert
        expect(found, isEmpty);
      },
    );
  });
  group('every options file under a root', () {
    test('a deeper options file must turn on each lint itself', () {
      // arrange
      final files = tree({
        'lib/src/features/analysis_options.yaml': _both,
        'lib/src/features/connection/analysis_options.yaml': '''
linter:
  rules:
    - unawaited_futures
''',
        'lib/src/features/connection/domain/link.dart': '',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/features/connection/analysis_options.yaml -> '
            'does not turn on discarded_futures',
      ]);
    });

    test('no options file may set a lint to ignore under analyzer errors', () {
      // arrange
      final files = tree({
        'lib/src/features/analysis_options.yaml': '''
analyzer:
  errors:
    unawaited_futures: ignore
    discarded_futures: warning
linter:
  rules:
    - unawaited_futures
    - discarded_futures
''',
        'lib/src/features/connection/domain/link.dart': '',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/features/analysis_options.yaml -> '
            'sets unawaited_futures to ignore',
      ]);
    });

    test('reads rules written as a map, true turning a lint on', () {
      // arrange
      final files = tree({
        'lib/src/features/analysis_options.yaml': '''
linter:
  rules:
    unawaited_futures: true
    discarded_futures: false
''',
        'lib/src/features/connection/domain/link.dart': '',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/features/analysis_options.yaml -> '
            'does not turn on discarded_futures',
      ]);
    });

    test('an options file that is not YAML turns nothing on', () {
      // arrange
      final files = tree({
        'lib/src/features/analysis_options.yaml': 'linter: [rules\n',
        'lib/src/features/connection/domain/link.dart': '',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/features/analysis_options.yaml -> does not parse as YAML',
      ]);
    });
  });
}
