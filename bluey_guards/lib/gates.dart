/// The gates CI runs over a test run's results, so a run that looks green
/// cannot hide a fixed defect whose test never moved, or one that stopped
/// running.
library;

export 'src/gates/known_defect_run.dart';
export 'src/gates/line_coverage.dart';
