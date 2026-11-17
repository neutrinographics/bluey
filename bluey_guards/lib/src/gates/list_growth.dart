/// How one list file changed between the base of a change and its head, so
/// CI holds a list to only ever shrinking: the architecture test can check
/// that a list matches the code, but only a comparison with the base can see
/// a line copied into the list to make a new violation pass.
final class ListGrowth {
  ListGrowth._({
    required this.path,
    required this.isNew,
    required this.added,
    required this.raised,
  });

  /// Compares the lists of the file at [path] as the [base] held them, null
  /// when the base did not have the file, with the lists the [head] holds.
  ///
  /// Each list is compared with the list of the same name at the base; a list
  /// the base did not have counts as an empty one, so renaming a list cannot
  /// carry new entries in. A count entry (`<path> -> <N> lines`) may be
  /// rewritten with a lower count, since a file that shrank must lower its
  /// entry. A file the base did not have holds whatever it lists: it is the
  /// first statement of what its rules find.
  factory ListGrowth.between({
    required String path,
    required Map<String, List<String>>? base,
    required Map<String, List<String>> head,
  }) {
    if (base == null) {
      return ListGrowth._(path: path, isNew: true, added: [], raised: []);
    }
    final added = <String>[];
    final raised = <String>[];
    head.forEach((list, entries) {
      final before = base[list] ?? const [];
      final counted = {
        for (final entry in before.map(_CountEntry.parse).nonNulls)
          entry.path: entry.lines,
      };
      for (final entry in entries) {
        if (before.contains(entry)) continue;
        final count = _CountEntry.parse(entry);
        final was = counted[count?.path];
        if (count == null || was == null) {
          added.add('$list: $entry');
        } else if (count.lines > was) {
          raised.add(
            '$list: ${count.path} raised from $was to '
            '${count.lines} lines',
          );
        }
      }
    });
    return ListGrowth._(
      path: path,
      isNew: false,
      added: List.unmodifiable(added),
      raised: List.unmodifiable(raised),
    );
  }

  /// The list file, as the gate was given it.
  final String path;

  /// Whether the base did not have the file.
  final bool isNew;

  /// Each entry the head holds that its list at the base did not, as
  /// `<list>: <entry>`.
  final List<String> added;

  /// Each count entry whose count the head raised, as
  /// `<list>: <path> raised from <was> to <now> lines`.
  final List<String> raised;

  /// Whether no list of the file grew.
  bool get holds => added.isEmpty && raised.isEmpty;

  /// The verdict in words: that the file is new, that no list grew, or each
  /// entry added and count raised with what to do.
  String describe() {
    if (isNew) {
      return '$path: not at the base, so its lists are the first statement '
          'of what they hold.\n';
    }
    if (holds) return '$path: no list grew.\n';
    final text = StringBuffer(
      '$path: ${_count(added.length, 'entry', 'entries')} added, '
      '${_count(raised.length, 'count', 'counts')} raised. A list only '
      'shrinks: fix the code and take the line out of the list.\n',
    );
    _part(text, 'Added:', added);
    _part(text, 'Raised:', raised);
    return text.toString();
  }
}

/// An entry that carries a count of its file's lines, read back into its two
/// halves so a lower count reads as the same file shrinking.
final class _CountEntry {
  _CountEntry(this.path, this.lines);

  static final _shape = RegExp(r'^(.+) -> (\d+) lines$');

  static _CountEntry? parse(String entry) {
    if (_shape.firstMatch(entry)?.groups([1, 2]) case [
      final path?,
      final lines?,
    ]) {
      return _CountEntry(path, int.parse(lines));
    }
    return null;
  }

  final String path;
  final int lines;
}

String _count(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';

void _part(StringBuffer text, String heading, List<String> entries) {
  if (entries.isEmpty) return;
  text.writeln(heading);
  for (final entry in entries) {
    text.writeln('  $entry');
  }
}
