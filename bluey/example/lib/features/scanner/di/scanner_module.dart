import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';
import '../infrastructure/scanner_repository_impl.dart';
import '../domain/use_cases/scan_for_devices.dart';
import '../domain/use_cases/stop_scan.dart';
import '../domain/use_cases/get_bluetooth_state.dart';
import '../domain/use_cases/request_permissions.dart';
import '../domain/use_cases/request_enable.dart';

void registerScannerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ScannerRepository>(
    () => ScannerRepositoryImpl(getIt<Bluey>()),
  );

  getIt.registerFactory<ScanForDevices>(
    () => ScanForDevices(getIt<ScannerRepository>()),
  );
  getIt.registerFactory<StopScan>(() => StopScan(getIt<ScannerRepository>()));
  getIt.registerFactory<GetBluetoothState>(
    () => GetBluetoothState(getIt<ScannerRepository>()),
  );
  getIt.registerFactory<RequestPermissions>(
    () => RequestPermissions(getIt<ScannerRepository>()),
  );
  getIt.registerFactory<RequestEnable>(
    () => RequestEnable(getIt<ScannerRepository>()),
  );
}
