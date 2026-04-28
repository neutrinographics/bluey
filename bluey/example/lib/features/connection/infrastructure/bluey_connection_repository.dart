import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';
import '../domain/connection_settings.dart';

/// Implementation of [ConnectionRepository] using the Bluey library.
class BlueyConnectionRepository implements ConnectionRepository {
  final Bluey _bluey;

  BlueyConnectionRepository(this._bluey);

  @override
  Future<Connection> connect(
    Device device, {
    Duration? timeout,
    ConnectionSettings settings = const ConnectionSettings(),
  }) async {
    // Note: post-C.6 `Bluey.connect` no longer accepts a
    // `peerSilenceTimeout` (the parameter only matters when wrapping a
    // raw connection in a `PeerConnection`). The setting is currently
    // unused here; restoring it requires switching to
    // `Bluey.connectAsPeer` / `Bluey.tryUpgrade` (TODO post-C.7).
    return await _bluey.connect(
      device,
      timeout: timeout,
    );
  }

  @override
  Future<void> disconnect(Connection connection) async {
    await connection.disconnect();
  }

  @override
  Future<List<RemoteService>> getServices(Connection connection) async {
    return await connection.services();
  }
}
