import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';
import '../infrastructure/bluey_scanner_repository.dart';
import '../application/scan_for_devices.dart';
import '../application/stop_scan.dart';
import '../application/get_bluetooth_state.dart';
import '../application/request_permissions.dart';
import '../application/request_enable.dart';

void registerScannerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ScannerRepository>(
    () => BlueyScannerRepository(getIt<Bluey>()),
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
