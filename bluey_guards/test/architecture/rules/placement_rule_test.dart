import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

void main() {
  group('a package with files in and out of the target layout', () {
    test('lists every Dart file that is not in the target layout', () {
      // arrange
      final files = tree({
        'lib/bluey.dart': '',
        'lib/src/api/bluey.dart': '',
        'lib/src/bluey.dart': '',
        'lib/src/connection/a.dart': '',
        'lib/src/features/connection/domain/link.dart': '',
        'lib/src/shared/domain/analysis_options.yaml': '',
        'lib/src/shared/domain/either.dart': '',
        'lib/src/shared/exceptions.dart': '',
      });

      // act
      final found = entries(PlacementRule(), files);

      // assert
      expect(found, [
        'lib/src/bluey.dart -> unplaced',
        'lib/src/connection/a.dart -> unplaced',
        'lib/src/shared/exceptions.dart -> unplaced',
      ]);
    });

    test('is named placement', () {
      // act
      final name = PlacementRule().name;

      // assert
      expect(name, 'placement');
    });
  });
}
