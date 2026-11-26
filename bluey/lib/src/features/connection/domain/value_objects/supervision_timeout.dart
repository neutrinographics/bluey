import 'package:meta/meta.dart';

/// BLE link supervision timeout, in milliseconds.
///
/// The time after which a connection is considered lost if no valid packet
/// has been received. The BLE spec bounds this to the range 100–32000 ms.
/// To remain valid alongside a [ConnectionInterval] and [PeripheralLatency],
/// the timeout must strictly exceed `(1 + latency) * interval`; that
/// cross-field invariant is enforced on `ConnectionParameters`.
@immutable
class SupervisionTimeout {
  final int milliseconds;

  SupervisionTimeout(this.milliseconds) {
    if (milliseconds < 100 || milliseconds > 32000) {
      throw ArgumentError(
        'supervision timeout out of spec range (100-32000 ms): $milliseconds',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SupervisionTimeout && other.milliseconds == milliseconds;

  @override
  int get hashCode => milliseconds.hashCode;

  @override
  String toString() => 'SupervisionTimeout(${milliseconds}ms)';
}
