import 'dart:io';

import 'package:bluey_guards/architecture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_violations.dart';

final Map<ArchitectureRule, List<String>> _rulesAndKnownViolations = {
  SizeRule(limit: 300, extension: '.dart'): oversizedDart,
};

void main() {
  final tree = SourceTree.read(
    Directory.current,
    under: const ['lib'],
    extensions: const {'.dart'},
  );

  group('the size of bluey_platform_interface\'s files', () {
    for (final MapEntry(key: rule, value: known)
        in _rulesAndKnownViolations.entries) {
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
