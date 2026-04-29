import 'package:get_it/get_it.dart';
import 'package:bluey/bluey.dart';

import '../application/connect_to_device.dart';
import '../application/disconnect_device.dart';
import '../application/get_services.dart';
import '../application/watch_peer.dart';
import '../domain/connection_repository.dart';
import '../infrastructure/bluey_connection_repository.dart';
import '../presentation/connection_settings_cubit.dart';

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
  getIt.registerFactory<WatchPeer>(
    () => WatchPeer(getIt<ConnectionRepository>()),
  );

  // Session-scoped settings — keep the same instance so settings persist
  // across scanner/connection screen transitions.
  getIt.registerLazySingleton<ConnectionSettingsCubit>(
    () => ConnectionSettingsCubit(),
  );
}
