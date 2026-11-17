import 'dart:io';

import 'package:bluey_guards/gates.dart';

/// Holds each list file to only ever shrinking since the change left its
/// base, every list entry by entry. A package whose rules weigh their
/// entries (a size entry's lines, a boundary's context) runs its own
/// `test/architecture/list_growth.dart`, which passes the rules' weights.
Future<void> main(List<String> arguments) async {
  final code = await holdListsToShrinking(arguments);
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
