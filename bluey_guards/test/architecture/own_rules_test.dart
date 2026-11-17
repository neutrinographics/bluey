import 'dart:io';

import 'package:bluey_guards/architecture.dart';

/// The guards are held to the rules they hold the other packages to that
/// apply to a package with no layers: no file too long to read whole, and a
/// public library that exports only its own code.
void main() {
  holdToKnownViolations(
    'bluey_guards',
    tree: SourceTree.read(
      Directory.current,
      under: const ['lib', 'bin'],
      extensions: const {'.dart'},
    ),
    anchor: 'lib/architecture.dart',
    rules: {
      SizeRule(limit: 300, extension: '.dart'): [],
      const PublicExportsRule(package: 'bluey_guards'): [],
    },
  );
}
