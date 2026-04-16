import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';
import '../domain/connection_settings.dart';

/// Use case for connecting to a BLE device.
class ConnectToDevice {
  final ConnectionRepository _repository;

  ConnectToDevice(this._repository);

  /// Connects to the specified [device].
  ///
  /// The underlying [Bluey.connect] auto-upgrades to a peer connection
  /// when the device hosts the Bluey control service.
  ///
  /// Returns a [Connection] object for reading and writing characteristics.
  /// Throws a [BlueyException] if the connection fails.
  Future<Connection> call(
    Device device, {
    Duration? timeout,
    ConnectionSettings settings = const ConnectionSettings(),
  }) async {
    return await _repository.connect(
      device,
      timeout: timeout,
      settings: settings,
    );
  }
}
