import 'dart:io';

import 'package:bluey_guards/architecture.dart';

import 'known_violations.dart';

void main() {
  holdToKnownViolations(
    'bluey_ios',
    tree: SourceTree.read(
      Directory.current,
      under: const ['lib', 'ios/Classes'],
      extensions: const {'.dart', '.swift'},
    ),
    anchor: 'lib/bluey_ios.dart',
    rules: {
      SizeRule(limit: 300, extension: '.dart'): oversizedDart,
      SizeRule(limit: 400, extension: '.swift'): oversizedSwift,
    },
  );
}
