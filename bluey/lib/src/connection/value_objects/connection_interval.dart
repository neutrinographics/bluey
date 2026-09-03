import 'package:meta/meta.dart';

/// A BLE connection interval, in milliseconds.
///
/// The connection interval is the time between two consecutive connection
/// events. The BLE spec bounds it to the range 7.5–4000 ms. Smaller values
/// reduce latency at the cost of higher power consumption; larger values
/// save power but slow down both directions of GATT traffic.
@immutable
class ConnectionInterval {
  final double milliseconds;

  /// The BLE-spec floor (7.5 ms): no two connection events can be closer,
  /// so nothing can cross the link faster than this.
  static const Duration specMinimum = Duration(microseconds: 7500);

  /// The BLE-spec ceiling (4 s).
  static const Duration specMaximum = Duration(seconds: 4);

  ConnectionInterval(this.milliseconds) {
    if (milliseconds < specMinimum.inMicroseconds / 1000 ||
        milliseconds > specMaximum.inMicroseconds / 1000) {
      throw ArgumentError(
        'connection interval out of spec range (7.5-4000 ms): $milliseconds',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionInterval && other.milliseconds == milliseconds;

  @override
  int get hashCode => milliseconds.hashCode;

  @override
  String toString() => 'ConnectionInterval(${milliseconds}ms)';
}
