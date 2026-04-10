import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';

/// Implementation of [ConnectionRepository] using the Bluey library.
class ConnectionRepositoryImpl implements ConnectionRepository {
  final Bluey _bluey;

  ConnectionRepositoryImpl(this._bluey);

  @override
  Future<Connection> connect(Device device, {Duration? timeout}) async {
    return await _bluey.connect(device, timeout: timeout);
  }

  @override
  Future<void> disconnect(Connection connection) async {
    await connection.disconnect();
  }

  @override
  Future<List<RemoteService>> discoverServices(Connection connection) async {
    return await connection.services;
  }
}
