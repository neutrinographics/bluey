import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';
import '../infrastructure/bluey_server_repository.dart';
import '../application/check_server_support.dart';
import '../application/start_advertising.dart';
import '../application/stop_advertising.dart';
import '../application/add_service.dart';
import '../application/send_notification.dart';
import '../application/observe_connections.dart';
import '../application/disconnect_central.dart';
import '../application/dispose_server.dart';

void registerServerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ServerRepository>(
    () => BlueyServerRepository(getIt<Bluey>()),
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
