import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:meta/meta.dart';

/// A negotiated BLE Maximum Transmission Unit (MTU).
///
/// Wraps a positive integer in the BLE-spec range (>= 23) and bounded above
/// by the platform's [Capabilities.maxMtu]. The wire-level type stays `int`;
/// this value object exists purely on the Dart domain side to enforce the
/// spec minimum and platform-specific maximum at construction time.
@immutable
class Mtu {
  final int value;
  const Mtu._(this.value);

  /// Constructs an [Mtu], validating against the BLE-spec minimum (23) and
  /// the platform-specific maximum reported by [capabilities].
  factory Mtu(int value, {required Capabilities capabilities}) {
    if (value < 23) {
      throw ArgumentError('MTU must be >= 23 (BLE spec minimum): $value');
    }
    if (value > capabilities.maxMtu) {
      throw ArgumentError(
        'MTU $value exceeds platform maximum ${capabilities.maxMtu}',
      );
    }
    return Mtu._(value);
  }

  /// Bypasses validation. Use only for values read back from the platform —
  /// the platform is authoritative about negotiated MTU.
  factory Mtu.fromPlatform(int value) => Mtu._(value);

  /// The minimum guaranteed across all platforms.
  static const Mtu minimum = Mtu._(23);

  @override
  bool operator ==(Object other) => other is Mtu && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Mtu($value)';
}
