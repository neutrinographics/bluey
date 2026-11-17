import 'dart:io';

import 'package:bluey_guards/architecture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_violations.dart';

final Map<ArchitectureRule, List<String>> _rulesAndKnownViolations = {
  SizeRule(limit: 300, extension: '.dart'): oversizedDart,
  SizeRule(limit: 400, extension: '.kt'): oversizedKotlin,
};

void main() {
  final tree = SourceTree.read(
    Directory.current,
    under: const ['lib', 'android/src/main/kotlin'],
    extensions: const {'.dart', '.kt'},
  );

  group('the size of bluey_android\'s files', () {
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
