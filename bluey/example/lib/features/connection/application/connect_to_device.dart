import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';
import '../domain/connection_settings.dart';

/// Use case for connecting to a BLE device.
class ConnectToDevice {
  final ConnectionRepository _repository;

  ConnectToDevice(this._repository);

  /// Connects to the specified [device].
  ///
  /// When [isBlueyServer] is true, uses [Bluey.connectToBlueyServer] to
  /// read the server's identity, start the lifecycle heartbeat, and hide
  /// the control service. Otherwise falls back to a plain BLE connection.
  ///
  /// Returns a [Connection] object for reading and writing characteristics.
  /// Throws a [BlueyException] if the connection fails.
  Future<Connection> call(
    Device device, {
    Duration? timeout,
    bool isBlueyServer = false,
    ConnectionSettings settings = const ConnectionSettings(),
  }) async {
    if (isBlueyServer) {
      return await _repository.connectToBlueyServer(
        device,
        timeout: timeout,
        settings: settings,
      );
    }
    return await _repository.connect(
      device,
      timeout: timeout,
      settings: settings,
    );
  }
}
