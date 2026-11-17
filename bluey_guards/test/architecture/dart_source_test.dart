import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

DartSource _parse(String content) =>
    DartSource.parse(SourceFile(path: 'lib/src/a.dart', content: content));

List<String> _raises(String content) => [
  for (final raise in _parse(content).raises) '${raise.line}: ${raise.what}',
];

void main() {
  group('uris', () {
    test('names every import, export and part, in source order', () {
      // act
      final source = _parse(
        "import 'dart:async';\nimport 'b.dart' as b show B;\n"
        "export 'c.dart' hide C;\npart 'd.dart';\n",
      );

      // assert
      expect(source.uris, ['dart:async', 'b.dart', 'c.dart', 'd.dart']);
      expect(source.exports, ['c.dart']);
    });

    test('names each alternative of a conditional import that spans lines', () {
      // act
      final source = _parse(
        "import 'stub.dart'\n    if (dart.library.io) 'io.dart'\n"
        "    if (dart.library.js_interop) 'web.dart';\n",
      );

      // assert
      expect(source.uris, ['stub.dart', 'io.dart', 'web.dart']);
    });

    test('ignores a directive inside a comment or a string', () {
      // act
      final source = _parse(
        "// import 'no.dart';\n/* export 'no.dart'; */\n"
        "const text = \"import 'no.dart';\";\n",
      );

      // assert
      expect(source.uris, isEmpty);
    });

    test(
      'still names the directives of a file that does not parse cleanly',
      () {
        // act
        final source = _parse("import 'a.dart';\nclass {");

        // assert
        expect(source.uris, ['a.dart']);
      },
    );
  });

  group('raises', () {
    test('names what each throw raises, with its line', () {
      // act
      final raises = _raises(
        "void f() {\n  throw StateError('x');\n}\n"
        "void g() => throw const Gone();\n"
        "void h() => throw ArgumentError.value(1);\n"
        "void i(Object e) => throw e;\n",
      );

      // assert
      expect(raises, [
        '2: throw StateError',
        '4: throw Gone',
        '5: throw ArgumentError.value',
        '6: throw e',
      ]);
    });

    test('names a rethrow and an addError call', () {
      // act
      final raises = _raises(
        "void f(dynamic sink) {\n  try {} catch (e) {\n"
        "    sink.addError(e);\n    rethrow;\n  }\n}\n",
      );

      // assert
      expect(raises, ['3: addError', '4: rethrow']);
    });

    test('names an addError tear-off', () {
      // act
      final raises = _raises(
        'void f(dynamic s, dynamic c) {\n'
        '  s.listen(null, onError: c.addError);\n'
        '}\n',
      );

      // assert
      expect(raises, ['2: addError']);
    });

    test('names an addError tear-off through a property, and a call once', () {
      // act
      final raises = _raises(
        'void f(dynamic s, dynamic c, Object e) {\n'
        '  s.listen(null, onError: c.sink.addError);\n'
        '  c.sink.addError(e);\n'
        '  c.addError(e);\n'
        '}\n',
      );

      // assert
      expect(raises, ['2: addError', '3: addError', '4: addError']);
    });

    test('names a bare addError tear-off inside a sink class, and a bare call '
        'once', () {
      // act
      final raises = _raises(
        'class Relay implements EventSink<int> {\n'
        '  void watch(Stream<int> s) => s.listen(null, onError: addError);\n'
        '  void fail(Object e) => addError(e);\n'
        '}\n',
      );

      // assert
      expect(raises, ['2: addError', '3: addError']);
    });

    test('names a completeError call and a completeError tear-off', () {
      // act
      final raises = _raises(
        'void f(Completer<void> c, Stream<int> s, Object e) {\n'
        '  c.completeError(e);\n'
        '  s.listen(null, onError: c.completeError);\n'
        '}\n',
      );

      // assert
      expect(raises, ['2: completeError', '3: completeError']);
    });

    test('names a Future.error and a Stream.error however each is written', () {
      // act
      final raises = _raises(
        'Future<int> f(Object e) => Future.error(e);\n'
        'Future<int> g(Object e) => Future<int>.error(e);\n'
        'Future<int> h(Object e) => new Future.error(e);\n'
        'Stream<int> i(Object e) => Stream.error(e);\n'
        'Stream<int> j(Object e) => async.Stream<int>.error(e);\n'
        'Future<int> k(Object e) => async.Future.error(e);\n',
      );

      // assert
      expect(raises, [
        '1: Future.error',
        '2: Future.error',
        '3: Future.error',
        '4: Stream.error',
        '5: Stream.error',
        '6: Future.error',
      ]);
    });

    test(
      'names Error.throwWithStackTrace as a throw of its first argument',
      () {
        // act
        final raises = _raises(
          'void f(Object e, StackTrace s) {\n'
          "  Error.throwWithStackTrace(StateError('x'), s);\n"
          '  Error.throwWithStackTrace(e, s);\n'
          '}\n',
        );

        // assert
        expect(raises, ['2: throw StateError', '3: throw e']);
      },
    );

    test('ignores an error member that is not a raise', () {
      // act
      final raises = _raises(
        'void f(dynamic r, Object e) {\n'
        '  r.error(e);\n'
        '  Failure.error(e);\n'
        '  final addError = r.handler;\n'
        '  r.on(addError: e);\n'
        '}\n',
      );

      // assert
      expect(raises, isEmpty);
    });

    test('ignores an addError named in a doc comment', () {
      // act
      final raises = _raises(
        '/// Forwards to [StreamController.addError] and [sink.addError].\n'
        'void f() {}\n'
        '\n'
        '/// See [Sink.addError], [Completer.completeError], [Future.error]\n'
        '/// and [Error.throwWithStackTrace].\n'
        'void g() {}\n',
      );

      // assert
      expect(raises, isEmpty);
    });

    test('ignores the words inside a comment or a string', () {
      // act
      final raises = _raises(
        "// throw StateError('x');\n"
        "const text = 'rethrow; throw x; addError(y)';\n",
      );

      // assert
      expect(raises, isEmpty);
    });
  });
}
