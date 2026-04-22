import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunNotificationThroughput {
  final StressTestRunner _runner;
  RunNotificationThroughput(this._runner);

  Stream<StressTestResult> call(
    NotificationThroughputConfig config,
    Connection connection,
  ) {
    return _runner.runNotificationThroughput(config, connection);
  }
}
