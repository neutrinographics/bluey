/// Bluey's architecture rules, the ratchet that judges what they find against
/// a list of known violations, and the vocabulary they are written in: the
/// files of a package, what a Dart file names and raises, where a path sits in
/// the target layout and what a URI points at.
library;

export 'src/architecture/architecture_rule.dart';
export 'src/architecture/dart_source.dart';
export 'src/architecture/dependency.dart';
export 'src/architecture/legacy_layout.dart';
export 'src/architecture/placement.dart';
export 'src/architecture/ratchet.dart';
export 'src/architecture/rules/boundary_rule.dart';
export 'src/architecture/rules/framework_rule.dart';
export 'src/architecture/rules/layer_rule.dart';
export 'src/architecture/rules/lint_options_rule.dart';
export 'src/architecture/rules/placement_rule.dart';
export 'src/architecture/rules/public_exports_rule.dart';
export 'src/architecture/rules/size_rule.dart';
export 'src/architecture/rules/throws_rule.dart';
export 'src/architecture/source_file.dart';
export 'src/architecture/source_tree.dart';
