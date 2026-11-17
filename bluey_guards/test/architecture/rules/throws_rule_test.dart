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
        '$_placed -> line 3: throw Gone',
        '$_placed -> line 5: addError',
        '$_placed -> line 6: rethrow',
        '$_placed -> line 9: throw StateErrors',
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
        '$_placed -> line 2: completeError',
        '$_placed -> line 3: Future.error',
        '$_placed -> line 4: Stream.error',
        '$_placed -> line 5: throw e',
      ]);
    });
  });

  group('the kernel, the edge and unplaced code', () {
    test(
      'the kernel is held to it, and the edge and unplaced code are not',
      () {
        // arrange
        final files = tree({
          'lib/src/api/failure_translation.dart': 'Never f() => throw Gone();',
          'lib/src/connection/a.dart':
              'void f() {\n  try {} catch (e) {\n    rethrow;\n  }\n}\n',
          'lib/src/shared/domain/either.dart': 'void f() => throw Gone();',
        });

        // act
        final found = entries(_rule, files);

        // assert
        expect(found, [
          'lib/src/shared/domain/either.dart -> line 1: throw Gone',
        ]);
      },
    );
  });
}
