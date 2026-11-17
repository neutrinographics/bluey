import 'dart:io';

import 'package:bluey_guards/architecture.dart';
import 'package:bluey_guards/gates.dart';

import 'bluey_android_architecture.dart';

/// The Lists only shrink gate for this package, run from its root: each list
/// file named is held to shrinking since the change left the base, and each
/// list is judged by how its rule weighs its entries, so a size entry may be
/// lowered and a boundary whose target moved within its context rewritten.
/// This file is the one place the package's rules meet the gate.
Future<void> main(List<String> arguments) async {
  final code = await holdListsToShrinking(
    arguments,
    weights: weightsOf(packageRules),
    usage:
        'Usage: dart run test/architecture/list_growth.dart <base> '
        '<list file>...',
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
