import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

void main() {
  group('a public library and what it exports', () {
    test('a public library exports from its own lib/src alone', () {
      // arrange
      final files = tree({
        'lib/bluey.dart':
            "export 'src/api/bluey.dart';\n"
            "export 'package:bluey/src/shared/uuid.dart';\n"
            "export 'package:bluey_platform_interface/"
            "bluey_platform_interface.dart' show Capabilities;\n"
            "export 'testing.dart';\n",
        'lib/src/a.dart': "export 'package:meta/meta.dart';",
      });

      // act
      final found = entries(PublicExportsRule(package: 'bluey'), files);

      // assert
      expect(found, [
        'lib/bluey.dart -> '
            'package:bluey_platform_interface/bluey_platform_interface.dart',
        'lib/bluey.dart -> testing.dart',
      ]);
    });
  });
}
