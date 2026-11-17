import '../architecture_rule.dart';
import '../source_tree.dart';

/// Holds every file of one language under a number of lines, so no file
/// grows past what a reader can hold in their head.
final class SizeRule implements MeasuringRule, WeighingRule {
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

  /// A size entry owes its file's lines, so a file that shrank owes less and
  /// one that grew owes more.
  @override
  Debt weigh(String entry) => switch (_Measured.parse(entry)) {
    final measured? => (debt: measured.path, amount: measured.lines),
    null => (debt: entry, amount: 1),
  };

  /// Shrink a file that grew back to its entry, and lower the entry of one
  /// that shrank, so the message never reads as an invitation to raise a
  /// ceiling.
  @override
  String? change({required String known, required String found}) {
    final (was, now) = (_Measured.parse(known), _Measured.parse(found));
    if (was == null || now == null || was.path != now.path) return null;
    return now.lines > was.lines
        ? '${now.path} grew from ${was.lines} to ${now.lines} lines: shrink '
            'the file to ${was.lines} lines or fewer; never raise the entry'
        : '${now.path} shrank from ${was.lines} to ${now.lines} lines: lower '
            'its entry to ${now.lines}';
  }
}

/// A size entry, `path -> N lines`, read back into its two halves.
final class _Measured {
  _Measured(this.path, this.lines);

  static final _shape = RegExp(r'^(.+) -> (\d+) lines$');

  static _Measured? parse(String entry) {
    if (_shape.firstMatch(entry)?.groups([1, 2]) case [
      final path?,
      final lines?,
    ]) {
      return _Measured(path, int.parse(lines));
    }
    return null;
  }

  final String path;
  final int lines;
}
