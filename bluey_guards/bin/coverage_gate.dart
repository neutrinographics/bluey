import 'dart:io';

import 'package:bluey_guards/gates.dart';
import 'package:path/path.dart' as p;

const _usage =
    'Usage: dart run bluey_guards:coverage_gate <lcov file> <minimum> '
    '<lib folder> [<path pattern>...]';

/// Holds a package to a line-coverage floor so CI fails when tests stop
/// covering what they used to, and to every Dart file under its lib folder
/// with code that runs being in the report, since a file no test loads is
/// absent from it and never lowers the figure. A missing report fails too: a
/// job that produced nothing proves nothing. Run from the package's root.
///
/// Given path patterns (`lib/src/features/*/domain`), the floor holds only
/// the files under them, so the domain can be held higher than the package.
/// Patterns that take in no line at all pass, and say so: the folders they
/// name fill in as code moves into the target layout, and a floor that held
/// nothing must not read as one that was met.
Future<void> main(List<String> arguments) async {
  final minimum = arguments.length >= 3 ? num.tryParse(arguments[1]) : null;
  if (minimum == null) {
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  final [report, _, library, ...written] = arguments;
  final patterns = written.map(PathPattern.new).toList();
  bool inScope(String path) =>
      patterns.isEmpty || patterns.any((pattern) => pattern.takesIn(path));
  final file = File(report);
  if (!file.existsSync()) {
    stdout.writeln('No coverage report at $report.');
    await stdout.flush();
    exit(1);
  }
  final coverage = LineCoverage.parse(
    _withRelativePaths(file.readAsLinesSync()),
  ).within(inScope);
  final unreported = unreportedFiles({
    for (final MapEntry(key: path, value: source)
        in _dartSourcesUnder(library).entries)
      if (inScope(path)) path: source,
  }, coverage);
  final scope = patterns.isEmpty ? '' : ' of ${patterns.join(' and ')}';
  if (patterns.isNotEmpty && coverage.found == 0 && unreported.isEmpty) {
    stdout.writeln(
      'No line under ${patterns.join(' and ')} is in the report or holds code '
      'that runs, so the $minimum% floor holds nothing yet.',
    );
    await stdout.flush();
    exit(0);
  }
  stdout.writeln(
    'Line coverage$scope ${coverage.percent.toStringAsFixed(1)}% '
    '(${coverage.hit} of ${coverage.found} lines). '
    'The floor is $minimum%.',
  );
  if (unreported.isNotEmpty) {
    stdout.writeln(
      'Not in the report, though each holds code that runs. No test loads '
      'it; write the test that does:',
    );
    for (final path in unreported) {
      stdout.writeln('  $path');
    }
  }
  await stdout.flush();
  exit(coverage.meets(minimum) && unreported.isEmpty ? 0 : 1);
}

/// Every Dart file under [folder], by its path relative to the working
/// directory with forward slashes, as an lcov report names it.
Map<String, String> _dartSourcesUnder(String folder) => {
  for (final entity in Directory(folder).listSync(recursive: true))
    if (entity is File && p.extension(entity.path) == '.dart')
      _relative(entity.path): entity.readAsStringSync(),
};

/// The report's lines with each `SF:` path relative to the working
/// directory, since a report may name a file by its absolute path.
String _withRelativePaths(List<String> lines) => [
  for (final line in lines)
    line.startsWith('SF:') ? 'SF:${_relative(line.substring(3))}' : line,
].join('\n');

String _relative(String path) => p.split(p.relative(path)).join('/');
