import '../architecture_rule.dart';
import '../dependency.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Holds each context's edge, `lib/src/api/<context>/`, to naming its own
/// context's code alone, so a context's public interface is never assembled
/// from another context's internals; it may still name another context's edge,
/// which is that context's public interface. A file directly in `api/` is the
/// edge of no one context and names none, unless it is a composition root,
/// which assembles them all. The kernel and unplaced code are left to the
/// other rules.
final class EdgeContextRule implements ArchitectureRule {
  /// The rule for [package], where [compositionRoots] are the files that may
  /// name every context.
  const EdgeContextRule({
    required this.package,
    required this.compositionRoots,
  });

  /// The package the tree is of, so its own `package:` URIs resolve to files.
  final String package;

  /// The files that assemble the package.
  final Set<String> compositionRoots;

  @override
  String get name => 'edge contexts';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) case InApi(
        :final context,
      ) when !compositionRoots.contains(source.path))
        for (final uri in source.uris)
          if (Dependency.resolve(from: source.path, uri: uri, package: package)
              case Internal(:final path)
              when _crosses(context, libraryPlacement(path)))
            Violation(source.path, path),
  ];

  bool _crosses(String? edgeContext, Placement? to) =>
      to is InFeature && to.context != edgeContext;
}
