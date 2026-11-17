import 'package:test/test.dart';

import 'architecture_rule.dart';
import 'ratchet.dart';
import 'source_tree.dart';

/// Registers the tests that hold [package]'s [tree] to each of [rules], each
/// rule against the list of what it is known to find, so every package is
/// judged by the same tests and fails with the same words.
///
/// [rules] and [lists] are keyed by the list's name, and [lists] is the
/// package's list file as read, so a rule is held to the list the file
/// declares and to nothing built elsewhere; one test asks that each list has
/// exactly one rule and each rule one list, so a list can neither be left
/// unjudged nor a rule go unheld.
///
/// The first test asks that [tree] holds [anchor], a file every checkout of
/// the package has: a test run from another folder reads an empty tree, and
/// over an empty tree an empty list would pass.
void holdToKnownViolations(
  String package, {
  required SourceTree tree,
  required String anchor,
  required Map<String, ArchitectureRule> rules,
  required Map<String, List<String>> lists,
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

    test('every list in the list file is held by one rule, and every rule by '
        'one list', () {
      // act
      final unheld = lists.keys.where((list) => !rules.containsKey(list));
      final listless = rules.keys.where((list) => !lists.containsKey(list));

      // assert
      expect(
        [...unheld, ...listless],
        isEmpty,
        reason:
            'Lists no rule holds: ${unheld.join(', ')}. Rules whose list '
            'the file lacks: ${listless.join(', ')}.',
      );
    });

    for (final MapEntry(key: list, value: rule) in rules.entries) {
      test('${rule.name}: what the rule finds is exactly what is known', () {
        // act
        final verdict = ratchet(
          found: rule.check(tree).map((violation) => violation.entry),
          known: lists[list] ?? const [],
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
