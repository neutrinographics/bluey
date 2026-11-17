import 'source_tree.dart';

/// One thing a rule found wrong in one file, so a list of known violations
/// can name it in one line that reads the same on every machine.
final class Violation {
  /// What is wrong with [file], said by [detail].
  const Violation(this.file, this.detail);

  /// The package-relative path of the file at fault.
  final String file;

  /// What is wrong, in the rule's words: a path, a URI, a line or a count.
  final String detail;

  /// The line a list of known violations holds for this one.
  String get entry => '$file -> $detail';

  @override
  bool operator ==(Object other) =>
      other is Violation && other.file == file && other.detail == detail;

  @override
  int get hashCode => Object.hash(file, detail);

  @override
  String toString() => entry;
}

/// A rule of Bluey's architecture, a pure function of a [SourceTree], so a
/// test can hold a package to it and a test of the rule can build the package
/// in memory.
abstract interface class ArchitectureRule {
  /// The rule's name, which its list of known violations and its failure
  /// message are known by.
  String get name;

  /// Every violation in [tree], in the tree's order, then in source order
  /// within a file.
  List<Violation> check(SourceTree tree);
}
