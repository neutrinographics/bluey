import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunFailureInjection {
  final StressTestRunner _runner;
  RunFailureInjection(this._runner);

  Stream<StressTestResult> call(
    FailureInjectionConfig config,
    Connection connection,
  ) {
    return _runner.runFailureInjection(config, connection);
  }
}
