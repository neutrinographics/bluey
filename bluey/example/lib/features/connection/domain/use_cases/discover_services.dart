import 'package:bluey/bluey.dart';

import '../connection_repository.dart';

/// Use case for discovering services on a connected BLE device.
class DiscoverServices {
  final ConnectionRepository _repository;

  DiscoverServices(this._repository);

  /// Discovers all GATT services on the connected device.
  ///
  /// Returns a list of [RemoteService] objects representing the discovered services.
  Future<List<RemoteService>> call(Connection connection) async {
    return await _repository.discoverServices(connection);
  }
}
