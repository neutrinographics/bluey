import 'dart:io';

import 'list_file.dart';
import 'list_growth.dart';

/// Holds each list file named after the base in [arguments] to only ever
/// shrinking since the point where the change left that base, a commit or
/// ref git knows, so a pull request cannot make a new violation pass by
/// copying its line into a list. Each path is relative to the folder the
/// command runs in, inside the repository; the head is the file as it is on
/// disk. Each list named in [weights] is judged by what its rule says an
/// entry owes (see [ListGrowth.between]), every other entry by entry. Both
/// [weights] and [usage] are the caller's, since only a package's own
/// composition root knows its rules and how it is run; a gate that ran with
/// no weights would fail a rewritten entry that holds.
///
/// Each `--first-statement=<list>` among [arguments], which may be repeated,
/// lets a list the base lacks hold whatever it lists, though its file is at
/// the base (see [ListGrowth.between]); it is for the one change that adds a
/// rule whose list states today's debt, and is printed as stale once the base
/// has the list.
///
/// Answers the exit code: 0 when every list held, 1 when one grew, a list
/// file at the base or the head cannot be read, the base cannot be found, or
/// a first-statement flag names a list no list file at the head declares,
/// and 64 with [usage] when no list file is named.
Future<int> holdListsToShrinking(
  List<String> arguments, {
  required Map<String, EntryWeight> weights,
  required String usage,
}) async {
  const flag = '--first-statement=';
  final firstStatements = {
    for (final argument in arguments)
      if (argument.startsWith(flag)) argument.substring(flag.length),
  };
  final positional = [
    for (final argument in arguments)
      if (!argument.startsWith(flag)) argument,
  ];
  if (positional.length < 2) {
    stderr.writeln(usage);
    return 64;
  }
  final [base, ...paths] = positional;
  final mergeBase = await _git(['merge-base', base, 'HEAD']);
  if (mergeBase.exitCode != 0) {
    stderr.writeln('Cannot find where HEAD left $base: ${mergeBase.stderr}');
    return 1;
  }
  final commit = (mergeBase.stdout as String).trim();
  var allHold = true;
  final declared = <String>{};
  for (final path in paths) {
    final Map<String, List<String>>? base;
    final Map<String, List<String>>? head;
    try {
      base = await _listsAt(commit, path);
    } on ListFileRefusal catch (refusal) {
      stderr.writeln('$path at the base: ${refusal.message}');
      allHold = false;
      continue;
    }
    try {
      final file = File(path);
      head = file.existsSync() ? readLists(file.readAsStringSync()) : null;
    } on ListFileRefusal catch (refusal) {
      stderr.writeln('$path: ${refusal.message}');
      allHold = false;
      continue;
    }
    final lists = head?.keys ?? const <String>[];
    declared.addAll(lists);
    final growth = ListGrowth.between(
      path: path,
      base: base,
      head: head,
      weights: weights,
      firstStatements: firstStatements.intersection(lists.toSet()),
    );
    stdout.write(growth.describe());
    allHold = allHold && growth.holds;
  }
  for (final list in firstStatements.difference(declared)) {
    stderr.writeln('$flag$list names a list no list file at the head declares');
    allHold = false;
  }
  return allHold ? 0 : 1;
}

/// The lists of [path] as [commit] held them, or null when it had no such
/// file. The `./` makes git read [path] from the folder the command runs in.
Future<Map<String, List<String>>?> _listsAt(String commit, String path) async {
  final object = '$commit:./$path';
  if ((await _git(['cat-file', '-e', object])).exitCode != 0) return null;
  final shown = await _git(['show', object]);
  return readLists(shown.stdout as String);
}

Future<ProcessResult> _git(List<String> arguments) =>
    Process.run('git', arguments);
