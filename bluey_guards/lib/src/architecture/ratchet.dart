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
  /// is not empty with what to do about it. A size entry found in both parts
  /// is told apart as one file that grew or shrank, so the message never
  /// reads as an invitation to raise a ceiling.
  String describe(String rule) {
    final resized = _resized();
    final changedPaths = {for (final size in resized) size.path};
    bool unpaired(String entry) =>
        !changedPaths.contains(_SizeEntry.parse(entry)?.path);
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
    _part(text, 'A size entry that no longer matches its file:', [
      for (final size in resized) size.advice,
    ]);
    return text.toString();
  }

  List<_Resized> _resized() {
    final listed = {
      for (final entry in stale.map(_SizeEntry.parse).nonNulls)
        entry.path: entry.lines,
    };
    return [
      for (final found in unlisted.map(_SizeEntry.parse).nonNulls)
        if (listed[found.path] case final int was)
          _Resized(found.path, was: was, now: found.lines),
    ];
  }
}

/// One file whose size entry and length differ.
final class _Resized {
  _Resized(this.path, {required this.was, required this.now});

  final String path;
  final int was;
  final int now;

  String get advice =>
      now > was
          ? '$path grew from $was to $now lines: shrink the file to $was lines '
              'or fewer; never raise the entry'
          : '$path shrank from $was to $now lines: lower its entry to $now';
}

/// A size rule's entry, `path -> N lines`, read back into its two halves.
final class _SizeEntry {
  _SizeEntry(this.path, this.lines);

  static final _shape = RegExp(r'^(.+) -> (\d+) lines$');

  static _SizeEntry? parse(String entry) {
    final match = _shape.firstMatch(entry);
    if (match == null) return null;
    return _SizeEntry(match[1]!, int.parse(match[2]!));
  }

  final String path;
  final int lines;
}

void _part(StringBuffer text, String heading, Iterable<String> entries) {
  if (entries.isEmpty) return;
  text.writeln(heading);
  for (final entry in entries) {
    text.writeln('  $entry');
  }
}
