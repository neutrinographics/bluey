import 'dart:io';

import 'package:bluey_guards/gates.dart';

const _usage =
    'Usage: dart run bluey_guards:known_defects '
    '<roster> <json file> [<roster> <json file>]...';

/// The list a roster file holds its known defects' full names in.
const _rosterList = 'knownDefects';

/// Judges each `flutter test --reporter json` output of the known-defect
/// tests as one run, against the roster of the package it ran in, so CI
/// fails when a known defect passes, does not run, or is deleted or added
/// without its roster saying so. A file that is missing or empty is a run
/// with no result, which fails too: a job that produced nothing proves
/// nothing.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length.isOdd) {
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  var allHold = true;
  for (var pair = 0; pair < arguments.length; pair += 2) {
    final [rosterPath, path] = arguments.sublist(pair, pair + 2);
    final roster = _rosterAt(rosterPath);
    if (roster == null) {
      stderr.writeln('$rosterPath has no $_rosterList list.');
      allHold = false;
      continue;
    }
    final file = File(path);
    final run = KnownDefectRun.parse(
      file.existsSync() ? file.readAsLinesSync() : const [],
      roster: roster,
    );
    stdout
      ..writeln(path)
      ..write(run.describe());
    allHold = allHold && run.holds;
  }
  await stdout.flush();
  await stderr.flush();
  exit(allHold ? 0 : 1);
}

List<String>? _rosterAt(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return readLists(file.readAsStringSync())[_rosterList];
}
