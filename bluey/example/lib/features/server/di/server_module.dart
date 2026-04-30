import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';
import '../infrastructure/bluey_server_repository.dart';
import '../infrastructure/server_identity_storage.dart';
import '../application/check_server_support.dart';
import '../application/set_server_identity.dart';
import '../application/reset_server.dart';
import '../application/start_advertising.dart';
import '../application/stop_advertising.dart';
import '../application/add_service.dart';
import '../application/send_notification.dart';
import '../application/observe_connections.dart';
import '../application/observe_peer_connections.dart';
import '../application/dispose_server.dart';
import '../application/get_connected_clients.dart';
import '../application/observe_disconnections.dart';
import '../application/handle_requests.dart';
import '../application/get_server.dart';

void registerServerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ServerRepository>(
    () => BlueyServerRepository(getIt<Bluey>()),
  );

  getIt.registerLazySingleton<ServerIdentityStorage>(
    () => ServerIdentityStorage(),
  );

  getIt.registerFactory<CheckServerSupport>(
    () => CheckServerSupport(getIt<ServerRepository>()),
  );
  getIt.registerFactory<SetServerIdentity>(
    () => SetServerIdentity(getIt<ServerRepository>()),
  );
  getIt.registerFactory<ResetServer>(
    () => ResetServer(getIt<ServerRepository>()),
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
  getIt.registerFactory<ObservePeerConnections>(
    () => ObservePeerConnections(getIt<ServerRepository>()),
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
  getIt.registerFactory<GetServer>(
    () => GetServer(getIt<ServerRepository>()),
  );
}
