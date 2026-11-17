import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _flutter = 'package:flutter/services.dart';
const _platform =
    'package:bluey_platform_interface/bluey_platform_interface.dart';
final _rule = FrameworkRule(
  package: 'bluey',
  frameworks: const {'package:flutter', 'package:bluey_platform_interface'},
  compositionRoots: const {'lib/src/api/bluey.dart', 'lib/src/bluey.dart'},
);

void main() {
  group('a framework named under lib/src', () {
    test('a framework named outside infrastructure is a violation', () {
      // arrange
      final files = tree({
        'lib/src/api/connection/connection.dart': naming([_flutter]),
        'lib/src/features/connection/application/connect_device.dart': naming([
          _platform,
        ]),
        'lib/src/features/connection/domain/link.dart': naming([_platform]),
        'lib/src/shared/error_translation.dart': naming([_flutter, _platform]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/api/connection/connection.dart -> $_flutter',
        'lib/src/features/connection/application/connect_device.dart -> '
            '$_platform',
        'lib/src/features/connection/domain/link.dart -> $_platform',
        'lib/src/shared/error_translation.dart -> $_flutter',
        'lib/src/shared/error_translation.dart -> $_platform',
      ]);
    });

    test('infrastructure and the composition roots may name a framework', () {
      // arrange
      final files = tree({
        'lib/src/api/bluey.dart': naming([_platform]),
        'lib/src/bluey.dart': naming([_platform]),
        'lib/src/features/connection/infrastructure/adapters/'
            'platform_links.dart': naming([_flutter, _platform]),
        'lib/src/shared/infrastructure/platform_errors.dart': naming([
          _flutter,
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, isEmpty);
    });
  });

  group('what the rule leaves alone', () {
    test("other packages and the public library are not this rule's", () {
      // arrange
      final files = tree({
        'lib/bluey.dart': "export '$_platform';",
        'lib/src/connection/a.dart': naming([
          'dart:async',
          'package:meta/meta.dart',
          'package:flutter_test/flutter_test.dart',
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, isEmpty);
    });
  });
}
