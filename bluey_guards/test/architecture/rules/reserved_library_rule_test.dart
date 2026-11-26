import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _reserved =
    'package:bluey_platform_interface/platform_implementation.dart';
const _rule = ReservedLibraryRule(libraries: {_reserved});

void main() {
  group('a reserved library', () {
    test('a file that names a reserved library is a violation wherever it '
        'sits', () {
      // arrange
      final files = tree({
        'lib/bluey.dart': "export '$_reserved';",
        'lib/src/api/bluey.dart': naming([_reserved]),
        'lib/src/features/connection/infrastructure/adapters/'
            'platform_links.dart': naming([_reserved]),
        'lib/src/connection/a.dart': naming([_reserved]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/bluey.dart -> $_reserved',
        'lib/src/api/bluey.dart -> $_reserved',
        'lib/src/connection/a.dart -> $_reserved',
        'lib/src/features/connection/infrastructure/adapters/'
            'platform_links.dart -> $_reserved',
      ]);
    });
  });

  group('a reserved folder', () {
    test('a file that names a library under a reserved folder is a '
        'violation', () {
      // arrange
      const folder = 'package:bluey_platform_interface/src/implementation/';
      const rule = ReservedLibraryRule(libraries: {_reserved, folder});
      final files = tree({
        'lib/src/connection/a.dart': naming(['${folder}device_streams.dart']),
        'lib/src/connection/b.dart': naming([
          'package:bluey_platform_interface/src/platform_interface.dart',
        ]),
      });

      // act
      final found = entries(rule, files);

      // assert
      expect(found, [
        'lib/src/connection/a.dart -> ${folder}device_streams.dart',
      ]);
    });
  });

  group('what the rule leaves alone', () {
    test("the package's other libraries are not reserved", () {
      // arrange
      final files = tree({
        'lib/src/connection/a.dart': naming([
          'package:bluey_platform_interface/bluey_platform_interface.dart',
          'dart:async',
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, isEmpty);
    });

    test('a library whose name only begins the same way is not reserved', () {
      // arrange
      final files = tree({
        'lib/src/connection/a.dart': naming([
          'package:bluey_platform_interface/platform_implementation_extras.dart',
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, isEmpty);
    });
  });
}
