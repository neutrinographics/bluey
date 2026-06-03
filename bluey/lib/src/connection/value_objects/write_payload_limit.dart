import 'package:meta/meta.dart';

/// The Bluetooth Core Spec (Vol 3, Part F §3.2.9) caps the length of an
/// attribute value at **512 octets**, independent of the negotiated ATT MTU.
/// A central must not write a single value larger than this: spec-conforming
/// peripherals silently truncate the overflow (e.g. Android's fixed
/// `GATT_MAX_ATTR_LEN` receive buffer), and because a Write Command carries no
/// response the loss is invisible. iOS's
/// `maximumWriteValueLength(for: .withoutResponse)` reports `MTU - 3` *without*
/// applying this cap (514 @ MTU 517), so [WritePayloadLimit.fromPlatform]
/// clamps to it. See backlog I343.
const int maxAttributeValueLength = 512;

/// Largest single ATT write payload the platform will accept for a given
/// connection.
///
/// Wraps the platform-supplied byte count so consumers don't compute
/// chunk sizes from raw `Mtu - 3` arithmetic — particularly important on
/// iOS, where CoreBluetooth does not expose the GATT MTU and the only
/// honest source for "how big can I write?" is
/// `CBPeripheral.maximumWriteValueLength(for:)`.
///
/// Construct directly via [WritePayloadLimit.new] when validating user
/// input; use [WritePayloadLimit.fromPlatform] when wrapping a value the
/// platform reported (which is authoritative — no client-side validation
/// applies).
@immutable
class WritePayloadLimit {
  /// Constructs a [WritePayloadLimit], validating that [value] is positive.
  factory WritePayloadLimit(int value) {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'WritePayloadLimit must be positive',
      );
    }
    return WritePayloadLimit._(value);
  }

  /// Bypasses positive-value validation (the platform is authoritative about
  /// the negotiated payload limit), but enforces the spec's 512-octet
  /// attribute-value cap — see [maxAttributeValueLength] / I343. The clamp only
  /// lowers values above 512; platform "unavailable" sentinels (0, -1) and all
  /// sub-512 values pass through unchanged.
  factory WritePayloadLimit.fromPlatform(int value) => WritePayloadLimit._(
        value > maxAttributeValueLength ? maxAttributeValueLength : value,
      );

  const WritePayloadLimit._(this.value);

  /// The maximum number of bytes that fit in a single ATT write.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is WritePayloadLimit && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'WritePayloadLimit($value)';
}
