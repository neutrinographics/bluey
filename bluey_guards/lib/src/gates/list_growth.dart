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
  /// carry new entries in. A file the base did not have holds whatever it
  /// lists: it is the first statement of what its rules find. A list the base
  /// had must still be in the head file, so a list cannot leave the gate's
  /// sight by moving to another file under the same name; a file the head
  /// deleted holds, since the test that reads it then fails.
  ///
  /// A list named in [weights] is judged by what its entries owe, as the rule
  /// that finds them weighs them: an entry rewritten for a debt the base owed
  /// holds while the debt is owed no more, a debt the base did not owe is an
  /// entry added, and one owed more is a count raised. Every other list is
  /// judged entry by entry.
  factory ListGrowth.between({
    required String path,
    required Map<String, List<String>>? base,
    required Map<String, List<String>>? head,
    Map<String, EntryWeight> weights = const {},
  }) {
    if (base == null) {
      return ListGrowth._(path: path, isNew: true, added: [], raised: []);
    }
    if (head == null) {
      return ListGrowth._(path: path, isNew: false, added: [], raised: []);
    }
    final added = <String>[];
    final raised = <String>[];
    head.forEach((list, listed) {
      final before = (base[list] ?? const []).toSet();
      final weigh = weights[list] ?? _itself;
      final owed = _owed(before, weigh);
      for (final MapEntry(key: debt, value: (:amount, entries: owing))
          in _owed(listed.toSet(), weigh).entries) {
        final was = owed[debt]?.amount;
        final fresh = owing.where((entry) => !before.contains(entry));
        if (was == null) {
          added.addAll([for (final entry in fresh) '$list: $entry']);
        } else if (amount > was) {
          raised.add(
            '$list: $debt, $was at the base and $amount at the head: '
            '${fresh.join('; ')}',
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

  /// Each debt the head owes more of than the base did, as
  /// `<list>: <debt>, <was> at the base and <now> at the head: <entries>`,
  /// naming the entries the base did not hold.
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

/// How a rule weighs one entry of its list: the debt the entry records and
/// how much of it, so a gate compares what a list owes and not its text.
typedef EntryWeight = ({String debt, int amount}) Function(String entry);

({String debt, int amount}) _itself(String entry) => (debt: entry, amount: 1);

/// What [entries] owe, by debt: how much in all, and the entries owing it.
Map<String, ({int amount, List<String> entries})> _owed(
  Set<String> entries,
  EntryWeight weigh,
) {
  final owed = <String, ({int amount, List<String> entries})>{};
  for (final entry in entries) {
    final (:debt, :amount) = weigh(entry);
    final so = owed[debt];
    owed[debt] = (
      amount: (so?.amount ?? 0) + amount,
      entries: [...?so?.entries, entry],
    );
  }
  return owed;
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
