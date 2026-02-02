import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../../scanner/domain/scanner_repository.dart';
import '../../scanner/data/scanner_repository_impl.dart';
import '../../scanner/domain/use_cases/scan_for_devices.dart';
import '../../scanner/domain/use_cases/stop_scan.dart';
import '../../scanner/domain/use_cases/get_bluetooth_state.dart';
import '../../scanner/domain/use_cases/request_permissions.dart';
import '../../scanner/domain/use_cases/request_enable.dart';

import '../../connection/domain/connection_repository.dart';
import '../../connection/data/connection_repository_impl.dart';
import '../../connection/domain/use_cases/connect_to_device.dart';
import '../../connection/domain/use_cases/disconnect_device.dart';
import '../../connection/domain/use_cases/discover_services.dart';

import '../../gatt/domain/gatt_repository.dart';
import '../../gatt/data/gatt_repository_impl.dart';
import '../../gatt/domain/use_cases/read_characteristic.dart';
import '../../gatt/domain/use_cases/write_characteristic.dart';
import '../../gatt/domain/use_cases/subscribe_to_characteristic.dart';
import '../../gatt/domain/use_cases/unsubscribe_from_characteristic.dart';
import '../../gatt/domain/use_cases/read_descriptor.dart';

import '../../server/domain/server_repository.dart';
import '../../server/data/server_repository_impl.dart';
import '../../server/domain/use_cases/start_advertising.dart';
import '../../server/domain/use_cases/stop_advertising.dart';
import '../../server/domain/use_cases/add_service.dart';
import '../../server/domain/use_cases/send_notification.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Bluey instance
  getIt.registerLazySingleton<Bluey>(() => Bluey());

  // Repositories
  getIt.registerLazySingleton<ScannerRepository>(
    () => ScannerRepositoryImpl(getIt<Bluey>()),
  );
  getIt.registerLazySingleton<ConnectionRepository>(
    () => ConnectionRepositoryImpl(getIt<Bluey>()),
  );
  getIt.registerLazySingleton<GattRepository>(() => GattRepositoryImpl());
  getIt.registerLazySingleton<ServerRepository>(
    () => ServerRepositoryImpl(getIt<Bluey>()),
  );

  // Scanner Use Cases
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

  // Connection Use Cases
  getIt.registerFactory<ConnectToDevice>(
    () => ConnectToDevice(getIt<ConnectionRepository>()),
  );
  getIt.registerFactory<DisconnectDevice>(
    () => DisconnectDevice(getIt<ConnectionRepository>()),
  );
  getIt.registerFactory<DiscoverServices>(
    () => DiscoverServices(getIt<ConnectionRepository>()),
  );

  // GATT Use Cases
  getIt.registerFactory<ReadCharacteristic>(
    () => ReadCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<WriteCharacteristic>(
    () => WriteCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<SubscribeToCharacteristic>(
    () => SubscribeToCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<UnsubscribeFromCharacteristic>(
    () => UnsubscribeFromCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<ReadDescriptor>(
    () => ReadDescriptor(getIt<GattRepository>()),
  );

  // Server Use Cases
  getIt.registerFactory<StartAdvertising>(
    () => StartAdvertising(getIt<ServerRepository>()),
  );
  getIt.registerFactory<StopAdvertising>(
    () => StopAdvertising(getIt<ServerRepository>()),
  );
  getIt.registerFactory<AddService>(
    () => AddService(getIt<ServerRepository>()),
  );
  getIt.registerFactory<SendNotification>(
    () => SendNotification(getIt<ServerRepository>()),
  );
}

Future<void> resetServiceLocator() async {
  await getIt.reset();
}
