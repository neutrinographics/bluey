/// Judges what a rule found against the list of what is already known, so
/// existing debt is tolerated while a new violation fails and a fixed one has
/// to be struck from the list: a list only ever shrinks.
final class Ratchet {
  Ratchet._();

  /// Compares the entries a rule [found] with the entries a list holds as
  /// [known]. Order and repeats do not matter.
  static RatchetVerdict judge({
    required Iterable<String> found,
    required Iterable<String> known,
  }) {
    final foundSet = found.toSet();
    final knownSet = known.toSet();
    return RatchetVerdict._(
      unlisted: List.unmodifiable(
        foundSet.difference(knownSet).toList()..sort(),
      ),
      stale: List.unmodifiable(knownSet.difference(foundSet).toList()..sort()),
    );
  }
}

/// What [Ratchet.judge] decided, so a test can fail with a message that says
/// what to fix and what to delete.
final class RatchetVerdict {
  RatchetVerdict._({required this.unlisted, required this.stale});

  /// What the rule found that the list does not hold, sorted: new debt.
  final List<String> unlisted;

  /// What the list holds that the rule no longer finds, sorted: an entry
  /// whose file moved, was deleted or was fixed.
  final List<String> stale;

  /// Whether the list is exactly what the rule found.
  bool get holds => unlisted.isEmpty && stale.isEmpty;

  /// The failure message for [rule]'s list: the counts, then each part that
  /// is not empty with what to do about it.
  String describe(String rule) {
    final text = StringBuffer(
      '$rule: ${unlisted.length} not on its list, '
      '${stale.length} on its list that no longer holds.\n',
    );
    if (unlisted.isNotEmpty) {
      text.writeln('Not on the list. Fix it; a list never grows:');
      for (final entry in unlisted) {
        text.writeln('  $entry');
      }
    }
    if (stale.isNotEmpty) {
      text.writeln(
        'On the list but no longer true. Delete the entry, or for a size '
        'entry write the new count:',
      );
      for (final entry in stale) {
        text.writeln('  $entry');
      }
    }
    return text.toString();
  }
}
