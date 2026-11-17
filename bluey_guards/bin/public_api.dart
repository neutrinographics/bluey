import 'dart:io';

import 'package:bluey_guards/public_api.dart';

const _usage =
    'Usage: dart run bluey_guards:public_api <library> <dump> [--write]';

const _changed =
    'The public API changed. If that was meant, run this command with '
    '--write and review the dump as an API change.';

/// Checks a package's committed API dump against its library, or rewrites
/// it with `--write`, so CI fails on an API change nobody meant and a meant
/// one shows in the diff. Run from the package's root. A library that does
/// not resolve fails the run too, naming why, and is never written.
Future<void> main(List<String> arguments) async {
  final write = arguments.length == 3 && arguments.last == '--write';
  final paths = write ? arguments.take(2).toList() : arguments;
  if (paths.length != 2 || paths.any((path) => path.startsWith('-'))) {
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  final [library, dumpPath] = paths;
  final String current;
  try {
    current = await dumpPublicApi(library);
  } on ApiDumpRefusal catch (refusal) {
    stderr.writeln(refusal.message);
    await stderr.flush();
    exit(1);
  }
  final dump = File(dumpPath);
  if (write) {
    dump.writeAsStringSync(current);
    exit(0);
  }
  final committed = dump.existsSync() ? dump.readAsStringSync() : '';
  final difference = ApiDifference.between(
    committed: committed,
    current: current,
  );
  if (difference.isEmpty) exit(0);
  for (final line in difference.removed) {
    stdout.writeln('- $line');
  }
  for (final line in difference.added) {
    stdout.writeln('+ $line');
  }
  stdout.writeln(_changed);
  await stdout.flush();
  exit(1);
}
