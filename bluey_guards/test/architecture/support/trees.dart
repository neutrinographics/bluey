import 'package:bluey_guards/architecture.dart';

/// A tree of [files], path to content, built in memory so a rule's test
/// states the whole package it judges.
SourceTree tree(Map<String, String> files) => SourceTree([
  for (final MapEntry(:key, :value) in files.entries)
    SourceFile(path: key, content: value),
]);

/// A file's text that imports each of [uris], for a test that cares only
/// about what a file names.
String naming(List<String> uris) =>
    [for (final uri in uris) "import '$uri';"].join('\n');

/// The entries [rule] finds in [tree], as a list holds them.
List<String> entries(ArchitectureRule rule, SourceTree tree) => [
  for (final violation in rule.check(tree)) violation.entry,
];
