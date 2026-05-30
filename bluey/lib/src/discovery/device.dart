import 'package:meta/meta.dart';

import 'device_address.dart';

/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [address] are considered
/// equal, even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
@immutable
class Device {
  /// Opaque, platform-assigned address of this remote device.
  ///
  /// On Android this is the MAC address; on iOS the `CBPeripheral.identifier`
  /// UUID string. Format is platform-specific — never parse it.
  final DeviceAddress address;

  /// Advertised device name, if available.
  final String? name;

  Device({required this.address, this.name});

  /// Creates a copy with updated fields.
  ///
  /// To explicitly set [name] to null, pass null. To keep the existing value,
  /// don't pass the parameter.
  Device copyWith({Object? name = _sentinel}) {
    return Device(
      address: address,
      name: name == _sentinel ? this.name : name as String?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is Device && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'Device(address: $address, name: $name)';
}
