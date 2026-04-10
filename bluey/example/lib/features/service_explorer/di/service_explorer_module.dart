import 'package:get_it/get_it.dart';

import '../domain/characteristic_repository.dart';
import '../infrastructure/bluey_characteristic_repository.dart';
import '../domain/use_cases/read_characteristic.dart';
import '../domain/use_cases/write_characteristic.dart';
import '../domain/use_cases/subscribe_to_characteristic.dart';
import '../domain/use_cases/read_descriptor.dart';

void registerServiceExplorerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<CharacteristicRepository>(() => BlueyCharacteristicRepository());

  getIt.registerFactory<ReadCharacteristic>(
    () => ReadCharacteristic(getIt<CharacteristicRepository>()),
  );
  getIt.registerFactory<WriteCharacteristic>(
    () => WriteCharacteristic(getIt<CharacteristicRepository>()),
  );
  getIt.registerFactory<SubscribeToCharacteristic>(
    () => SubscribeToCharacteristic(getIt<CharacteristicRepository>()),
  );
  getIt.registerFactory<ReadDescriptor>(
    () => ReadDescriptor(getIt<CharacteristicRepository>()),
  );
}
