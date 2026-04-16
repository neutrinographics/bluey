import 'package:bluey/bluey.dart';
import 'package:get_it/get_it.dart';

import '../application/connect_saved_peer.dart';
import '../application/discover_peers.dart';
import '../application/forget_saved_peer.dart';
import '../infrastructure/peer_storage.dart';

void registerPeerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<PeerStorage>(() => PeerStorage());

  getIt.registerFactory<DiscoverPeers>(
    () => DiscoverPeers(getIt<Bluey>()),
  );
  getIt.registerFactory<ConnectSavedPeer>(
    () => ConnectSavedPeer(getIt<Bluey>(), getIt<PeerStorage>()),
  );
  getIt.registerFactory<ForgetSavedPeer>(
    () => ForgetSavedPeer(getIt<PeerStorage>()),
  );
}
