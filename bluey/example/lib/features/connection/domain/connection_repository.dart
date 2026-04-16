import 'package:bluey/bluey.dart';

import 'connection_settings.dart';

/// Abstract repository interface for BLE connection operations.
abstract class ConnectionRepository {
  /// Connects to a BLE device.
  /// Returns a [Connection] object for the connected device.
  Future<Connection> connect(
    Device device, {
    Duration? timeout,
    ConnectionSettings settings = const ConnectionSettings(),
  });

  /// Connects to a device known to be a Bluey server.
  ///
  /// Reads the server's [ServerId], starts the lifecycle heartbeat,
  /// and hides the control service from the caller.
  Future<Connection> connectToBlueyServer(
    Device device, {
    Duration? timeout,
    ConnectionSettings settings = const ConnectionSettings(),
  });

  /// Disconnects from a device.
  Future<void> disconnect(Connection connection);

  /// Returns the services available on a connected device.
  Future<List<RemoteService>> getServices(Connection connection);
}
