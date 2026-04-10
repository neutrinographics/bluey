import 'package:bluey/bluey.dart';

/// Abstract repository interface for BLE connection operations.
abstract class ConnectionRepository {
  /// Connects to a BLE device.
  /// Returns a [Connection] object for the connected device.
  Future<Connection> connect(Device device, {Duration? timeout});

  /// Disconnects from a device.
  Future<void> disconnect(Connection connection);

  /// Returns the services available on a connected device.
  Future<List<RemoteService>> getServices(Connection connection);
}
