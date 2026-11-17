import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _rule = PlacementRule(contexts: {'connection', 'discovery'});

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
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/bluey.dart -> unplaced',
        'lib/src/connection/a.dart -> unplaced',
        'lib/src/shared/exceptions.dart -> unplaced',
      ]);
    });

    test('is named placement', () {
      // act
      final name = _rule.name;

      // assert
      expect(name, 'placement');
    });
  });

  group('a feature folder that is not one of the contexts', () {
    test('lists each file in it, naming the folder', () {
      // arrange
      final files = tree({
        'lib/src/features/connectoin/domain/link.dart': '',
        'lib/src/features/discovery/domain/scan.dart': '',
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/features/connectoin/domain/link.dart -> '
            'features/connectoin is not a context',
      ]);
    });
  });
}
