import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../../features/scanner/di/scanner_module.dart';
import '../../features/connection/di/connection_module.dart';
import '../../features/service_explorer/di/service_explorer_module.dart';
import '../../features/server/di/server_module.dart';
import '../../features/stress_tests/di/stress_tests_module.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Core dependency
  getIt.registerLazySingleton<Bluey>(() => Bluey());

  // Bounded context registrations
  registerScannerDependencies(getIt);
  registerConnectionDependencies(getIt);
  registerServiceExplorerDependencies(getIt);
  registerServerDependencies(getIt);
  registerStressTestsDependencies(getIt);
}

Future<void> resetServiceLocator() async {
  await getIt.reset();
}
