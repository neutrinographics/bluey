/// The gates CI runs over a test run's results and over a change, so a run
/// that looks green cannot hide a fixed defect whose test never moved, one
/// that stopped running, or a list that grew to let new debt in.
library;

export 'src/gates/known_defect_run.dart';
export 'src/gates/line_coverage.dart';
export 'src/gates/list_file.dart';
export 'src/gates/list_growth.dart';
