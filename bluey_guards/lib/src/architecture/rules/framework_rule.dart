import '../architecture_rule.dart';
import '../dependency.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Keeps the frameworks (Flutter, the platform interface) in infrastructure
/// and the composition roots, so the domain and the application can be
/// tested and reasoned about without them.
final class FrameworkRule implements ArchitectureRule {
  /// The rule for [package], where [frameworks] are libraries or whole
  /// packages (`package:flutter`) that only infrastructure and
  /// [compositionRoots] may name.
  const FrameworkRule({
    required this.package,
    required this.frameworks,
    required this.compositionRoots,
  });

  /// The package the tree is of, so its own `package:` URIs resolve to files.
  final String package;

  /// The libraries, or whole packages, that count as a framework.
  final Set<String> frameworks;

  /// The paths of the files that assemble the package and so may name a
  /// framework wherever they sit.
  final Set<String> compositionRoots;

  @override
  String get name => 'framework placement';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (_judges(source.path))
        for (final uri in source.uris)
          if (_isFramework(
            Dependency.resolve(from: source.path, uri: uri, package: package),
          ))
            Violation(source.path, uri),
  ];

  bool _isFramework(Dependency dependency) =>
      dependency is External && frameworks.any(dependency.isWithin);

  bool _judges(String path) =>
      path.startsWith('lib/src/') &&
      !compositionRoots.contains(path) &&
      layerOf(Placement.of(path)) != Layer.infrastructure;
}
