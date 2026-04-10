import 'package:get_it/get_it.dart';

import '../domain/gatt_repository.dart';
import '../infrastructure/gatt_repository_impl.dart';
import '../domain/use_cases/read_characteristic.dart';
import '../domain/use_cases/write_characteristic.dart';
import '../domain/use_cases/subscribe_to_characteristic.dart';
import '../domain/use_cases/read_descriptor.dart';

void registerGattDependencies(GetIt getIt) {
  getIt.registerLazySingleton<GattRepository>(() => GattRepositoryImpl());

  getIt.registerFactory<ReadCharacteristic>(
    () => ReadCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<WriteCharacteristic>(
    () => WriteCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<SubscribeToCharacteristic>(
    () => SubscribeToCharacteristic(getIt<GattRepository>()),
  );
  getIt.registerFactory<ReadDescriptor>(
    () => ReadDescriptor(getIt<GattRepository>()),
  );
}
