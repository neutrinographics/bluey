import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';
import '../infrastructure/bluey_connection_repository.dart';
import '../domain/use_cases/connect_to_device.dart';
import '../domain/use_cases/disconnect_device.dart';
import '../domain/use_cases/get_services.dart';

void registerConnectionDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ConnectionRepository>(
    () => BlueyConnectionRepository(getIt<Bluey>()),
  );

  getIt.registerFactory<ConnectToDevice>(
    () => ConnectToDevice(getIt<ConnectionRepository>()),
  );
  getIt.registerFactory<DisconnectDevice>(
    () => DisconnectDevice(getIt<ConnectionRepository>()),
  );
  getIt.registerFactory<GetServices>(
    () => GetServices(getIt<ConnectionRepository>()),
  );
}
