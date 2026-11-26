import '../architecture_rule.dart';
import '../dependency.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Holds each public library to exporting the package's own code, so the
/// public API is only what the package declares and never a whole other
/// package or another public library, and a bounded context reaches apps
/// only through its edge in `api/`, never by a file of its own being exported.
final class PublicExportsRule implements ArchitectureRule {
  /// The rule for [package].
  const PublicExportsRule({required this.package});

  /// The package the tree is of, so its own `package:` URIs resolve to files.
  final String package;

  @override
  String get name => 'public exports';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) is PublicLibrary)
        for (final uri in source.exports)
          if (!_isExportable(
            Dependency.resolve(from: source.path, uri: uri, package: package),
          ))
            Violation(source.path, uri),
  ];

  bool _isExportable(Dependency dependency) =>
      dependency is Internal &&
      dependency.path.startsWith('lib/src/') &&
      Placement.of(dependency.path) is! InFeature;
}
