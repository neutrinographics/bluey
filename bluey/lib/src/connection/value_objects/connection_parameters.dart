import 'package:meta/meta.dart';

import 'connection_interval.dart';
import 'peripheral_latency.dart';
import 'supervision_timeout.dart';

/// BLE connection parameters: the timing triple that governs every
/// connection event on a link.
///
/// Combines [ConnectionInterval], [PeripheralLatency], and
/// [SupervisionTimeout] and enforces the cross-field invariant that the
/// supervision timeout must strictly exceed `(1 + latency) * interval`
/// (otherwise the link would be torn down before the peripheral has had
/// the chance to skip its allowed events).
@immutable
class ConnectionParameters {
  final ConnectionInterval interval;
  final PeripheralLatency latency;
  final SupervisionTimeout timeout;

  ConnectionParameters({
    required this.interval,
    required this.latency,
    required this.timeout,
  }) {
    final minTimeout = (1 + latency.events) * interval.milliseconds;
    if (timeout.milliseconds <= minTimeout) {
      throw ArgumentError(
        'supervision timeout must exceed (1 + latency) * interval '
        '($minTimeout ms); got ${timeout.milliseconds} ms',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionParameters &&
      other.interval == interval &&
      other.latency == latency &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(interval, latency, timeout);

  @override
  String toString() =>
      'ConnectionParameters(interval: $interval, latency: $latency, timeout: $timeout)';
}
