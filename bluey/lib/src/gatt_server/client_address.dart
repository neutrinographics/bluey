import 'package:meta/meta.dart';

/// Opaque, platform-assigned address of a remote BLE **central that connected
/// inbound to our local `Server`** — the *inbound* direction, in which the
/// local role is GATT **server** and the remote is the GATT client.
///
/// Sourced at the GATT-server seam from `PlatformCentral.id` / `centralId`:
/// the MAC address on Android, the `CBCentral.identifier` UUID string on iOS.
/// The format is platform-specific and opaque — never parse it.
///
/// This is the value emitted on `Server.disconnections` and carried by the
/// server-side events, so it is the stable key for bridging the
/// `peerConnections` and `disconnections` streams (this is the fix for I337).
///
/// Mirror of `DeviceAddress`, which addresses a remote peripheral we
/// discovered/connected to *outbound*.
@immutable
class ClientAddress {
  /// The raw platform identifier. Opaque — never parse.
  final String value;

  const ClientAddress(this.value);

  /// A short form for display/logging only (first 8 chars).
  String toShortString() =>
      value.length <= 8 ? value : value.substring(0, 8);

  @override
  bool operator ==(Object other) =>
      other is ClientAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
