import 'dart:typed_data';

import 'package:bluey/bluey.dart';

/// Abstract repository interface for BLE server operations.
abstract class ServerRepository {
  /// Gets the server instance, or null if not supported on this platform.
  Server? getServer();

  /// Starts advertising with the given parameters.
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  });

  /// Stops advertising.
  Future<void> stopAdvertising();

  /// Adds a hosted service to the server.
  Future<void> addService(HostedService service);

  /// Sends a notification to all connected centrals.
  Future<void> notify(UUID characteristicUuid, Uint8List data);

  /// Stream of central device connections.
  Stream<Central> get connections;

  /// Disconnects a specific central device.
  Future<void> disconnectCentral(Central central);

  /// Disposes the server resources.
  Future<void> dispose();
}
