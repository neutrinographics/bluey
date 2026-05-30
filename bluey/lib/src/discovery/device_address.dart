import 'package:meta/meta.dart';

/// Opaque, platform-assigned address of a remote BLE **peripheral that this
/// device discovered or reached out to** — the *outbound* direction, in which
/// the local role is GATT **client** and the remote is the GATT server.
///
/// Sourced at the scan/connection seam from `PlatformDevice.id`: the MAC
/// address on Android, the `CBPeripheral.identifier` UUID string on iOS. The
/// format is platform-specific and opaque — never parse it.
///
/// Mirror of [ClientAddress], which addresses a remote central that connected
/// *inbound* to our local `Server`. Both wrap the same kind of platform
/// string; the distinct types keep the communication direction legible and
/// prevent accidental cross-assignment. The two coincide only when one peer
/// both scans and advertises (see `Server.isClientConnected`).
@immutable
class DeviceAddress {
  /// The raw platform identifier. Opaque — never parse.
  final String value;

  const DeviceAddress(this.value);

  /// A short form for display/logging only (first 8 chars).
  String toShortString() =>
      value.length <= 8 ? value : value.substring(0, 8);

  @override
  bool operator ==(Object other) =>
      other is DeviceAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
