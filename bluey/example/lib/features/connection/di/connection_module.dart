import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';
import '../infrastructure/connection_repository_impl.dart';
import '../domain/use_cases/connect_to_device.dart';
import '../domain/use_cases/disconnect_device.dart';
import '../domain/use_cases/discover_services.dart';

void registerConnectionDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ConnectionRepository>(
    () => ConnectionRepositoryImpl(getIt<Bluey>()),
  );

  getIt.registerFactory<ConnectToDevice>(
    () => ConnectToDevice(getIt<ConnectionRepository>()),
  );
  getIt.registerFactory<DisconnectDevice>(
    () => DisconnectDevice(getIt<ConnectionRepository>()),
  );
  getIt.registerFactory<DiscoverServices>(
    () => DiscoverServices(getIt<ConnectionRepository>()),
  );
}
