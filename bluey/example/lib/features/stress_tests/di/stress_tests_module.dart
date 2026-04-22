import 'package:get_it/get_it.dart';

import '../application/run_burst_write.dart';
import '../infrastructure/stress_test_runner.dart';

void registerStressTestsDependencies(GetIt getIt) {
  getIt.registerLazySingleton<StressTestRunner>(() => StressTestRunner());
  getIt.registerFactory<RunBurstWrite>(() => RunBurstWrite(getIt()));
}
