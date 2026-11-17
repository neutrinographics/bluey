import 'dart:io';

import 'package:bluey_guards/architecture.dart';

/// A package of one file over its limit, held by [holdToKnownViolations] to
/// a list that knows the file at an older length, and anchored at the file
/// the `ANCHOR` environment variable names, so the contract's test can ask
/// for an anchor the tree has and one it lacks. `STRAY_LIST` adds a list no
/// rule holds and `LISTLESS_RULE` a rule whose list the file lacks.
void main() {
  final tree = SourceTree([
    const SourceFile(path: 'lib/held.dart', content: 'a\nb\nc\nd\n'),
  ]);
  holdToKnownViolations(
    'held',
    tree: tree,
    anchor: Platform.environment['ANCHOR'] ?? 'lib/held.dart',
    rules: {
      'oversized': SizeRule(limit: 3, extension: '.dart'),
      'publicExports': const PublicExportsRule(package: 'held'),
      if (Platform.environment['LISTLESS_RULE'] case final name?)
        name: const PublicExportsRule(package: 'held'),
    },
    lists: {
      'oversized': ['lib/held.dart -> 5 lines'],
      'publicExports': [],
      if (Platform.environment['STRAY_LIST'] case final name?) name: [],
    },
  );
}
