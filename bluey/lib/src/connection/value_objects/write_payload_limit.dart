import 'package:meta/meta.dart';

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

  /// Bypasses validation. Use only for values reported by the platform —
  /// the platform is authoritative about the negotiated payload limit.
  factory WritePayloadLimit.fromPlatform(int value) =>
      WritePayloadLimit._(value);

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
