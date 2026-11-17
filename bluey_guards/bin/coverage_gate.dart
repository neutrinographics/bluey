import 'dart:io';

import 'package:bluey_guards/gates.dart';

const _usage =
    'Usage: dart run bluey_guards:coverage_gate <lcov file> <minimum>';

/// Holds a package to a line-coverage floor so CI fails when tests stop
/// covering what they used to. A missing report fails too: a job that
/// produced nothing proves nothing.
Future<void> main(List<String> arguments) async {
  final minimum = arguments.length == 2 ? num.tryParse(arguments[1]) : null;
  if (minimum == null) {
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  final file = File(arguments[0]);
  if (!file.existsSync()) {
    stdout.writeln('No coverage report at ${arguments[0]}.');
    await stdout.flush();
    exit(1);
  }
  final coverage = LineCoverage.parse(file.readAsStringSync());
  stdout.writeln(
    'Line coverage ${coverage.percent.toStringAsFixed(1)}% '
    '(${coverage.hit} of ${coverage.found} lines). '
    'The floor is $minimum%.',
  );
  await stdout.flush();
  exit(coverage.meets(minimum) ? 0 : 1);
}
