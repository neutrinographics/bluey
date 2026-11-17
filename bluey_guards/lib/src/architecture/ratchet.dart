/// Judges what a rule [found] against the entries its list holds as [known],
/// so existing debt is tolerated while a new violation fails and a fixed one
/// has to be struck from the list. Order and repeats do not matter.
RatchetVerdict ratchet({
  required Iterable<String> found,
  required Iterable<String> known,
}) {
  final foundSet = found.toSet();
  final knownSet = known.toSet();
  return RatchetVerdict._(
    unlisted: List.unmodifiable(foundSet.difference(knownSet).toList()..sort()),
    stale: List.unmodifiable(knownSet.difference(foundSet).toList()..sort()),
  );
}

/// What a rule says about a [known] entry and a [found] one that are the
/// same file measured twice, or null when they are not. A rule whose entries
/// carry a measure supplies one, so a file that changed reads as one change
/// with which way to move, never as new debt beside paid debt.
typedef EntryChange =
    String? Function({required String known, required String found});

/// What [ratchet] decided, so a test can fail with a message that says what
/// to fix and what to delete.
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
  /// is not empty with what to do about it. A stale and an unlisted entry
  /// that [change] reads as one file that changed are told together, in the
  /// rule's words, and in neither of the other parts.
  String describe(String rule, {EntryChange? change}) {
    final changes = <String>[];
    final paired = <String>{};
    for (final known in stale) {
      for (final found in unlisted) {
        if (paired.contains(found)) continue;
        if (change?.call(known: known, found: found) case final advice?) {
          changes.add(advice);
          paired.addAll([known, found]);
          break;
        }
      }
    }
    bool unpaired(String entry) => !paired.contains(entry);
    final text = StringBuffer(
      '$rule: ${unlisted.length} not on its list, '
      '${stale.length} on its list that no longer holds.\n',
    );
    _part(
      text,
      'Not on the list. Fix it; a list never grows:',
      unlisted.where(unpaired),
    );
    _part(
      text,
      'On the list but no longer true. Delete the entry:',
      stale.where(unpaired),
    );
    _part(text, 'On the list, but its file changed:', changes);
    return text.toString();
  }
}

void _part(StringBuffer text, String heading, Iterable<String> entries) {
  if (entries.isEmpty) return;
  text.writeln(heading);
  for (final entry in entries) {
    text.writeln('  $entry');
  }
}
