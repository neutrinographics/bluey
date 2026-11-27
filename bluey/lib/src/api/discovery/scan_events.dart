import '../../shared/domain/bluey_event.dart';
import '../../shared/domain/device_address.dart';
import '../../shared/domain/uuid.dart';

/// Scan started.
final class ScanStartedEvent extends BlueyEvent {
  final List<UUID>? serviceFilter;
  final Duration? timeout;

  ScanStartedEvent({
    this.serviceFilter,
    this.timeout,
    super.timestamp,
    super.source,
  });

  @override
  String toString() =>
      '[Scan] Started${_filterOf(serviceFilter)}${_timeoutOf(timeout)}';
}

/// Emitted when [Scanner.scan] is called and the platform-side start
/// is now in flight. Followed by [ScanStartedEvent] when the platform
/// confirms (or a failure if the platform rejects).
final class ScanStartingEvent extends BlueyEvent {
  final List<UUID>? serviceFilter;
  final Duration? timeout;

  ScanStartingEvent({
    this.serviceFilter,
    this.timeout,
    super.timestamp,
    super.source,
  });

  @override
  String toString() =>
      '[Scan] Starting${_filterOf(serviceFilter)}${_timeoutOf(timeout)}';
}

/// Device discovered during scan.
final class DeviceDiscoveredEvent extends BlueyEvent {
  final DeviceAddress deviceAddress;
  final String? name;
  final int? rssi;

  DeviceDiscoveredEvent({
    required this.deviceAddress,
    this.name,
    this.rssi,
    super.timestamp,
    super.source,
  });

  @override
  String toString() {
    final n = name != null ? ' "$name"' : '';
    final r = rssi != null ? ' rssi=$rssi' : '';
    return '[Scan] Discovered ${deviceAddress.toShortString()}$n$r';
  }
}

/// Scan stopped.
final class ScanStoppedEvent extends BlueyEvent {
  final String? reason;

  ScanStoppedEvent({this.reason, super.timestamp, super.source});

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    return '[Scan] Stopped$r';
  }
}

/// Emitted when [Scanner.stop] is called (or the consumer cancelled
/// the subscription, or a timeout fired) and the platform-side stop
/// is now in flight. Followed by [ScanStoppedEvent] when the platform
/// confirms.
final class ScanStoppingEvent extends BlueyEvent {
  ScanStoppingEvent({super.timestamp, super.source});

  @override
  String toString() => '[Scan] Stopping';
}

String _filterOf(List<UUID>? serviceFilter) => switch (serviceFilter) {
  final services? when services.isNotEmpty =>
    ' filter=${services.map((u) => u.toShortString()).join(', ')}',
  _ => '',
};

String _timeoutOf(Duration? timeout) => switch (timeout) {
  final limit? => ' timeout=${limit.inSeconds}s',
  null => '',
};
