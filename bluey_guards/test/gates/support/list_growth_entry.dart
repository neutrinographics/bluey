import 'dart:io';

import 'package:bluey_guards/gates.dart';

/// The list gate with no rule's weights, so the command tests can run it as
/// a process and judge its exit codes and output; a package's own
/// `test/architecture/list_growth.dart` is the gate CI runs.
Future<void> main(List<String> arguments) async {
  final code = await holdListsToShrinking(
    arguments,
    weights: const {},
    usage: 'Usage: list_growth_entry <base> <list file>...',
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
