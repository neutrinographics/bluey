import '../architecture_rule.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Lists the library files that are not yet in the target layout, so the
/// list of what is left to move can only shrink.
final class PlacementRule implements ArchitectureRule {
  /// The one placement rule.
  const PlacementRule();

  @override
  String get name => 'placement';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final file in tree.withExtension('.dart'))
      if (libraryPlacement(file.path) is Unplaced)
        Violation(file.path, 'unplaced'),
  ];
}
