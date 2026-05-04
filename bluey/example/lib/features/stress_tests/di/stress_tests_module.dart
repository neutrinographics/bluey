import 'package:get_it/get_it.dart';

import '../application/run_burst_write.dart';
import '../application/run_failure_injection.dart';
import '../application/run_mixed_ops.dart';
import '../application/run_mtu_probe.dart';
import '../application/run_notification_throughput.dart';
import '../application/run_soak.dart';
import '../application/run_timeout_probe.dart';
import '../infrastructure/stress_test_runner.dart';

void registerStressTestsDependencies(GetIt getIt) {
  getIt.registerLazySingleton<StressTestRunner>(() => StressTestRunner());
  getIt.registerFactory<RunBurstWrite>(() => RunBurstWrite(getIt()));
  getIt.registerFactory<RunMixedOps>(() => RunMixedOps(getIt()));
  getIt.registerFactory<RunSoak>(() => RunSoak(getIt()));
  getIt.registerFactory<RunTimeoutProbe>(() => RunTimeoutProbe(getIt()));
  getIt.registerFactory<RunFailureInjection>(
    () => RunFailureInjection(getIt()),
  );
  getIt.registerFactory<RunMtuProbe>(() => RunMtuProbe(getIt()));
  getIt.registerFactory<RunNotificationThroughput>(
    () => RunNotificationThroughput(getIt()),
  );
}
