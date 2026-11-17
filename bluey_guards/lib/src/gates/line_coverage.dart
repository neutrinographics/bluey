/// The line coverage an lcov report records, so CI can hold a package to a
/// floor without a third-party service.
///
/// A report with no lines meets no floor: a run that measured nothing proves
/// nothing, and zero percent of nothing must not read as passing.
final class LineCoverage {
  const LineCoverage._(this.found, this.hit);

  /// Sums the `LF:` and `LH:` lines of every record in [lcov].
  factory LineCoverage.parse(String lcov) {
    var found = 0;
    var hit = 0;
    for (final line in lcov.split('\n')) {
      final text = line.trim();
      if (text.startsWith('LF:')) {
        found += int.tryParse(text.substring(3)) ?? 0;
      } else if (text.startsWith('LH:')) {
        hit += int.tryParse(text.substring(3)) ?? 0;
      }
    }
    return LineCoverage._(found, hit);
  }

  /// Lines the report says could run.
  final int found;

  /// Lines the report says did run.
  final int hit;

  /// Share of found lines that ran, 0 when none were found.
  double get percent => found == 0 ? 0 : hit * 100 / found;

  /// Whether coverage reaches [minimum]; false when no line was found.
  bool meets(num minimum) => found > 0 && percent >= minimum;
}
