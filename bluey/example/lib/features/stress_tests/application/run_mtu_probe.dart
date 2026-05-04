import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunMtuProbe {
  final StressTestRunner _runner;
  RunMtuProbe(this._runner);

  Stream<StressTestResult> call(MtuProbeConfig config, Connection connection) {
    return _runner.runMtuProbe(config, connection);
  }
}
