import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

Dependency _resolve(String uri) => Dependency.resolve(
  from: 'lib/src/connection/bluey_connection.dart',
  uri: uri,
  package: 'bluey',
);

void main() {
  group('resolve', () {
    test('resolves a relative URI against the file that names it', () {
      // act
      final dependency = _resolve('../discovery/device.dart');

      // assert
      expect(
        dependency,
        isA<Internal>().having(
          (d) => d.path,
          'path',
          'lib/src/discovery/device.dart',
        ),
      );
    });

    test('resolves a URI of its own package', () {
      // act
      final dependency = _resolve('package:bluey/src/shared/uuid.dart');

      // assert
      expect(
        dependency,
        isA<Internal>().having(
          (d) => d.path,
          'path',
          'lib/src/shared/uuid.dart',
        ),
      );
    });

    test('keeps another package and an SDK library external', () {
      // act
      final flutter = _resolve('package:flutter/services.dart');
      final sdk = _resolve('dart:async');

      // assert
      expect(flutter, isA<External>());
      expect(sdk, isA<External>());
    });
  });

  group('isWithin', () {
    test('holds a library of the package, and the exact library', () {
      // arrange
      final services = _resolve('package:flutter/services.dart') as External;

      // act
      final inPackage = services.isWithin('package:flutter');
      final exact = services.isWithin('package:flutter/services.dart');
      final sibling = services.isWithin('package:flutter/widgets.dart');

      // assert
      expect(inPackage, isTrue);
      expect(exact, isTrue);
      expect(sibling, isFalse);
    });

    test('does not confuse a package with one whose name it begins', () {
      // arrange
      final test =
          _resolve('package:flutter_test/flutter_test.dart') as External;

      // act
      final within = test.isWithin('package:flutter');

      // assert
      expect(within, isFalse);
    });
  });
}
