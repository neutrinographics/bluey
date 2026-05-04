import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../../features/scanner/di/scanner_module.dart';
import '../../features/connection/di/connection_module.dart';
import '../../features/service_explorer/di/service_explorer_module.dart';
import '../../features/server/di/server_module.dart';
import '../../features/stress_tests/di/stress_tests_module.dart';

final getIt = GetIt.instance;

/// Wires the shared [Bluey] singleton (with the persisted server
/// identity) and registers all per-feature dependencies.
///
/// [localIdentity] must be loaded before this is called — the central
/// side's peer-protocol upgrade path (`Bluey.tryUpgrade` /
/// `Bluey.watchPeer`) requires it, and the same identity is used for
/// the local server. Loading it eagerly at startup keeps a single
/// `Bluey` instance shared across all bounded contexts.
Future<void> setupServiceLocator({required ServerId localIdentity}) async {
  // Core dependency: identity-bound Bluey shared across all features.
  getIt.registerLazySingleton<Bluey>(() => Bluey(localIdentity: localIdentity));

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
