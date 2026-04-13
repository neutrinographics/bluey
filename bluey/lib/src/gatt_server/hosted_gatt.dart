import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../shared/characteristic_properties.dart';
import '../shared/uuid.dart';

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
