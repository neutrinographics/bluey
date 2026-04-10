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

  /// Sends a notification to all connected clients.
  Future<void> notify(UUID characteristicUuid, Uint8List data);

  /// Stream of client device connections.
  Stream<Client> get connections;

  /// Stream of client device disconnections (emits central ID).
  Stream<String> get disconnections;

  /// Returns the currently connected clients.
  List<Client> get connectedClients;

  /// Stream of read requests from connected clients.
  Stream<ReadRequest> get readRequests;

  /// Stream of write requests from connected clients.
  Stream<WriteRequest> get writeRequests;

  /// Responds to a read request.
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  });

  /// Responds to a write request.
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  });

  /// Disconnects a specific client device.
  Future<void> disconnectClient(Client central);

  /// Disposes the server resources.
  Future<void> dispose();
}
