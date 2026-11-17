import 'package:bluey_guards/architecture.dart';
import 'package:bluey_guards/gates.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bluey_architecture.dart';

const _path = 'test/architecture/known_violations.dart';

/// Bluey's lists as the file holds them today, with [list] changed by
/// [change], so each case judges a change to the real lists by the real
/// rules' weights, as the Lists only shrink job does.
ListGrowth _growthAfter(
  String list,
  List<String> Function(List<String> entries) change,
) {
  final base = readKnownViolations();
  return ListGrowth.between(
    path: _path,
    base: base,
    head: {...base, list: change(base[list] ?? const [])},
    weights: weightsOf(blueyRules),
  );
}

void main() {
  group("Bluey's lists judged by its rules' weights", () {
    test('a boundaries entry whose target moved to its place in the target '
        'layout holds', () {
      // act
      final growth = _growthAfter(
        'boundaries',
        (entries) => [
          for (final entry in entries)
            entry ==
                    'lib/src/gatt_client/gatt.dart -> '
                        'lib/src/connection/value_objects/attribute_handle.dart'
                ? 'lib/src/gatt_client/gatt.dart -> '
                    'lib/src/features/connection/domain/attribute_handle.dart'
                : entry,
        ],
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
    });

    test('a boundaries entry into a context its source did not depend on '
        'grows the list', () {
      // act
      final growth = _growthAfter(
        'boundaries',
        (entries) => [
          ...entries,
          'lib/src/discovery/bluey_scanner.dart -> lib/src/peer/server_id.dart',
        ],
      );

      // assert
      expect(growth.added, [
        'boundaries: lib/src/discovery/bluey_scanner.dart -> '
            'lib/src/peer/server_id.dart',
      ]);
    });

    test('a second boundaries entry into a context its source depended on '
        'grows the list', () {
      // act
      final growth = _growthAfter(
        'boundaries',
        (entries) => [
          ...entries,
          'lib/src/discovery/bluey_scanner.dart -> '
              'lib/src/features/platform/domain/capabilities.dart',
        ],
      );

      // assert
      expect(growth.raised, [
        'boundaries: lib/src/discovery/bluey_scanner.dart into platform, 1 at '
            'the base and 2 at the head: '
            'lib/src/discovery/bluey_scanner.dart -> '
            'lib/src/features/platform/domain/capabilities.dart',
      ]);
    });

    test('a boundaries entry whose target moved into shared is deleted, and '
        'the list holds', () {
      // act
      final growth = _growthAfter(
        'boundaries',
        (entries) => [
          for (final entry in entries)
            if (entry !=
                'lib/src/gatt_server/lifecycle_server.dart -> '
                    'lib/src/peer/server_id.dart')
              entry,
        ],
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
    });

    test('an oversized entry lowered to its file\'s new length holds', () {
      // act
      final growth = _growthAfter(
        'oversized',
        (entries) => [
          for (final entry in entries)
            entry == 'lib/src/bluey.dart -> 1002 lines'
                ? 'lib/src/bluey.dart -> 990 lines'
                : entry,
        ],
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
    });
  });
}
