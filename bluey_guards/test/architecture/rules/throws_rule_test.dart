import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _placed = 'lib/src/features/connection/application/connect_device.dart';
final _rule = ThrowsRule(
  programmingErrors: const {
    'StateError',
    'ArgumentError',
    'UnimplementedError',
  },
);

void main() {
  group('placed code', () {
    test('placed code may throw a programming error', () {
      // arrange
      final files = tree({
        _placed:
            "void f() => throw StateError('x');\n"
            'void g() => throw ArgumentError.value(1);\n'
            'void h() => throw UnimplementedError();\n',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, isEmpty);
    });

    test('placed code may not throw a failure, rethrow or add an error to a '
        'stream', () {
      // arrange
      final files = tree({
        _placed:
            'void f(dynamic sink) {\n  try {\n    throw Gone();\n'
            '  } catch (e) {\n'
            '    sink.addError(e);\n    rethrow;\n  }\n}\n'
            'void g() => throw StateErrors();\n',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        '$_placed -> throw Gone, 1 time',
        '$_placed -> addError, 1 time',
        '$_placed -> rethrow, 1 time',
        '$_placed -> throw StateErrors, 1 time',
      ]);
    });

    test('placed code may not complete, create or rethrow an error with its '
        'stack trace, unless it is a programming error', () {
      // arrange
      final files = tree({
        _placed:
            'void f(Completer<void> c, Object e, StackTrace s) {\n'
            '  c.completeError(e);\n'
            '  Future<void>.error(e);\n'
            '  Stream<int>.error(e);\n'
            '  Error.throwWithStackTrace(e, s);\n'
            "  Error.throwWithStackTrace(StateError('x'), s);\n"
            '}\n',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        '$_placed -> completeError, 1 time',
        '$_placed -> Future.error, 1 time',
        '$_placed -> Stream.error, 1 time',
        '$_placed -> throw e, 1 time',
      ]);
    });
  });

  group('the kernel, the edge and unplaced code', () {
    test(
      'the kernel is held to it, and the edge and unplaced code are not',
      () {
        // arrange
        final files = tree({
          'lib/src/api/connection/connection_failure_translation.dart':
              'Never f() => throw Gone();',
          'lib/src/connection/a.dart':
              'void f() {\n  try {} catch (e) {\n    rethrow;\n  }\n}\n',
          'lib/src/shared/domain/either.dart': 'void f() => throw Gone();',
        });

        // act
        final found = entries(_rule, files);

        // assert
        expect(found, [
          'lib/src/shared/domain/either.dart -> throw Gone, 1 time',
        ]);
      },
    );
  });

  group('one entry per file and raise', () {
    test('counts each raise of a file, in the order it first appears, and no '
        'line', () {
      // arrange
      final files = tree({
        _placed:
            'void f() => throw Gone();\n'
            'void g(dynamic s, Object e) => s.addError(e);\n'
            'void h() => throw Gone();\n'
            'void i() => throw Gone();\n',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        '$_placed -> throw Gone, 3 times',
        '$_placed -> addError, 1 time',
      ]);
    });
  });

  group('the debt an entry records', () {
    test('is its file and raise, weighed by the count', () {
      // act
      final debt = _rule.weigh('$_placed -> throw Gone, 3 times');

      // assert
      expect(debt, (debt: '$_placed -> throw Gone', amount: 3));
    });

    for (final miscounted in ['1 times', '2 time', '0 times']) {
      test('is the entry itself, once, for a count written as $miscounted, '
          'which the rule never writes', () {
        // act
        final debt = _rule.weigh('$_placed -> throw Gone, $miscounted');

        // assert
        expect(debt, (debt: '$_placed -> throw Gone, $miscounted', amount: 1));
      });
    }

    test('is the entry itself, once, for an entry of another shape', () {
      // act
      final debt = _rule.weigh('$_placed -> line 3: throw Gone');

      // assert
      expect(debt, (debt: '$_placed -> line 3: throw Gone', amount: 1));
    });
  });

  group('a known entry and a found entry of one file and raise', () {
    test('tells a raise that grew to go, never to raise its entry', () {
      // act
      final change = _rule.change(
        known: '$_placed -> throw Gone, 2 times',
        found: '$_placed -> throw Gone, 3 times',
      );

      // assert
      expect(
        change,
        '$_placed raises throw Gone 3 times, up from 2: answer the new one as '
        'a value; never raise the entry',
      );
    });

    test('tells a raise that fell to lower its entry', () {
      // act
      final change = _rule.change(
        known: '$_placed -> throw Gone, 2 times',
        found: '$_placed -> throw Gone, 1 time',
      );

      // assert
      expect(
        change,
        '$_placed raises throw Gone 1 time, down from 2: lower its entry to '
        '1 time',
      );
    });

    test('is no change for a known entry whose count is miscounted', () {
      // act
      final change = _rule.change(
        known: '$_placed -> throw Gone, 1 times',
        found: '$_placed -> throw Gone, 1 time',
      );

      // assert
      expect(change, isNull);
    });

    test('is no change for two raises of one file', () {
      // act
      final change = _rule.change(
        known: '$_placed -> throw Gone, 2 times',
        found: '$_placed -> rethrow, 2 times',
      );

      // assert
      expect(change, isNull);
    });
  });
}
