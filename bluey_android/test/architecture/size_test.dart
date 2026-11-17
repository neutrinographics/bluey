import 'dart:io';

import 'package:bluey_guards/architecture.dart';

import 'known_violations.dart';

void main() {
  holdToKnownViolations(
    'bluey_android',
    tree: SourceTree.read(
      Directory.current,
      under: const ['lib', 'android/src/main/kotlin'],
      extensions: const {'.dart', '.kt'},
    ),
    anchor: 'lib/bluey_android.dart',
    rules: {
      SizeRule(limit: 300, extension: '.dart'): oversizedDart,
      SizeRule(limit: 400, extension: '.kt'): oversizedKotlin,
    },
  );
}
