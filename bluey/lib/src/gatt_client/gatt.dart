import 'dart:typed_data';

import '../shared/characteristic_properties.dart';
import '../shared/uuid.dart';

/// A descriptor on a connected device.
///
/// Descriptors are metadata about characteristics, such as the Client
/// Characteristic Configuration Descriptor (CCCD) used for enabling
/// notifications.
abstract class RemoteDescriptor {
  /// The UUID of this descriptor.
  UUID get uuid;

  /// Read the current value of the descriptor.
  ///
  /// Throws [GattException] if the read fails.
  Future<Uint8List> read();

  /// Write a value to the descriptor.
  ///
  /// Throws [GattException] if the write fails.
  Future<void> write(Uint8List value);
}

/// A characteristic on a connected device.
///
/// Characteristics are the primary way to interact with a BLE device.
/// They contain values that can be read, written, or subscribed to
/// depending on their properties.
abstract class RemoteCharacteristic {
  /// The UUID of this characteristic.
  UUID get uuid;

  /// The properties of this characteristic.
  ///
  /// Check these before calling read/write/subscribe to know what
  /// operations are supported.
  CharacteristicProperties get properties;

  /// Read the current value of the characteristic.
  ///
  /// Throws [OperationNotSupportedException] if [properties.canRead] is false.
  /// Throws [GattException] if the read fails.
  Future<Uint8List> read();

  /// Write a value to the characteristic.
  ///
  /// If [withResponse] is true (default), uses write-with-response.
  /// If [withResponse] is false, uses write-without-response.
  ///
  /// Throws [OperationNotSupportedException] if the write type is not supported.
  /// Throws [GattException] if the write fails.
  Future<void> write(Uint8List value, {bool withResponse = true});

  /// Stream of notification/indication values.
  ///
  /// Subscribing to this stream enables notifications on the characteristic.
  /// Unsubscribing disables notifications.
  ///
  /// Throws [OperationNotSupportedException] if [properties.canSubscribe] is false.
  Stream<Uint8List> get notifications;

  /// Get a descriptor by UUID.
  ///
  /// Throws [CharacteristicNotFoundException] if the descriptor is not found.
  RemoteDescriptor descriptor(UUID uuid);

  /// All descriptors of this characteristic.
  List<RemoteDescriptor> get descriptors;
}

/// A service on a connected device.
///
/// Services group related characteristics together. For example, the
/// Heart Rate Service contains the Heart Rate Measurement characteristic.
abstract class RemoteService {
  /// The UUID of this service.
  UUID get uuid;

  /// Whether this is a primary service.
  ///
  /// Primary services are the main services exposed by a device.
  /// Secondary services are included by primary services.
  bool get isPrimary;

  /// Get a characteristic by UUID.
  ///
  /// Throws [CharacteristicNotFoundException] if the characteristic is not found.
  RemoteCharacteristic characteristic(UUID uuid);

  /// All characteristics in this service.
  List<RemoteCharacteristic> get characteristics;

  /// Included services (services nested within this service).
  List<RemoteService> get includedServices;
}
