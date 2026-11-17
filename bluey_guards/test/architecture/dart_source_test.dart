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
      // arrange
      const content = '''
import 'dart:async';
import 'b.dart' as b show B;
export 'c.dart' hide C;
part 'd.dart';
''';

      // act
      final source = _parse(content);

      // assert
      expect(source.uris, ['dart:async', 'b.dart', 'c.dart', 'd.dart']);
      expect(source.exports, ['c.dart']);
    });

    test('names each alternative of a conditional import that spans lines', () {
      // arrange
      const content = '''
import 'stub.dart'
    if (dart.library.io) 'io.dart'
    if (dart.library.js_interop) 'web.dart';
''';

      // act
      final source = _parse(content);

      // assert
      expect(source.uris, ['stub.dart', 'io.dart', 'web.dart']);
    });

    test('ignores a directive inside a comment or a string', () {
      // arrange
      const content = '''
// import 'no.dart';
/* export 'no.dart'; */
const text = "import 'no.dart';";
''';

      // act
      final source = _parse(content);

      // assert
      expect(source.uris, isEmpty);
    });

    test(
      'still names the directives of a file that does not parse cleanly',
      () {
        // arrange
        const content = '''
import 'a.dart';
class {''';

        // act
        final source = _parse(content);

        // assert
        expect(source.uris, ['a.dart']);
      },
    );
  });

  group('raises', () {
    test('names what each throw raises, with its line', () {
      // arrange
      const content = '''
void f() {
  throw StateError('x');
}
void g() => throw const Gone();
void h() => throw ArgumentError.value(1);
void i(Object e) => throw e;
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, [
        '2: throw StateError',
        '4: throw Gone',
        '5: throw ArgumentError.value',
        '6: throw e',
      ]);
    });

    test('names what a throw in parentheses raises', () {
      // arrange
      const content = '''
void f() => throw (StateError('x'));
void g() => throw ((const Gone()));
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, ['1: throw StateError', '2: throw Gone']);
    });

    test('names a rethrow and an addError call', () {
      // arrange
      const content = '''
void f(dynamic sink) {
  try {} catch (e) {
    sink.addError(e);
    rethrow;
  }
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, ['3: addError', '4: rethrow']);
    });

    test('names an addError tear-off', () {
      // arrange
      const content = '''
void f(dynamic s, dynamic c) {
  s.listen(null, onError: c.addError);
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, ['2: addError']);
    });

    test('names an addError tear-off through a property, and a call once', () {
      // arrange
      const content = '''
void f(dynamic s, dynamic c, Object e) {
  s.listen(null, onError: c.sink.addError);
  c.sink.addError(e);
  c.addError(e);
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, ['2: addError', '3: addError', '4: addError']);
    });

    test('names a bare addError tear-off inside a sink class, and a bare call '
        'once', () {
      // arrange
      const content = '''
class Relay implements EventSink<int> {
  void watch(Stream<int> s) => s.listen(null, onError: addError);
  void fail(Object e) => addError(e);
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, ['2: addError', '3: addError']);
    });

    test('names a completeError call and a completeError tear-off', () {
      // arrange
      const content = '''
void f(Completer<void> c, Stream<int> s, Object e) {
  c.completeError(e);
  s.listen(null, onError: c.completeError);
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, ['2: completeError', '3: completeError']);
    });

    test('names a Future.error and a Stream.error however each is called', () {
      // arrange
      const content = '''
Future<int> f(Object e) => Future.error(e);
Future<int> g(Object e) => Future<int>.error(e);
Future<int> h(Object e) => new Future.error(e);
Stream<int> i(Object e) => Stream.error(e);
Stream<int> j(Object e) => async.Stream<int>.error(e);
Future<int> k(Object e) => async.Future.error(e);
''';

      // act
      final raises = _raises(content);

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

    test('names a Future.error and a Stream.error tear-off', () {
      // arrange
      const content = '''
void f(Future<int> a, Stream<int> s) {
  a.then((_) {}, onError: Future.error);
  s.handleError(Stream.error);
  a.catchError(async.Future.error);
  a.catchError(Future<int>.error);
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, [
        '2: Future.error',
        '3: Stream.error',
        '4: Future.error',
        '5: Future.error',
      ]);
    });

    test(
      'names Error.throwWithStackTrace as a throw of its first argument',
      () {
        // arrange
        const content = '''
void f(Object e, StackTrace s) {
  Error.throwWithStackTrace(StateError('x'), s);
  Error.throwWithStackTrace(e, s);
}
''';

        // act
        final raises = _raises(content);

        // assert
        expect(raises, ['2: throw StateError', '3: throw e']);
      },
    );

    test('ignores an error member that is not a raise', () {
      // arrange
      const content = '''
void f(dynamic r, Object e) {
  r.error(e);
  Failure.error(e);
  final handler = Failure.error;
  final addError = r.handler;
  r.on(addError: e);
}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, isEmpty);
    });

    test('ignores an addError named in a doc comment', () {
      // arrange
      const content = '''
/// Forwards to [StreamController.addError] and [sink.addError].
void f() {}

/// See [Sink.addError], [Completer.completeError], [Future.error]
/// and [Error.throwWithStackTrace].
void g() {}
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, isEmpty);
    });

    test('ignores the words inside a comment or a string', () {
      // arrange
      const content = '''
// throw StateError('x');
const text = 'rethrow; throw x; addError(y)';
''';

      // act
      final raises = _raises(content);

      // assert
      expect(raises, isEmpty);
    });
  });
}
