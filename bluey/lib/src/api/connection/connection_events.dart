import '../../shared/domain/bluey_event.dart';
import '../../shared/domain/device_address.dart';

/// A connect to [deviceAddress] began, so an app watching `bluey.events` can
/// show the attempt before it succeeds or fails.
final class ConnectingEvent extends BlueyEvent {
  final DeviceAddress deviceAddress;

  ConnectingEvent({required this.deviceAddress, super.source, super.timestamp});

  @override
  String toString() =>
      '[Connection] Connecting to ${deviceAddress.toShortString()}';
}

/// The link to [deviceAddress] is open: it follows a [ConnectingEvent] for
/// the same device only when the connect succeeded.
final class ConnectedEvent extends BlueyEvent {
  final DeviceAddress deviceAddress;

  ConnectedEvent({required this.deviceAddress, super.source, super.timestamp});

  @override
  String toString() =>
      '[Connection] Connected to ${deviceAddress.toShortString()}';
}

/// The link to [deviceAddress] ended, with the [reason] in words when one is
/// known, so an app can tell a disconnect it asked for from a lost link.
final class DisconnectedEvent extends BlueyEvent {
  final DeviceAddress deviceAddress;
  final String? reason;

  DisconnectedEvent({
    required this.deviceAddress,
    this.reason,
    super.source,
    super.timestamp,
  });

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    return '[Connection] Disconnected from ${deviceAddress.toShortString()}$r';
  }
}
