import '../architecture_rule.dart';
import '../dart_source.dart';
import '../dependency.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// The libraries outside the package that each layer adds to what the layers
/// inside it may already name, so domain stays plain Dart and only
/// infrastructure reaches a framework.
final class LayerAllowances {
  /// What [domain], [application] and [infrastructure] each add.
  const LayerAllowances({
    required this.domain,
    required this.application,
    required this.infrastructure,
  });

  /// The libraries, or whole packages, the domain may name.
  final Set<String> domain;

  /// What the application may name besides the domain's.
  final Set<String> application;

  /// What infrastructure may name besides the application's.
  final Set<String> infrastructure;

  /// Every library [layer] may name: its own and those of the layers inside
  /// it.
  Iterable<String> of(Layer layer) => [
    domain,
    if (layer.index >= Layer.application.index) application,
    if (layer == Layer.infrastructure) infrastructure,
  ].expand((libraries) => libraries);
}

/// Holds placed code to pointing inward, domain to application to
/// infrastructure, within a context and within the kernel, and keeps a
/// context's infrastructure out of the edge and the public libraries but for
/// the composition roots. A public library is held as the edge is, since an
/// export of an adapter would hand a consumer the infrastructure the edge
/// keeps from them. A dependency on another context is left to the boundary
/// rule.
final class LayerRule implements ArchitectureRule {
  /// The rule for [package], where [allowances] say which outside libraries
  /// each layer may name and [compositionRoots] are the files of the edge, or
  /// public libraries, that may name a context's infrastructure.
  const LayerRule({
    required this.package,
    required this.allowances,
    required this.compositionRoots,
  });

  /// The package the tree is of, so its own `package:` URIs resolve to files.
  final String package;

  /// The outside libraries each layer may name.
  final LayerAllowances allowances;

  /// The files of the edge, or public libraries, that assemble the package.
  final Set<String> compositionRoots;

  @override
  String get name => 'layers';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) case final placement?)
        for (final uri in source.uris)
          if (_resolve(source, uri) case final to
              when _breaks(source, placement, to))
            Violation(source.path, _named(uri, to)),
  ];

  Dependency _resolve(DartSource source, String uri) =>
      Dependency.resolve(from: source.path, uri: uri, package: package);

  String _named(String uri, Dependency dependency) => switch (dependency) {
    Internal(:final path) => path,
    External() => uri,
  };

  bool _breaks(DartSource source, Placement from, Dependency to) =>
      switch (from) {
        InFeature(:final layer) ||
        InShared(:final layer) => _breaksInside(from, layer, to),
        InApi() || PublicLibrary() => _breaksEdge(source.path, to),
        _ => false,
      };

  bool _breaksInside(Placement from, Layer layer, Dependency to) {
    if (to is External) {
      return !allowances.of(layer).any(to.isWithin);
    }
    return switch (targetPlacement(to)) {
      null => false,
      InFeature(:final context, layer: final targetLayer) =>
        from is InFeature &&
            from.context == context &&
            targetLayer.index > layer.index,
      InShared(layer: final targetLayer) => targetLayer.index > layer.index,
      _ => true,
    };
  }

  bool _breaksEdge(String path, Dependency to) =>
      !compositionRoots.contains(path) &&
      switch (targetPlacement(to)) {
        InFeature(layer: Layer.infrastructure) => true,
        _ => false,
      };
}
