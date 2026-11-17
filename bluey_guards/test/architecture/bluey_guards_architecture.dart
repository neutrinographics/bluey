import 'dart:io';

import 'package:bluey_guards/architecture.dart';
import 'package:bluey_guards/gates.dart';

/// The package these rules hold, and the file every checkout of it has.
const package = 'bluey_guards';
const anchor = 'lib/architecture.dart';

/// The guards' library and command files, read from the package root a test
/// runs in.
SourceTree readPackage() => SourceTree.read(
  Directory.current,
  under: const ['lib', 'bin'],
  extensions: const {'.dart'},
);

/// What the rules are known to find today, read from the list file itself,
/// so a rule is held to exactly the list the file declares and the list gate
/// compares the same text.
Map<String, List<String>> readKnownViolations() => readLists(
  File('test/architecture/known_violations.dart').readAsStringSync(),
);

/// Each rule the package is held to, by the name of its list.
final Map<String, ArchitectureRule> packageRules = {
  'oversized': SizeRule(limit: 300, extension: '.dart'),
  'publicExports': const PublicExportsRule(package: 'bluey_guards'),
};
