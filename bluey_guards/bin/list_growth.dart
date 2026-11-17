import 'dart:io';

import 'package:bluey_guards/gates.dart';

const _usage = 'Usage: dart run bluey_guards:list_growth <base> <list file>...';

/// Holds each list file to only ever shrinking since the point where the
/// change left [base], a commit or ref git knows, so a pull request cannot
/// make a new violation pass by copying its line into a list. Each path is
/// relative to the folder the command runs in, inside the repository; the
/// head is the file as it is on disk.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  final [base, ...paths] = arguments;
  final mergeBase = await _git(['merge-base', base, 'HEAD']);
  if (mergeBase.exitCode != 0) {
    stderr.writeln('Cannot find where HEAD left $base: ${mergeBase.stderr}');
    await stderr.flush();
    exit(1);
  }
  final commit = (mergeBase.stdout as String).trim();
  var allHold = true;
  for (final path in paths) {
    final head = File(path);
    final growth = ListGrowth.between(
      path: path,
      base: await _listsAt(commit, path),
      head: head.existsSync() ? readLists(head.readAsStringSync()) : const {},
    );
    stdout.write(growth.describe());
    allHold = allHold && growth.holds;
  }
  await stdout.flush();
  exit(allHold ? 0 : 1);
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
