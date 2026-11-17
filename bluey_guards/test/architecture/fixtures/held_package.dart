import 'dart:io';

import 'package:bluey_guards/architecture.dart';

/// A package of one file over its limit, held by [holdToKnownViolations] to
/// a list that knows the file at an older length, and anchored at the file
/// the `ANCHOR` environment variable names, so the contract's test can ask
/// for an anchor the tree has and one it lacks.
void main() {
  final tree = SourceTree([
    const SourceFile(path: 'lib/held.dart', content: 'a\nb\nc\nd\n'),
  ]);
  holdToKnownViolations(
    'held',
    tree: tree,
    anchor: Platform.environment['ANCHOR'] ?? 'lib/held.dart',
    rules: {
      SizeRule(limit: 3, extension: '.dart'): ['lib/held.dart -> 5 lines'],
      const PublicExportsRule(package: 'held'): [],
    },
  );
}
