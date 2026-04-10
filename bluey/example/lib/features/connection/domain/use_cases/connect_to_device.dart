import 'package:bluey/bluey.dart';

import '../connection_repository.dart';

/// Use case for connecting to a BLE device.
class ConnectToDevice {
  final ConnectionRepository _repository;

  ConnectToDevice(this._repository);

  /// Connects to the specified [device].
  ///
  /// Returns a [Connection] object for reading and writing characteristics.
  /// Throws a [BlueyException] if the connection fails.
  Future<Connection> call(Device device, {Duration? timeout}) async {
    return await _repository.connect(device, timeout: timeout);
  }
}
