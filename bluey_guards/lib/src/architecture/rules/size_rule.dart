import '../architecture_rule.dart';
import '../source_tree.dart';

/// Holds every file of one language under a number of lines, so no file
/// grows past what a reader can hold in their head.
final class SizeRule implements ArchitectureRule {
  /// The rule for files with [extension] (such as `.dart`), at most [limit]
  /// lines each.
  const SizeRule({required this.limit, required this.extension});

  /// The most lines a file may have.
  final int limit;

  /// The extension of the files measured.
  final String extension;

  @override
  String get name => 'size of $extension files';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final file in tree.withExtension(extension))
      if (file.lineCount > limit)
        Violation(file.path, '${file.lineCount} lines'),
  ];
}
