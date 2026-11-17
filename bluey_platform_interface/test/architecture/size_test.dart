import 'dart:io';

import 'package:bluey_guards/architecture.dart';

import 'known_violations.dart';

void main() {
  holdToKnownViolations(
    'bluey_platform_interface',
    tree: SourceTree.read(
      Directory.current,
      under: const ['lib'],
      extensions: const {'.dart'},
    ),
    anchor: 'lib/bluey_platform_interface.dart',
    rules: {SizeRule(limit: 300, extension: '.dart'): oversizedDart},
  );
}
