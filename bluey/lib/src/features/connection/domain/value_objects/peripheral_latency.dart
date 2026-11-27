import 'package:meta/meta.dart';

/// Peripheral latency, expressed as a number of connection events the
/// peripheral may skip when it has no data to send.
///
/// The BLE spec bounds this to the range 0–499. Higher values save power
/// at the peripheral but increase the latency of peripheral-initiated
/// communication.
@immutable
class PeripheralLatency {
  final int events;

  PeripheralLatency(this.events) {
    if (events < 0 || events > 499) {
      throw ArgumentError(
        'peripheral latency out of spec range (0-499 events): $events',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PeripheralLatency && other.events == events;

  @override
  int get hashCode => events.hashCode;

  @override
  String toString() => 'PeripheralLatency($events)';
}
