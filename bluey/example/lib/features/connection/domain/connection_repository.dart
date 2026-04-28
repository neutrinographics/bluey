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

  /// Attempts to upgrade [connection] to a [PeerConnection] if the
  /// remote exposes the Bluey lifecycle service. Returns `null` for
  /// non-peer devices. The returned [PeerConnection] starts a
  /// [LifecycleClient] internally — heartbeats begin flowing
  /// immediately.
  Future<PeerConnection?> tryUpgrade(Connection connection);

  /// Disconnects from a device.
  Future<void> disconnect(Connection connection);

  /// Returns the services available on a connected device.
  Future<List<RemoteService>> getServices(Connection connection);
}
