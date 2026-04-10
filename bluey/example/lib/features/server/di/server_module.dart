import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';
import '../infrastructure/server_repository_impl.dart';
import '../domain/use_cases/check_server_support.dart';
import '../domain/use_cases/start_advertising.dart';
import '../domain/use_cases/stop_advertising.dart';
import '../domain/use_cases/add_service.dart';
import '../domain/use_cases/send_notification.dart';
import '../domain/use_cases/observe_connections.dart';
import '../domain/use_cases/disconnect_central.dart';
import '../domain/use_cases/dispose_server.dart';

void registerServerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ServerRepository>(
    () => ServerRepositoryImpl(getIt<Bluey>()),
  );

  getIt.registerFactory<CheckServerSupport>(
    () => CheckServerSupport(getIt<ServerRepository>()),
  );
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
  getIt.registerFactory<ObserveConnections>(
    () => ObserveConnections(getIt<ServerRepository>()),
  );
  getIt.registerFactory<DisconnectCentral>(
    () => DisconnectCentral(getIt<ServerRepository>()),
  );
  getIt.registerFactory<DisposeServer>(
    () => DisposeServer(getIt<ServerRepository>()),
  );
}
