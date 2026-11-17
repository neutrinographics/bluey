import 'package:bluey_guards/architecture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bluey_architecture.dart';

void main() {
  final tree = readBluey();

  group('the architecture of bluey', () {
    test('reads the package from its root', () {
      // act
      final library = tree.file('lib/bluey.dart');

      // assert
      expect(library, isNotNull);
    });

    for (final MapEntry(key: rule, value: known)
        in rulesAndKnownViolations.entries) {
      test('${rule.name}: what the rule finds is exactly what is known', () {
        // act
        final verdict = Ratchet.judge(
          found: rule.check(tree).map((violation) => violation.entry),
          known: known,
        );

        // assert
        expect(verdict.holds, isTrue, reason: verdict.describe(rule.name));
      });
    }
  });
}
