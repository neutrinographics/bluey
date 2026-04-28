import 'dart:typed_data';

import '../connection/value_objects/attribute_handle.dart';
import '../shared/characteristic_properties.dart';
import '../shared/uuid.dart';

/// A descriptor discovered on a connected remote device.
///
/// Descriptors are metadata attached to a [RemoteCharacteristic]. They are
/// discovered automatically as part of service discovery and are available
/// via [RemoteCharacteristic.descriptors].
///
/// ## Common descriptors
///
/// The most useful descriptors to be aware of:
///
/// - **User Description (0x2901):** A UTF-8 human-readable name for the
///   characteristic. Decode with `utf8.decode(await descriptor.read())`.
///   See [Descriptors.characteristicUserDescription].
///
/// - **CCCD (0x2902):** Controls notification/indication subscriptions. You
///   do not read or write this directly; the platform manages it automatically
///   when you call [Connection.subscribeToCharacteristic].
///   See [Descriptors.clientCharacteristicConfiguration].
///
/// - **Presentation Format (0x2904):** Describes the data type, unit, and
///   exponent of the characteristic value. Useful for vendor-specific numeric
///   characteristics without a well-known UUID.
///   See [Descriptors.characteristicPresentationFormat].
///
/// See [Descriptors] for the full list of standard descriptor UUIDs and their
/// data formats.
abstract class RemoteDescriptor {
  /// The UUID of this descriptor.
  UUID get uuid;

  /// The wire-level GATT handle for this descriptor.
  ///
  /// Stable for the lifetime of the owning [Connection]; invalidated only
  /// when the peer signals Service Changed (Android) or
  /// `didModifyServices` (iOS), at which point a fresh discovery mints
  /// new handles.
  AttributeHandle get handle;

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

  /// The wire-level GATT handle for this characteristic.
  ///
  /// Stable for the lifetime of the owning [Connection]; invalidated only
  /// when the peer signals Service Changed (Android) or
  /// `didModifyServices` (iOS), at which point a fresh discovery mints
  /// new handles.
  AttributeHandle get handle;

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
