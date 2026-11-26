import '../architecture_rule.dart';
import '../source_tree.dart';

/// Keeps a package from naming a library that another package publishes for
/// someone else, so code shared among the platform packages never becomes
/// something an app, or the library apps use, leans on.
///
/// Every Dart file of the tree is judged, the infrastructure and the
/// composition root included, since no layer of the package is the library's
/// audience.
final class ReservedLibraryRule implements ArchitectureRule {
  /// The rule that refuses [libraries].
  const ReservedLibraryRule({required this.libraries});

  /// The libraries, by the exact URI a file names them with, that no file of
  /// the package may name.
  final Set<String> libraries;

  @override
  String get name => 'reserved libraries';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      for (final uri in source.uris)
        if (libraries.contains(uri)) Violation(source.path, uri),
  ];
}
