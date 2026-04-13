import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'characteristic_properties.dart';
import 'manufacturer_data.dart';
import 'uuid.dart';

/// Permissions for GATT characteristic and descriptor values.
///
/// These control what operations clients can perform on local attributes.
enum GattPermission {
  /// Allow reading the attribute value.
  read,

  /// Allow reading only with an encrypted connection.
  readEncrypted,

  /// Allow writing the attribute value.
  write,

  /// Allow writing only with an encrypted connection.
  writeEncrypted,
}

/// A descriptor hosted by this device's GATT server.
///
/// Descriptors provide metadata about characteristics. The most common
/// descriptor is the Client Characteristic Configuration Descriptor (CCCD)
/// used to enable notifications.
@immutable
class HostedDescriptor {
  /// The UUID of this descriptor.
  final UUID uuid;

  /// The permissions for this descriptor.
  final List<GattPermission> permissions;

  /// The static value of this descriptor (for immutable descriptors).
  final Uint8List? value;

  /// Creates a hosted descriptor with the given UUID and permissions.
  const HostedDescriptor({
    required this.uuid,
    required this.permissions,
    this.value,
  });

  /// Creates an immutable (read-only) descriptor with a static value.
  ///
  /// Use this for descriptors whose value never changes, like
  /// Characteristic User Description.
  factory HostedDescriptor.immutable({
    required UUID uuid,
    required Uint8List value,
  }) {
    return HostedDescriptor(
      uuid: uuid,
      permissions: const [GattPermission.read],
      value: value,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostedDescriptor && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A characteristic hosted by this device's GATT server.
///
/// Characteristics are the primary way clients interact with a peripheral.
/// They can be read, written, or subscribed to for notifications.
@immutable
class HostedCharacteristic {
  /// The UUID of this characteristic.
  final UUID uuid;

  /// The properties of this characteristic (read, write, notify, etc.).
  final CharacteristicProperties properties;

  /// The permissions for this characteristic's value.
  final List<GattPermission> permissions;

  /// The descriptors for this characteristic.
  final List<HostedDescriptor> descriptors;

  /// Creates a hosted characteristic.
  const HostedCharacteristic({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.descriptors = const [],
  });

  /// Creates a read-only characteristic.
  factory HostedCharacteristic.readable({
    required UUID uuid,
    List<HostedDescriptor> descriptors = const [],
  }) {
    return HostedCharacteristic(
      uuid: uuid,
      properties: const CharacteristicProperties(canRead: true),
      permissions: const [GattPermission.read],
      descriptors: descriptors,
    );
  }

  /// Creates a writable characteristic.
  factory HostedCharacteristic.writable({
    required UUID uuid,
    bool withResponse = true,
    List<HostedDescriptor> descriptors = const [],
  }) {
    return HostedCharacteristic(
      uuid: uuid,
      properties: CharacteristicProperties(
        canWrite: withResponse,
        canWriteWithoutResponse: !withResponse,
      ),
      permissions: const [GattPermission.write],
      descriptors: descriptors,
    );
  }

  /// Creates a notifiable characteristic.
  ///
  /// Notifiable characteristics can push updates to subscribed clients.
  factory HostedCharacteristic.notifiable({
    required UUID uuid,
    List<HostedDescriptor> descriptors = const [],
  }) {
    return HostedCharacteristic(
      uuid: uuid,
      properties: const CharacteristicProperties(canNotify: true),
      permissions: const [GattPermission.read],
      descriptors: descriptors,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostedCharacteristic && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A service hosted by this device's GATT server.
///
/// Services group related characteristics together. For example, the
/// Heart Rate Service contains the Heart Rate Measurement characteristic.
@immutable
class HostedService {
  /// The UUID of this service.
  final UUID uuid;

  /// Whether this is a primary service.
  ///
  /// Primary services are discoverable by clients. Secondary services
  /// can only be included by other services.
  final bool isPrimary;

  /// The characteristics in this service.
  final List<HostedCharacteristic> characteristics;

  /// Other services included by this service.
  final List<HostedService> includedServices;

  /// Creates a hosted service.
  const HostedService({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
    this.includedServices = const [],
  });

  @override
  bool operator ==(Object other) {
    return other is HostedService && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// Response status for GATT operations.
///
/// Used when responding to read or write requests from clients.
enum GattResponseStatus {
  /// Operation completed successfully.
  success,

  /// Read operation not permitted.
  readNotPermitted,

  /// Write operation not permitted.
  writeNotPermitted,

  /// Invalid offset for the attribute value.
  invalidOffset,

  /// Invalid attribute value length.
  invalidAttributeLength,

  /// Insufficient authentication for the operation.
  insufficientAuthentication,

  /// Insufficient encryption for the operation.
  insufficientEncryption,

  /// Request not supported.
  requestNotSupported,
}

/// A read request from a connected client.
///
/// When a client reads a characteristic value, a [ReadRequest] is emitted
/// on [Server.readRequests]. The server must respond using [Server.respondToRead].
@immutable
class ReadRequest {
  /// The client that initiated this request.
  final Client client;

  /// The characteristic being read.
  final UUID characteristicId;

  /// The offset into the characteristic value.
  final int offset;

  // Internal request ID for response correlation.
  // ignore: public_member_api_docs
  final int internalRequestId;

  /// Creates a read request.
  const ReadRequest({
    required this.client,
    required this.characteristicId,
    required this.offset,
    required this.internalRequestId,
  });
}

/// A write request from a connected client.
///
/// When a client writes to a characteristic, a [WriteRequest] is emitted
/// on [Server.writeRequests]. If [responseNeeded] is true, the server must
/// respond using [Server.respondToWrite].
@immutable
class WriteRequest {
  /// The client that initiated this request.
  final Client client;

  /// The characteristic being written.
  final UUID characteristicId;

  /// The value being written.
  final Uint8List value;

  /// The offset into the characteristic value.
  final int offset;

  /// Whether a response is needed.
  ///
  /// If true, the server must call [Server.respondToWrite].
  /// If false, this is a "write without response" operation.
  final bool responseNeeded;

  // Internal request ID for response correlation.
  // ignore: public_member_api_docs
  final int internalRequestId;

  /// Creates a write request.
  const WriteRequest({
    required this.client,
    required this.characteristicId,
    required this.value,
    required this.offset,
    required this.responseNeeded,
    required this.internalRequestId,
  });
}

/// A connected client device (from the server's perspective).
///
/// When a client connects to this peripheral, a [Client] instance is
/// created to represent it. Use this to send notifications to specific
/// clients or to disconnect them.
abstract class Client {
  /// The unique identifier of this client.
  UUID get id;

  /// The current MTU for this connection.
  int get mtu;

  /// Disconnect this client.
  Future<void> disconnect();
}

/// GATT server for peripheral role.
///
/// The Server allows this device to act as a BLE peripheral, advertising
/// services and responding to requests from clients.
///
/// Example:
/// ```dart
/// final server = bluey.server();
/// if (server == null) {
///   print('Peripheral role not supported');
///   return;
/// }
///
/// // Add a service
/// server.addService(HostedService(
///   uuid: UUID.short(0x180F),
///   characteristics: [
///     HostedCharacteristic.readable(uuid: UUID.short(0x2A19)),
///   ],
/// ));
///
/// // Start advertising
/// await server.startAdvertising(name: 'My Device');
///
/// // Listen for connections
/// server.connections.listen((client) {
///   print('Client connected: ${client.id}');
/// });
/// ```
abstract class Server {
  /// Whether advertising is currently active.
  bool get isAdvertising;

  /// Stream of connected client devices.
  ///
  /// Emits when a client connects to this peripheral.
  Stream<Client> get connections;

  /// Stream of disconnected client device IDs.
  ///
  /// Emits the ID of a client when it disconnects from this peripheral.
  Stream<String> get disconnections;

  /// Currently connected clients.
  List<Client> get connectedClients;

  /// Add a service to the GATT database.
  ///
  /// Must be called before [startAdvertising].
  /// Throws if the GATT server cannot be opened or the service cannot be added.
  Future<void> addService(HostedService service);

  /// Remove a service by UUID.
  ///
  /// Cannot be called while advertising.
  void removeService(UUID uuid);

  /// Start advertising.
  ///
  /// [name] - The device name to include in the advertisement. On iOS, this
  /// sets the local name in the advertisement packet (foreground only). On
  /// Android, the system Bluetooth adapter name is always used instead;
  /// this parameter is included in the scan response header but does not
  /// override the adapter name.
  /// [services] - Service UUIDs to include in the advertisement.
  /// [manufacturerData] - Manufacturer-specific data.
  /// [timeout] - Stop advertising after this duration.
  ///
  /// Throws [AdvertisingException] if advertising fails.
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  });

  /// Stop advertising.
  Future<void> stopAdvertising();

  /// Send a notification to all subscribed clients.
  ///
  /// [characteristic] - The characteristic UUID to notify.
  /// [data] - The data to send.
  ///
  /// Returns after the notification is sent (with flow control).
  Future<void> notify(UUID characteristic, {required Uint8List data});

  /// Send a notification to a specific client.
  Future<void> notifyTo(
    Client client,
    UUID characteristic, {
    required Uint8List data,
  });

  /// Send an indication to all subscribed clients.
  ///
  /// Unlike notifications, indications require acknowledgment from the client
  /// before returning. Use this for data that must be reliably delivered.
  ///
  /// [characteristic] - The characteristic UUID to indicate.
  /// [data] - The data to send.
  Future<void> indicate(UUID characteristic, {required Uint8List data});

  /// Send an indication to a specific client.
  ///
  /// Unlike notifications, indications require acknowledgment from the client
  /// before returning. Use this for data that must be reliably delivered.
  Future<void> indicateTo(
    Client client,
    UUID characteristic, {
    required Uint8List data,
  });

  /// Stream of read requests from clients.
  ///
  /// When a client reads a characteristic value, a [ReadRequest] is emitted.
  /// The server must respond using [respondToRead].
  Stream<ReadRequest> get readRequests;

  /// Stream of write requests from clients.
  ///
  /// When a client writes to a characteristic, a [WriteRequest] is emitted.
  /// If [WriteRequest.responseNeeded] is true, the server must respond using
  /// [respondToWrite].
  Stream<WriteRequest> get writeRequests;

  /// Respond to a read request.
  ///
  /// [request] - The read request to respond to.
  /// [status] - The GATT status for the response.
  /// [value] - The value to return (required for success status).
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  });

  /// Respond to a write request.
  ///
  /// [request] - The write request to respond to.
  /// [status] - The GATT status for the response.
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  });

  /// Dispose the server and release resources.
  Future<void> dispose();
}
