import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/recovery_notifier.dart';
import '../../features/scanner/di/scanner_module.dart';
import '../../features/connection/di/connection_module.dart';
import '../../features/service_explorer/di/service_explorer_module.dart';
import '../../features/server/di/server_module.dart';
import '../../features/stress_tests/di/stress_tests_module.dart';

final getIt = GetIt.instance;

/// The [ServerId] captured from the most recent [setupServiceLocator] call.
///
/// Stashed so [recreateBluey] can rebuild the [Bluey] singleton with the
/// same identity without having to pass it back in.
ServerId? _capturedIdentity;

/// Wires the shared [Bluey] singleton (with the persisted server
/// identity) and registers all per-feature dependencies.
///
/// [localIdentity] must be loaded before this is called — the central
/// side's peer-protocol upgrade path (`Bluey.tryUpgrade` /
/// `Bluey.watchPeer`) requires it, and the same identity is used for
/// the local server. Loading it eagerly at startup keeps a single
/// `Bluey` instance shared across all bounded contexts.
Future<void> setupServiceLocator({required ServerId localIdentity}) async {
  _capturedIdentity = localIdentity;

  // Broadcast notifier that lives for the full app lifetime; UI screens
  // key their BlocProviders off it to reconstruct cubits when Bluey is
  // recreated after a fatal adapter error.
  getIt.registerSingleton<RecoveryNotifier>(RecoveryNotifier());

  await _registerBlueyAndFeatures(localIdentity);
}

/// Internal helper that registers [Bluey] and all feature modules.
///
/// Extracted so [recreateBluey] can call it without re-registering
/// [RecoveryNotifier] (which must survive across resets).
Future<void> _registerBlueyAndFeatures(ServerId localIdentity) async {
  // Core dependency: identity-bound Bluey shared across all features.
  // Constructed eagerly via the async factory so the first feature to
  // touch it never sees `BluetoothState.unknown` — see `Bluey.create`.
  final bluey = await Bluey.create(localIdentity: localIdentity);
  getIt.registerSingleton<Bluey>(bluey);

  // Bounded context registrations
  registerScannerDependencies(getIt);
  registerConnectionDependencies(getIt);
  registerServiceExplorerDependencies(getIt);
  registerServerDependencies(getIt);
  registerStressTestsDependencies(getIt);
}

/// Disposes the current [Bluey] instance, resets GetIt, and builds a fresh
/// [Bluey] singleton with the same [ServerId] that was passed to
/// [setupServiceLocator].
///
/// The existing [RecoveryNotifier] is preserved across the reset — UI
/// screens hold references to it, so destroying and recreating it would
/// break their listeners. After the fresh [Bluey] is registered,
/// [RecoveryNotifier.notify] is called so any listening screens rebuild
/// their cubits against the new use cases.
///
/// Throws [StateError] if called before [setupServiceLocator] has run.
Future<void> recreateBluey() async {
  final identity = _capturedIdentity;
  assert(identity != null, 'setupServiceLocator must be called before recreateBluey');

  // Preserve the notifier — it outlives the GetIt reset.
  final recoveryNotifier = getIt<RecoveryNotifier>();

  // Dispose the stale Bluey before resetting GetIt so any open streams
  // are torn down cleanly.
  await getIt<Bluey>().dispose();

  // Full reset: clears all registered factories and singletons.
  await getIt.reset();

  // Re-register the same RecoveryNotifier instance so existing listeners
  // remain connected.
  getIt.registerSingleton<RecoveryNotifier>(recoveryNotifier);

  // Build a fresh Bluey and re-register all feature modules.
  await _registerBlueyAndFeatures(identity!);

  // Signal UI screens to rebuild their cubits with fresh use cases.
  recoveryNotifier.notify();
}

Future<void> resetServiceLocator() async {
  await getIt.reset();
}
