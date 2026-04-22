import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';

/// Single point of contact between the stress_tests feature and a live
/// [Connection]. Each `run*` method returns a `Stream<StressTestResult>`
/// that emits incremental snapshots as ops complete and a final
/// `isRunning=false` snapshot when done.
///
/// Every method begins by sending [ResetCommand] to the server so the
/// run starts from a known baseline regardless of how the previous test
/// ended (see spec: "Test isolation").
class StressTestRunner {
  Stream<StressTestResult> runBurstWrite(
    BurstWriteConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runBurstWrite implemented in Task 11');
  }

  Stream<StressTestResult> runMixedOps(
    MixedOpsConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runMixedOps implemented in Task 14');
  }

  Stream<StressTestResult> runSoak(
    SoakConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runSoak implemented in Task 15');
  }

  Stream<StressTestResult> runTimeoutProbe(
    TimeoutProbeConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runTimeoutProbe implemented in Task 16');
  }

  Stream<StressTestResult> runFailureInjection(
    FailureInjectionConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runFailureInjection implemented in Task 17');
  }

  Stream<StressTestResult> runMtuProbe(
    MtuProbeConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runMtuProbe implemented in Task 18');
  }

  Stream<StressTestResult> runNotificationThroughput(
    NotificationThroughputConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runNotificationThroughput implemented in Task 19');
  }
}
