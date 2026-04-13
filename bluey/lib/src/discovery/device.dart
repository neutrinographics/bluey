import 'package:meta/meta.dart';

import '../shared/uuid.dart';

/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [id] are considered equal,
/// even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
@immutable
class Device {
  /// Unique device identifier as a UUID.
  ///
  /// On iOS, this is the native CoreBluetooth UUID.
  /// On Android, this is derived from the MAC address.
  final UUID id;

  /// Hardware address used for platform connections.
  ///
  /// On Android, this is the MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, this is the same as [id] since iOS doesn't expose MAC addresses.
  final String address;

  /// Advertised device name, if available.
  final String? name;

  Device({
    required this.id,
    String? address,
    this.name,
  }) : address = address ?? id.toString();

  /// Creates a copy with updated fields.
  ///
  /// To explicitly set [name] to null, pass null. To keep the existing value,
  /// don't pass the parameter.
  Device copyWith({
    Object? name = _sentinel,
  }) {
    return Device(
      id: id,
      address: address,
      name: name == _sentinel ? this.name : name as String?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) {
    // Entity equality: based on ID only
    return other is Device && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Device(id: $id, name: $name)';
  }
}
