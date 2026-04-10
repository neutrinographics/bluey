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

  /// Stream of central device disconnections (emits central ID).
  Stream<String> get disconnections;

  /// Returns the currently connected centrals.
  List<Central> get connectedCentrals;

  /// Stream of read requests from connected centrals.
  Stream<ReadRequest> get readRequests;

  /// Stream of write requests from connected centrals.
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

  /// Disconnects a specific central device.
  Future<void> disconnectCentral(Central central);

  /// Disposes the server resources.
  Future<void> dispose();
}
