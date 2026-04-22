import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunTimeoutProbe {
  final StressTestRunner _runner;
  RunTimeoutProbe(this._runner);

  Stream<StressTestResult> call(
    TimeoutProbeConfig config,
    Connection connection,
  ) {
    return _runner.runTimeoutProbe(config, connection);
  }
}
