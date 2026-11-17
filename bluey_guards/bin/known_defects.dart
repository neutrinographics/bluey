import 'dart:io';

import 'package:bluey_guards/gates.dart';

const _usage = 'Usage: dart run bluey_guards:known_defects <json file>...';

/// Judges each `flutter test --reporter json` output of the known-defect
/// tests as one run, so CI fails when a known defect passes or does not run.
/// A file that is missing or empty is a run with no result, which fails too:
/// a job that produced nothing proves nothing.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  var allHold = true;
  for (final path in arguments) {
    final file = File(path);
    final run = KnownDefectRun.parse(
      file.existsSync() ? file.readAsLinesSync() : const [],
    );
    stdout
      ..writeln(path)
      ..write(run.describe());
    allHold = allHold && run.holds;
  }
  await stdout.flush();
  exit(allHold ? 0 : 1);
}
