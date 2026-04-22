import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunBurstWrite {
  final StressTestRunner _runner;
  RunBurstWrite(this._runner);

  Stream<StressTestResult> call(
    BurstWriteConfig config,
    Connection connection,
  ) {
    return _runner.runBurstWrite(config, connection);
  }
}
