import 'package:meta/meta.dart';

/// A BLE Maximum Transmission Unit (MTU): the largest ATT packet a link
/// carries.
///
/// An app builds one to ask for a larger MTU, and the link reports one as
/// what was negotiated. Only the range the Bluetooth specification allows
/// is checked here, so a value can be built before any connection exists.
@immutable
class Mtu {
  final int value;
  const Mtu._(this.value);

  /// Throws ArgumentError outside 23 to 517, the range the Bluetooth
  /// specification allows. Whether this platform can ask for the value is
  /// answered when the request is made.
  factory Mtu(int value) {
    if (value < _specMinimum) {
      throw ArgumentError('MTU must be >= 23 (BLE spec minimum): $value');
    }
    if (value > _specMaximum) {
      throw ArgumentError('MTU must be <= 517 (BLE spec maximum): $value');
    }
    return Mtu._(value);
  }

  /// What the platform reported, unchecked: the platform is authoritative
  /// about the MTU it negotiated.
  factory Mtu.fromPlatform(int value) => Mtu._(value);

  /// The minimum guaranteed across all platforms.
  static const Mtu minimum = Mtu._(_specMinimum);

  static const int _specMinimum = 23;
  static const int _specMaximum = 517;

  @override
  bool operator ==(Object other) => other is Mtu && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Mtu($value)';
}
