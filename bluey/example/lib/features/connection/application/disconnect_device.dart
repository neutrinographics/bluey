import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';

/// Use case for disconnecting from a BLE device.
class DisconnectDevice {
  final ConnectionRepository _repository;

  DisconnectDevice(this._repository);

  /// Disconnects from the device associated with [connection].
  Future<void> call(Connection connection) async {
    await _repository.disconnect(connection);
  }
}
