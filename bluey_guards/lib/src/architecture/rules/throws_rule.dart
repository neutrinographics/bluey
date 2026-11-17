import '../architecture_rule.dart';
import '../dart_source.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Holds the contexts and the kernel to answering a failure as a value, so
/// the only errors that leave placed code are the programming errors that
/// mean a bug.
final class ThrowsRule implements ArchitectureRule {
  /// The rule, where [programmingErrors] are the classes placed code may
  /// throw.
  const ThrowsRule({required this.programmingErrors});

  /// The classes whose throw means a bug (`StateError`, `ArgumentError`),
  /// each allowed with any of its named constructors.
  final Set<String> programmingErrors;

  @override
  String get name => 'throws';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) case InFeature() || InShared())
        for (final raise in source.raises)
          if (!_isProgrammingError(raise))
            Violation(source.path, 'line ${raise.line}: ${raise.what}'),
  ];

  bool _isProgrammingError(Raise raise) {
    if (!raise.what.startsWith('throw ')) return false;
    final thrown = raise.what.substring('throw '.length);
    return programmingErrors.any(
      (error) => thrown == error || thrown.startsWith('$error.'),
    );
  }
}
