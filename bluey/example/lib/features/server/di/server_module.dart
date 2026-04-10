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
import '../application/disconnect_client.dart';
import '../application/dispose_server.dart';
import '../application/get_connected_clients.dart';
import '../application/observe_disconnections.dart';
import '../application/handle_requests.dart';

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
  getIt.registerFactory<DisconnectClient>(
    () => DisconnectClient(getIt<ServerRepository>()),
  );
  getIt.registerFactory<DisposeServer>(
    () => DisposeServer(getIt<ServerRepository>()),
  );
  getIt.registerFactory<GetConnectedClients>(
    () => GetConnectedClients(getIt<ServerRepository>()),
  );
  getIt.registerFactory<ObserveDisconnections>(
    () => ObserveDisconnections(getIt<ServerRepository>()),
  );
  getIt.registerFactory<ObserveReadRequests>(
    () => ObserveReadRequests(getIt<ServerRepository>()),
  );
  getIt.registerFactory<ObserveWriteRequests>(
    () => ObserveWriteRequests(getIt<ServerRepository>()),
  );
}
