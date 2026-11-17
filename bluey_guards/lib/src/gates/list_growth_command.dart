import 'dart:io';

import 'list_file.dart';
import 'list_growth.dart';

/// Holds each list file named after the base in [arguments] to only ever
/// shrinking since the point where the change left that base, a commit or
/// ref git knows, so a pull request cannot make a new violation pass by
/// copying its line into a list. Each path is relative to the folder the
/// command runs in, inside the repository; the head is the file as it is on
/// disk. Each list named in [weights] is judged by what its rule says an
/// entry owes (see [ListGrowth.between]), every other entry by entry.
///
/// Answers the exit code: 0 when every list held, 1 when one grew, a list
/// file at the base or the head cannot be read, or the base cannot be found,
/// and 64 with [usage] when no list file is named.
Future<int> holdListsToShrinking(
  List<String> arguments, {
  Map<String, EntryWeight> weights = const {},
  String usage =
      'Usage: dart run bluey_guards:list_growth <base> '
          '<list file>...',
}) async {
  if (arguments.length < 2) {
    stderr.writeln(usage);
    return 64;
  }
  final [base, ...paths] = arguments;
  final mergeBase = await _git(['merge-base', base, 'HEAD']);
  if (mergeBase.exitCode != 0) {
    stderr.writeln('Cannot find where HEAD left $base: ${mergeBase.stderr}');
    return 1;
  }
  final commit = (mergeBase.stdout as String).trim();
  var allHold = true;
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
    final growth = ListGrowth.between(
      path: path,
      base: base,
      head: head,
      weights: weights,
    );
    stdout.write(growth.describe());
    allHold = allHold && growth.holds;
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
