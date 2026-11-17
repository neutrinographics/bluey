import '../architecture_rule.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Lists the library files that are not yet in the target layout, so the
/// list of what is left to move can only shrink, and the files placed under
/// a feature folder that is not one of the bounded contexts, so a misspelt
/// or invented context is never read as a seventh one.
final class PlacementRule implements ArchitectureRule {
  /// The rule for a package whose bounded contexts are [contexts], the
  /// folder names under `lib/src/features/`.
  const PlacementRule({required this.contexts});

  /// The folders under `lib/src/features/` that are a bounded context.
  final Set<String> contexts;

  @override
  String get name => 'placement';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final file in tree.withExtension('.dart'))
      if (libraryPlacement(file.path) case final placement?)
        if (_misplaced(placement) case final detail?)
          Violation(file.path, detail),
  ];

  String? _misplaced(Placement placement) => switch (placement) {
    Unplaced() => 'unplaced',
    InFeature(:final context) when !contexts.contains(context) =>
      'features/$context is not a context',
    _ => null,
  };
}
