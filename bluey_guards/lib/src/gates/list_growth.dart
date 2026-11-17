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
    this.gone = const [],
  });

  /// Compares the lists of the file at [path] as the [base] held them, null
  /// when the base did not have the file, with the lists the [head] holds,
  /// null when the head no longer has the file.
  ///
  /// Each list is compared with the list of the same name at the base; a list
  /// the base did not have counts as an empty one, so renaming a list cannot
  /// carry new entries in. A count entry (`<path> -> <N> lines`) may be
  /// rewritten with a lower count, since a file that shrank must lower its
  /// entry. A file the base did not have holds whatever it lists: it is the
  /// first statement of what its rules find. A list the base had must still
  /// be in the head file, so a list cannot leave the gate's sight by moving
  /// to another file under the same name; a file the head deleted holds,
  /// since the test that reads it then fails.
  ///
  /// A list named in [byContext] holds `<source> -> <target>` entries whose
  /// debt is that the source depends on the target's context, not on its
  /// path, so it is counted per source and context instead: an entry may be
  /// rewritten when its target moved within its context, while an entry into
  /// a context the source did not depend on, or one more into a context it
  /// did, is added debt.
  factory ListGrowth.between({
    required String path,
    required Map<String, List<String>>? base,
    required Map<String, List<String>>? head,
    Set<String> byContext = const {},
  }) {
    if (base == null) {
      return ListGrowth._(path: path, isNew: true, added: [], raised: []);
    }
    if (head == null) {
      return ListGrowth._(path: path, isNew: false, added: [], raised: []);
    }
    final added = <String>[];
    final raised = <String>[];
    head.forEach((list, entries) {
      final before = base[list] ?? const [];
      if (byContext.contains(list)) {
        added.addAll(_ContextDebt.grown(list, before: before, after: entries));
        return;
      }
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
      gone: List.unmodifiable(
        base.keys.where((list) => !head.containsKey(list)),
      ),
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

  /// Each list the base had that the head file lacks.
  final List<String> gone;

  /// Whether no list of the file grew.
  bool get holds => added.isEmpty && raised.isEmpty && gone.isEmpty;

  /// The verdict in words: that the file is new, that no list grew, or each
  /// entry added, count raised and list gone with what to do.
  String describe() {
    if (isNew) {
      return '$path: not at the base, so its lists are the first statement '
          'of what they hold.\n';
    }
    if (holds) return '$path: no list grew.\n';
    final grew = added.isNotEmpty || raised.isNotEmpty;
    final text =
        StringBuffer('$path: ')
          ..writeAll([
            if (grew)
              '${_count(added.length, 'entry', 'entries')} added, '
                  '${_count(raised.length, 'count', 'counts')} raised',
            if (gone.isNotEmpty) '${_count(gone.length, 'list', 'lists')} gone',
          ], ', ')
          ..write('.')
          ..write(
            grew
                ? ' A list only shrinks: fix the code and take the line out of '
                    'the list.'
                : '',
          )
          ..writeln(
            gone.isNotEmpty
                ? ' A list file keeps every list it had: put the list back here, '
                    'under its name.'
                : '',
          );
    _part(text, 'Added:', added);
    _part(text, 'Raised:', raised);
    _part(text, 'Gone:', gone);
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

/// The entries of one source file into one context, keyed so a target that
/// moved from a legacy folder (`lib/src/connection/`) to its placed home
/// (`lib/src/features/connection/`) stays the same debt.
final class _ContextDebt {
  static final _shape = RegExp(r'^(.+) -> lib/src/(?:features/)?([^/]+)/');

  /// Each source and context the [after] entries reach more often than the
  /// [before] entries did, with the entries the base did not hold.
  static List<String> grown(
    String list, {
    required List<String> before,
    required List<String> after,
  }) {
    final was = _byKey(before);
    return [
      for (final MapEntry(key: key, value: entries) in _byKey(after).entries)
        if (entries.length > (was[key]?.length ?? 0))
          '$list: ${key.$1} into ${key.$2}, '
              '${_count(entries.length, 'entry', 'entries')} where the base '
              'had ${was[key]?.length ?? 0}: '
              '${entries.where((entry) => !before.contains(entry)).join('; ')}',
    ];
  }

  /// The entries grouped by source and context, a repeat counted once; an
  /// entry of another shape is its own key, so it is held strictly.
  static Map<(String, String), List<String>> _byKey(List<String> entries) {
    final grouped = <(String, String), List<String>>{};
    for (final entry in entries.toSet()) {
      final key = switch (_shape.firstMatch(entry)?.groups([1, 2])) {
        [final source?, final context?] => (source, context),
        _ => (entry, entry),
      };
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return grouped;
  }
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
