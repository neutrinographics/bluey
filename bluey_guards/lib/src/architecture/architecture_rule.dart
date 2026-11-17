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

/// A rule that can tell an entry its list holds and one it finds as one
/// thing that changed (a file whose length moved, a target that moved within
/// its context), with what to do, never as new debt beside paid debt.
abstract interface class MeasuringRule implements ArchitectureRule {
  /// What to do about the one thing [known] and [found] both name, or null
  /// when they name different things.
  String? change({required String known, required String found});
}

/// What one entry of a rule's list owes: the [debt] it records and how much
/// of it, so a list can be compared across commits by what it owes and not
/// by its text.
typedef Debt = ({String debt, int amount});

/// A rule whose entries record a debt that outlives their text: a file that
/// shrank, a target that moved within its context. A gate that compares the
/// list across commits judges it by what it owes, so an entry rewritten for
/// the same debt is never new debt, and a debt may only be owed less.
abstract interface class WeighingRule implements ArchitectureRule {
  /// The debt [entry] records. An entry of another shape is a debt of its
  /// own, owed once, so it is held entry by entry.
  Debt weigh(String entry);
}

/// How the list of each rule in [rules] that weighs its entries weighs them,
/// by the list's name, for a gate that compares the lists across commits; a
/// list left out is compared entry by entry.
Map<String, Debt Function(String entry)> weightsOf(
  Map<String, ArchitectureRule> rules,
) => {
  for (final MapEntry(key: list, value: rule) in rules.entries)
    if (rule is WeighingRule) list: rule.weigh,
};
