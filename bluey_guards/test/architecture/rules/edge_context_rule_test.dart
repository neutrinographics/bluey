import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _edge = 'lib/src/api/connection/a.dart';
const _root = 'lib/src/api/bluey.dart';
const _direct = 'lib/src/api/errors.dart';
const _rule = EdgeContextRule(
  package: 'bluey',
  compositionRoots: {'lib/src/bluey.dart', _root},
);

List<String> found(Map<String, String> files) => entries(_rule, tree(files));

void main() {
  test('is named for its list', () {
    // act
    final name = _rule.name;

    // assert
    expect(name, 'edge contexts');
  });

  group("an edge file of a context", () {
    test('names its own context', () {
      // arrange
      final files = {
        _edge: naming(['../../features/connection/domain/x.dart']),
      };

      // act
      final violations = found(files);

      // assert
      expect(violations, isEmpty);
    });

    test('may not name another context', () {
      // arrange
      final files = {
        _edge: naming([
          '../../features/gatt/domain/y.dart',
          'package:bluey/src/features/peer/application/z.dart',
        ]),
      };

      // act
      final violations = found(files);

      // assert
      expect(violations, [
        '$_edge -> lib/src/features/gatt/domain/y.dart',
        '$_edge -> lib/src/features/peer/application/z.dart',
      ]);
    });

    test("names another context's public interface", () {
      // arrange
      final files = {
        _edge: naming(['../gatt/z.dart']),
      };

      // act
      final violations = found(files);

      // assert
      expect(violations, isEmpty);
    });

    test('is not judged on the kernel or on unplaced code', () {
      // arrange
      final files = {
        _edge: naming([
          '../../shared/domain/either.dart',
          '../../peer/peer_connection.dart',
          'package:meta/meta.dart',
        ]),
      };

      // act
      final violations = found(files);

      // assert
      expect(violations, isEmpty);
    });
  });

  group('a file directly in the edge', () {
    test('may not name any context', () {
      // arrange
      final files = {
        _direct: naming(['../features/connection/domain/x.dart']),
      };

      // act
      final violations = found(files);

      // assert
      expect(violations, [
        '$_direct -> lib/src/features/connection/domain/x.dart',
      ]);
    });

    test('names any context when it is a composition root', () {
      // arrange
      final files = {
        _root: naming([
          '../features/connection/infrastructure/adapters/links.dart',
          '../features/gatt/domain/y.dart',
        ]),
      };

      // act
      final violations = found(files);

      // assert
      expect(violations, isEmpty);
    });
  });

  test('judges nothing outside the edge', () {
    // arrange
    final files = {
      'lib/src/features/connection/domain/x.dart': naming([
        '../../gatt/domain/y.dart',
      ]),
      'lib/src/peer/p.dart': naming(['../features/gatt/domain/y.dart']),
    };

    // act
    final violations = found(files);

    // assert
    expect(violations, isEmpty);
  });
}
