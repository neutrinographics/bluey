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
final class BoundaryRule implements MeasuringRule, WeighingRule {
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

  /// An entry owes its source's dependency on the target's context, not on
  /// the target's path, so a target that moved within its context, or out of
  /// today's folder into its place in the target layout, is the same debt.
  @override
  Debt weigh(String entry) {
    if (_Edge.parse(entry) case _Edge(:final source, :final target)) {
      if (libraryPlacement(target) case final placement?) {
        if (_contextOf(placement) case final context?) {
          return (debt: '$source into $context', amount: 1);
        }
      }
    }
    return (debt: entry, amount: 1);
  }

  /// A known entry and a found one that owe the same debt are one target
  /// that moved within its context, so the entry is rewritten, never told
  /// as new debt beside paid debt.
  @override
  String? change({required String known, required String found}) {
    final was = weigh(known);
    if (known == found || was.debt == known || was != weigh(found)) {
      return null;
    }
    if ((_Edge.parse(known), _Edge.parse(found)) case (
      _Edge(:final source, target: final from),
      _Edge(target: final to),
    )) {
      final context = was.debt.substring('$source into '.length);
      return '$source still depends on $context, but on $to, not on $from: '
          'rewrite the entry to the new path';
    }
    return null;
  }

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

/// A boundaries entry, `source -> target`, read back into its two halves
/// the one way both [BoundaryRule.weigh] and [BoundaryRule.change] read it.
/// An entry with more than one ` -> ` names no one target, so it is not of
/// this shape and is a debt of its own.
final class _Edge {
  _Edge(this.source, this.target);

  static _Edge? parse(String entry) => switch (entry.split(' -> ')) {
    [final source, final target] => _Edge(source, target),
    _ => null,
  };

  final String source;
  final String target;
}
