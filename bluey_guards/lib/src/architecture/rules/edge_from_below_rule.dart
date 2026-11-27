import '../architecture_rule.dart';
import '../dependency.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Holds code that has not moved yet off the edge, `lib/src/api/`, but for
/// the composition roots, so the edge stays the outermost layer while the old
/// folders shrink: code below it that names a public type couples the inside
/// to what an app sees, and the move into the target layout would carry that
/// coupling along. Placed code is held by the layer rule, and the edge may
/// name itself.
final class EdgeFromBelowRule implements ArchitectureRule {
  /// The rule for [package], where [compositionRoots] are the files that may
  /// name the edge.
  const EdgeFromBelowRule({
    required this.package,
    required this.compositionRoots,
  });

  /// The package the tree is of, so its own `package:` URIs resolve to files.
  final String package;

  /// The files that assemble the package.
  final Set<String> compositionRoots;

  @override
  String get name => 'edge from below';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) is Unplaced &&
          !compositionRoots.contains(source.path))
        for (final uri in source.uris)
          if (Dependency.resolve(from: source.path, uri: uri, package: package)
              case Internal(:final path) when libraryPlacement(path) is InApi)
            Violation(source.path, path),
  ];
}
