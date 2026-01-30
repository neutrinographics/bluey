import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'characteristic_properties.dart';
import 'device.dart';
import 'uuid.dart';

/// Permissions for GATT characteristic and descriptor values.
///
/// These control what operations centrals can perform on local attributes.
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

/// A descriptor for a local GATT characteristic.
///
/// Descriptors provide metadata about characteristics. The most common
/// descriptor is the Client Characteristic Configuration Descriptor (CCCD)
/// used to enable notifications.
@immutable
class LocalDescriptor {
  /// The UUID of this descriptor.
  final UUID uuid;

  /// The permissions for this descriptor.
  final List<GattPermission> permissions;

  /// The static value of this descriptor (for immutable descriptors).
  final Uint8List? value;

  /// Creates a local descriptor with the given UUID and permissions.
  const LocalDescriptor({
    required this.uuid,
    required this.permissions,
    this.value,
  });

  /// Creates an immutable (read-only) descriptor with a static value.
  ///
  /// Use this for descriptors whose value never changes, like
  /// Characteristic User Description.
  factory LocalDescriptor.immutable({
    required UUID uuid,
    required Uint8List value,
  }) {
    return LocalDescriptor(
      uuid: uuid,
      permissions: const [GattPermission.read],
      value: value,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocalDescriptor && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A characteristic for a local GATT service.
///
/// Characteristics are the primary way centrals interact with a peripheral.
/// They can be read, written, or subscribed to for notifications.
@immutable
class LocalCharacteristic {
  /// The UUID of this characteristic.
  final UUID uuid;

  /// The properties of this characteristic (read, write, notify, etc.).
  final CharacteristicProperties properties;

  /// The permissions for this characteristic's value.
  final List<GattPermission> permissions;

  /// The descriptors for this characteristic.
  final List<LocalDescriptor> descriptors;

  /// Creates a local characteristic.
  const LocalCharacteristic({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.descriptors = const [],
  });

  /// Creates a read-only characteristic.
  factory LocalCharacteristic.readable({
    required UUID uuid,
    List<LocalDescriptor> descriptors = const [],
  }) {
    return LocalCharacteristic(
      uuid: uuid,
      properties: const CharacteristicProperties(canRead: true),
      permissions: const [GattPermission.read],
      descriptors: descriptors,
    );
  }

  /// Creates a writable characteristic.
  factory LocalCharacteristic.writable({
    required UUID uuid,
    bool withResponse = true,
    List<LocalDescriptor> descriptors = const [],
  }) {
    return LocalCharacteristic(
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
  /// Notifiable characteristics can push updates to subscribed centrals.
  factory LocalCharacteristic.notifiable({
    required UUID uuid,
    List<LocalDescriptor> descriptors = const [],
  }) {
    return LocalCharacteristic(
      uuid: uuid,
      properties: const CharacteristicProperties(canNotify: true),
      permissions: const [GattPermission.read],
      descriptors: descriptors,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocalCharacteristic && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A service for the local GATT server.
///
/// Services group related characteristics together. For example, the
/// Heart Rate Service contains the Heart Rate Measurement characteristic.
@immutable
class LocalService {
  /// The UUID of this service.
  final UUID uuid;

  /// Whether this is a primary service.
  ///
  /// Primary services are discoverable by centrals. Secondary services
  /// can only be included by other services.
  final bool isPrimary;

  /// The characteristics in this service.
  final List<LocalCharacteristic> characteristics;

  /// Other services included by this service.
  final List<LocalService> includedServices;

  /// Creates a local service.
  const LocalService({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
    this.includedServices = const [],
  });

  @override
  bool operator ==(Object other) {
    return other is LocalService && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A connected central device (from the server's perspective).
///
/// When a central connects to this peripheral, a [Central] instance is
/// created to represent it. Use this to send notifications to specific
/// centrals or to disconnect them.
abstract class Central {
  /// The unique identifier of this central.
  UUID get id;

  /// The current MTU for this connection.
  int get mtu;

  /// Disconnect this central.
  Future<void> disconnect();
}

/// GATT server for peripheral role.
///
/// The Server allows this device to act as a BLE peripheral, advertising
/// services and responding to requests from centrals.
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
/// server.addService(LocalService(
///   uuid: UUID.short(0x180F),
///   characteristics: [
///     LocalCharacteristic.readable(uuid: UUID.short(0x2A19)),
///   ],
/// ));
///
/// // Start advertising
/// await server.startAdvertising(name: 'My Device');
///
/// // Listen for connections
/// server.connections.listen((central) {
///   print('Central connected: ${central.id}');
/// });
/// ```
abstract class Server {
  /// Whether advertising is currently active.
  bool get isAdvertising;

  /// Stream of connected central devices.
  ///
  /// Emits when a central connects to this peripheral.
  Stream<Central> get connections;

  /// Currently connected centrals.
  List<Central> get connectedCentrals;

  /// Add a service to the GATT database.
  ///
  /// Must be called before [startAdvertising].
  void addService(LocalService service);

  /// Remove a service by UUID.
  ///
  /// Cannot be called while advertising.
  void removeService(UUID uuid);

  /// Start advertising.
  ///
  /// [name] - The device name to advertise.
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

  /// Send a notification to all subscribed centrals.
  ///
  /// [characteristic] - The characteristic UUID to notify.
  /// [data] - The data to send.
  ///
  /// Returns after the notification is sent (with flow control).
  Future<void> notify(UUID characteristic, {required Uint8List data});

  /// Send a notification to a specific central.
  Future<void> notifyTo(
    Central central,
    UUID characteristic, {
    required Uint8List data,
  });

  /// Dispose the server and release resources.
  Future<void> dispose();
}
