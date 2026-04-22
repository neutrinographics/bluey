import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunSoak {
  final StressTestRunner _runner;
  RunSoak(this._runner);

  Stream<StressTestResult> call(SoakConfig config, Connection connection) {
    return _runner.runSoak(config, connection);
  }
}
