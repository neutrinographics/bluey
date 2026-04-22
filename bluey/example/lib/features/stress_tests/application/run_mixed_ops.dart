import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunMixedOps {
  final StressTestRunner _runner;
  RunMixedOps(this._runner);

  Stream<StressTestResult> call(
    MixedOpsConfig config,
    Connection connection,
  ) {
    return _runner.runMixedOps(config, connection);
  }
}
