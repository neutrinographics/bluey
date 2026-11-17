/// The line coverage an lcov report records, so CI can hold a package to a
/// floor without a third-party service.
///
/// A report with no lines meets no floor: a run that measured nothing proves
/// nothing, and zero percent of nothing must not read as passing.
final class LineCoverage {
  const LineCoverage._(this.found, this.hit, this.files, this._records);

  /// Sums the `LF:` and `LH:` lines of every record in [lcov], and keeps the
  /// `SF:` path each record names.
  factory LineCoverage.parse(String lcov) {
    final records = <({String file, int found, int hit})>[];
    String? file;
    var found = 0;
    var hit = 0;
    for (final line in lcov.split('\n')) {
      final text = line.trim();
      if (text.startsWith('SF:')) {
        if (file != null) records.add((file: file, found: found, hit: hit));
        (file, found, hit) = (text.substring(3), 0, 0);
      } else if (text.startsWith('LF:')) {
        found += int.tryParse(text.substring(3)) ?? 0;
      } else if (text.startsWith('LH:')) {
        hit += int.tryParse(text.substring(3)) ?? 0;
      }
    }
    if (file != null) records.add((file: file, found: found, hit: hit));
    return LineCoverage._of(records);
  }

  factory LineCoverage._of(List<({String file, int found, int hit})> records) =>
      LineCoverage._(
        records.fold(0, (sum, record) => sum + record.found),
        records.fold(0, (sum, record) => sum + record.hit),
        Set.unmodifiable(records.map((record) => record.file)),
        List.unmodifiable(records),
      );

  /// The coverage of the files [takesIn] accepts alone, so one part of a
  /// package, its domain, can be held to a floor of its own.
  LineCoverage within(bool Function(String file) takesIn) => LineCoverage._of([
    for (final record in _records)
      if (takesIn(record.file)) record,
  ]);

  final List<({String file, int found, int hit})> _records;

  /// The source files the report measured, as its `SF:` lines name them.
  /// A file no test loaded is not among them, whatever it holds.
  final Set<String> files;

  /// Lines the report says could run.
  final int found;

  /// Lines the report says did run.
  final int hit;

  /// Share of found lines that ran, 0 when none were found.
  double get percent => found == 0 ? 0 : hit * 100 / found;

  /// Whether coverage reaches [minimum]; false when no line was found.
  bool meets(num minimum) => found > 0 && percent >= minimum;
}
