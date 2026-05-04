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
    return await _bluey.connect(device, timeout: timeout);
  }

  @override
  Stream<PeerConnection?> watchPeer(Connection connection) {
    return _bluey.watchPeer(connection);
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
