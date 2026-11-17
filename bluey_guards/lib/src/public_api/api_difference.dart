/// The lines that differ between a committed API dump and the current one,
/// so a check can name exactly what an API change added and removed.
///
/// A member's line is compared together with the declaration it belongs to,
/// so a `String toString()` leaving one class is seen even though forty
/// other classes still have the same line.
final class ApiDifference {
  ApiDifference._({required this.removed, required this.added});

  /// The lines of [committed] that [current] no longer has, and the lines
  /// [current] has that [committed] did not.
  factory ApiDifference.between({
    required String committed,
    required String current,
  }) {
    final before = _entries(committed);
    final after = _entries(current);
    final kept = after.toSet();
    final known = before.toSet();
    return ApiDifference._(
      removed: List.unmodifiable(
        before.where((entry) => !kept.contains(entry)),
      ),
      added: List.unmodifiable(after.where((entry) => !known.contains(entry))),
    );
  }

  /// The entries only the committed dump has, in its order. A member reads
  /// `<declaration> > <member>`.
  final List<String> removed;

  /// The entries only the current dump has, in its order. A member reads
  /// `<declaration> > <member>`.
  final List<String> added;

  /// Whether the two dumps describe the same API.
  bool get isEmpty => removed.isEmpty && added.isEmpty;
}

List<String> _entries(String dump) {
  final entries = <String>[];
  var declaration = '';
  for (final line in dump.split('\n')) {
    if (line.isEmpty) continue;
    if (line.startsWith(' ')) {
      entries.add('$declaration > ${line.trimLeft()}');
    } else {
      declaration = line;
      entries.add(line);
    }
  }
  return entries;
}
