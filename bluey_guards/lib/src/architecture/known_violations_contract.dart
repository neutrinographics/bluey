import 'package:test/test.dart';

import 'architecture_rule.dart';
import 'ratchet.dart';
import 'source_tree.dart';

/// Registers the tests that hold [package]'s [tree] to each of [rules], each
/// rule against the list of what it is known to find, so every package is
/// judged by the same tests and fails with the same words.
///
/// The first test asks that [tree] holds [anchor], a file every checkout of
/// the package has: a test run from another folder reads an empty tree, and
/// over an empty tree an empty list would pass.
void holdToKnownViolations(
  String package, {
  required SourceTree tree,
  required String anchor,
  required Map<ArchitectureRule, List<String>> rules,
}) {
  group('the architecture of $package', () {
    test('reads the package from its root', () {
      // act
      final file = tree.file(anchor);

      // assert
      expect(
        file,
        isNotNull,
        reason: 'No $anchor: run the test from the root of $package.',
      );
    });

    for (final MapEntry(key: rule, value: known) in rules.entries) {
      test('${rule.name}: what the rule finds is exactly what is known', () {
        // act
        final verdict = ratchet(
          found: rule.check(tree).map((violation) => violation.entry),
          known: known,
        );

        // assert
        expect(
          verdict.holds,
          isTrue,
          reason: verdict.describe(
            rule.name,
            change: rule is MeasuringRule ? rule.change : null,
          ),
        );
      });
    }
  });
}
