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

  /// Watches [connection] for peer-status across its lifetime. Emits
  /// the initial `tryUpgrade` result, retries on every Service Changed
  /// re-discovery, completes after the first non-null peer or on
  /// disconnect. See [Bluey.watchPeer].
  Stream<PeerConnection?> watchPeer(Connection connection);

  /// Disconnects from a device.
  Future<void> disconnect(Connection connection);

  /// Returns the services available on a connected device.
  Future<List<RemoteService>> getServices(Connection connection);
}
