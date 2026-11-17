import '../architecture_rule.dart';
import '../dependency.dart';
import '../legacy_layout.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Holds each bounded context to itself and the kernel to naming no context,
/// in today's folders and in the target layout alike, so a context reaches
/// another only through a bridge, and a bridge only the other's domain and
/// application.
final class BoundaryRule implements ArchitectureRule {
  /// The rule for [package], whose code that has not moved yet is read
  /// through [legacy].
  const BoundaryRule({required this.package, required this.legacy});

  /// The package the tree is of, so its own `package:` URIs resolve to files.
  final String package;

  /// Which of today's folders are contexts and which are kernel.
  final LegacyLayout legacy;

  @override
  String get name => 'boundaries';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) case final placement?)
        for (final uri in source.uris)
          if (Dependency.resolve(from: source.path, uri: uri, package: package)
              case Internal(:final path)
              when _crosses(placement, libraryPlacement(path)))
            Violation(source.path, path),
  ];

  bool _crosses(Placement from, Placement? to) {
    if (to == null) return false;
    final targetContext = _contextOf(to);
    if (targetContext == null) return false;
    if (_isKernel(from)) return true;
    final sourceContext = _contextOf(from);
    if (sourceContext == null || sourceContext == targetContext) return false;
    return !_bridgeReach(from, to);
  }

  /// Whether [from] is a bridge and [to] is what a bridge may name of the
  /// other context: its domain or its application.
  bool _bridgeReach(Placement from, Placement to) =>
      from is InFeature &&
      from.isBridge &&
      to is InFeature &&
      to.layer != Layer.infrastructure;

  String? _contextOf(Placement placement) => switch (placement) {
    InFeature(:final context) => context,
    Unplaced(:final folder?) when legacy.contexts.contains(folder) => folder,
    _ => null,
  };

  bool _isKernel(Placement placement) => switch (placement) {
    InShared() => true,
    Unplaced(:final folder?) => legacy.shared.contains(folder),
    _ => false,
  };
}
