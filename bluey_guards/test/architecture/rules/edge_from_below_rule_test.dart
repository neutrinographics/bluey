import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _unplaced = 'lib/src/peer/p.dart';
const _rule = EdgeFromBelowRule(
  package: 'bluey',
  compositionRoots: {'lib/src/bluey.dart', 'lib/src/api/bluey.dart'},
);

List<String> found(Map<String, String> files) => entries(_rule, tree(files));

void main() {
  test('is named for its list', () {
    // act
    final name = _rule.name;

    // assert
    expect(name, 'edge from below');
  });

  test('flags unplaced code that names the edge', () {
    // arrange
    final files = {
      _unplaced: naming([
        '../api/connection/connection.dart',
        'package:bluey/src/api/bluey.dart',
      ]),
    };

    // act
    final violations = found(files);

    // assert
    expect(violations, [
      '$_unplaced -> lib/src/api/connection/connection.dart',
      '$_unplaced -> lib/src/api/bluey.dart',
    ]);
  });

  test('lets a composition root name the edge', () {
    // arrange
    final files = {
      'lib/src/bluey.dart': naming(['api/connection/connection.dart']),
    };

    // act
    final violations = found(files);

    // assert
    expect(violations, isEmpty);
  });

  test('leaves placed code to the layer rule', () {
    // arrange
    final files = {
      'lib/src/features/peer/application/p.dart': naming([
        '../../../api/connection/connection.dart',
      ]),
      'lib/src/shared/domain/s.dart': naming([
        '../../api/connection/connection.dart',
      ]),
    };

    // act
    final violations = found(files);

    // assert
    expect(violations, isEmpty);
  });

  test('lets the edge name the edge', () {
    // arrange
    final files = {
      'lib/src/api/peer/peer.dart': naming(['../connection/connection.dart']),
    };

    // act
    final violations = found(files);

    // assert
    expect(violations, isEmpty);
  });

  test('is not judged on what unplaced code names below the edge', () {
    // arrange
    final files = {
      _unplaced: naming([
        '../connection/bluey_connection.dart',
        '../features/connection/domain/x.dart',
      ]),
    };

    // act
    final violations = found(files);

    // assert
    expect(violations, isEmpty);
  });
}
