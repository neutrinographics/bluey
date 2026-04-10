import 'package:flutter/foundation.dart';

import 'uuid.dart';

/// Base class for all Bluey diagnostic events.
///
/// Events provide visibility into what's happening inside Bluey,
/// useful for debugging and monitoring BLE operations.
@immutable
sealed class BlueyEvent {
  /// Timestamp when this event occurred.
  final DateTime timestamp;

  /// Optional source component that generated this event.
  final String? source;

  const BlueyEvent({DateTime? timestamp, this.source})
    : timestamp = timestamp ?? const _Now();

  @override
  String toString() => '[$runtimeType] ${_formatTime(timestamp)}';

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}

// Helper class for default timestamp
class _Now implements DateTime {
  const _Now();

  DateTime get _now => DateTime.now();

  @override
  int get year => _now.year;
  @override
  int get month => _now.month;
  @override
  int get day => _now.day;
  @override
  int get hour => _now.hour;
  @override
  int get minute => _now.minute;
  @override
  int get second => _now.second;
  @override
  int get millisecond => _now.millisecond;
  @override
  int get microsecond => _now.microsecond;
  @override
  int get weekday => _now.weekday;
  @override
  bool get isUtc => _now.isUtc;
  @override
  String get timeZoneName => _now.timeZoneName;
  @override
  Duration get timeZoneOffset => _now.timeZoneOffset;
  @override
  int get millisecondsSinceEpoch => _now.millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => _now.microsecondsSinceEpoch;

  @override
  DateTime add(Duration duration) => _now.add(duration);
  @override
  DateTime subtract(Duration duration) => _now.subtract(duration);
  @override
  Duration difference(DateTime other) => _now.difference(other);
  @override
  bool isAfter(DateTime other) => _now.isAfter(other);
  @override
  bool isBefore(DateTime other) => _now.isBefore(other);
  @override
  bool isAtSameMomentAs(DateTime other) => _now.isAtSameMomentAs(other);
  @override
  int compareTo(DateTime other) => _now.compareTo(other);
  @override
  DateTime toLocal() => _now.toLocal();
  @override
  DateTime toUtc() => _now.toUtc();
  @override
  String toIso8601String() => _now.toIso8601String();
  @override
  String toString() => _now.toString();
}

// === Scan Events ===

/// Scan started.
final class ScanStartedEvent extends BlueyEvent {
  final List<UUID>? serviceFilter;
  final Duration? timeout;

  const ScanStartedEvent({this.serviceFilter, this.timeout, super.source});

  @override
  String toString() {
    final filter =
        serviceFilter?.isNotEmpty == true
            ? ' filter=${serviceFilter!.map((u) => u.toShortString()).join(', ')}'
            : '';
    final to = timeout != null ? ' timeout=${timeout!.inSeconds}s' : '';
    return '[Scan] Started$filter$to';
  }
}

/// Device discovered during scan.
final class DeviceDiscoveredEvent extends BlueyEvent {
  final UUID deviceId;
  final String? name;
  final int? rssi;

  const DeviceDiscoveredEvent({
    required this.deviceId,
    this.name,
    this.rssi,
    super.source,
  });

  @override
  String toString() {
    final n = name != null ? ' "$name"' : '';
    final r = rssi != null ? ' rssi=$rssi' : '';
    return '[Scan] Discovered ${deviceId.toShortString()}$n$r';
  }
}

/// Scan stopped.
final class ScanStoppedEvent extends BlueyEvent {
  final String? reason;

  const ScanStoppedEvent({this.reason, super.source});

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    return '[Scan] Stopped$r';
  }
}

// === Connection Events ===

/// Connection attempt started.
final class ConnectingEvent extends BlueyEvent {
  final UUID deviceId;

  const ConnectingEvent({required this.deviceId, super.source});

  @override
  String toString() => '[Connection] Connecting to ${deviceId.toShortString()}';
}

/// Connection established.
final class ConnectedEvent extends BlueyEvent {
  final UUID deviceId;

  const ConnectedEvent({required this.deviceId, super.source});

  @override
  String toString() => '[Connection] Connected to ${deviceId.toShortString()}';
}

/// Disconnection occurred.
final class DisconnectedEvent extends BlueyEvent {
  final UUID deviceId;
  final String? reason;

  const DisconnectedEvent({required this.deviceId, this.reason, super.source});

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    return '[Connection] Disconnected from ${deviceId.toShortString()}$r';
  }
}

// === GATT Events ===

/// Service discovery started.
final class DiscoveringServicesEvent extends BlueyEvent {
  final UUID deviceId;

  const DiscoveringServicesEvent({required this.deviceId, super.source});

  @override
  String toString() =>
      '[GATT] Discovering services on ${deviceId.toShortString()}';
}

/// Services discovered.
final class ServicesDiscoveredEvent extends BlueyEvent {
  final UUID deviceId;
  final int serviceCount;

  const ServicesDiscoveredEvent({
    required this.deviceId,
    required this.serviceCount,
    super.source,
  });

  @override
  String toString() =>
      '[GATT] Discovered $serviceCount services on ${deviceId.toShortString()}';
}

/// Characteristic read.
final class CharacteristicReadEvent extends BlueyEvent {
  final UUID deviceId;
  final UUID characteristicId;
  final int valueLength;

  const CharacteristicReadEvent({
    required this.deviceId,
    required this.characteristicId,
    required this.valueLength,
    super.source,
  });

  @override
  String toString() =>
      '[GATT] Read ${characteristicId.toShortString()} ($valueLength bytes)';
}

/// Characteristic written.
final class CharacteristicWrittenEvent extends BlueyEvent {
  final UUID deviceId;
  final UUID characteristicId;
  final int valueLength;
  final bool withResponse;

  const CharacteristicWrittenEvent({
    required this.deviceId,
    required this.characteristicId,
    required this.valueLength,
    required this.withResponse,
    super.source,
  });

  @override
  String toString() {
    final type = withResponse ? 'Write' : 'WriteNoResponse';
    return '[GATT] $type ${characteristicId.toShortString()} ($valueLength bytes)';
  }
}

/// Notification received.
final class NotificationReceivedEvent extends BlueyEvent {
  final UUID deviceId;
  final UUID characteristicId;
  final int valueLength;

  const NotificationReceivedEvent({
    required this.deviceId,
    required this.characteristicId,
    required this.valueLength,
    super.source,
  });

  @override
  String toString() =>
      '[GATT] Notification from ${characteristicId.toShortString()} ($valueLength bytes)';
}

/// Notification subscription changed.
final class NotificationSubscriptionEvent extends BlueyEvent {
  final UUID deviceId;
  final UUID characteristicId;
  final bool enabled;

  const NotificationSubscriptionEvent({
    required this.deviceId,
    required this.characteristicId,
    required this.enabled,
    super.source,
  });

  @override
  String toString() {
    final action = enabled ? 'Subscribed to' : 'Unsubscribed from';
    return '[GATT] $action ${characteristicId.toShortString()}';
  }
}

// === Server (Peripheral) Events ===

/// Server started.
final class ServerStartedEvent extends BlueyEvent {
  const ServerStartedEvent({super.source});

  @override
  String toString() => '[Server] Started';
}

/// Service added to server.
final class ServiceAddedEvent extends BlueyEvent {
  final UUID serviceId;

  const ServiceAddedEvent({required this.serviceId, super.source});

  @override
  String toString() => '[Server] Added service ${serviceId.toShortString()}';
}

/// Advertising started.
final class AdvertisingStartedEvent extends BlueyEvent {
  final String? name;
  final List<UUID>? services;

  const AdvertisingStartedEvent({this.name, this.services, super.source});

  @override
  String toString() {
    final n = name != null ? ' as "$name"' : '';
    return '[Server] Advertising started$n';
  }
}

/// Advertising stopped.
final class AdvertisingStoppedEvent extends BlueyEvent {
  const AdvertisingStoppedEvent({super.source});

  @override
  String toString() => '[Server] Advertising stopped';
}

/// Client connected to server.
final class ClientConnectedEvent extends BlueyEvent {
  final String clientId;
  final int? mtu;

  const ClientConnectedEvent({
    required this.clientId,
    this.mtu,
    super.source,
  });

  @override
  String toString() {
    final m = mtu != null ? ' mtu=$mtu' : '';
    return '[Server] Client connected: ${_shortId(clientId)}$m';
  }

  String _shortId(String id) {
    if (id.length > 8) {
      return '${id.substring(0, 8)}...';
    }
    return id;
  }
}

/// Client disconnected from server.
final class ClientDisconnectedEvent extends BlueyEvent {
  final String clientId;

  const ClientDisconnectedEvent({required this.clientId, super.source});

  @override
  String toString() => '[Server] Client disconnected: ${_shortId(clientId)}';

  String _shortId(String id) {
    if (id.length > 8) {
      return '${id.substring(0, 8)}...';
    }
    return id;
  }
}

/// Read request received from client.
final class ReadRequestEvent extends BlueyEvent {
  final String clientId;
  final UUID characteristicId;

  const ReadRequestEvent({
    required this.clientId,
    required this.characteristicId,
    super.source,
  });

  @override
  String toString() =>
      '[Server] Read request for ${characteristicId.toShortString()}';
}

/// Write request received from client.
final class WriteRequestEvent extends BlueyEvent {
  final String clientId;
  final UUID characteristicId;
  final int valueLength;

  const WriteRequestEvent({
    required this.clientId,
    required this.characteristicId,
    required this.valueLength,
    super.source,
  });

  @override
  String toString() =>
      '[Server] Write request for ${characteristicId.toShortString()} ($valueLength bytes)';
}

/// Notification sent to client(s).
final class NotificationSentEvent extends BlueyEvent {
  final UUID characteristicId;
  final int valueLength;
  final String? clientId; // null means broadcast to all

  const NotificationSentEvent({
    required this.characteristicId,
    required this.valueLength,
    this.clientId,
    super.source,
  });

  @override
  String toString() {
    final target = clientId != null ? ' to ${_shortId(clientId!)}' : '';
    return '[Server] Sent notification$target ($valueLength bytes)';
  }

  String _shortId(String id) {
    if (id.length > 8) {
      return '${id.substring(0, 8)}...';
    }
    return id;
  }
}

/// Indication sent to client(s).
///
/// Indications are like notifications but require acknowledgment from the client.
final class IndicationSentEvent extends BlueyEvent {
  final UUID characteristicId;
  final int valueLength;
  final String? clientId; // null means broadcast to all

  const IndicationSentEvent({
    required this.characteristicId,
    required this.valueLength,
    this.clientId,
    super.source,
  });

  @override
  String toString() {
    final target = clientId != null ? ' to ${_shortId(clientId!)}' : '';
    return '[Server] Sent indication$target ($valueLength bytes)';
  }

  String _shortId(String id) {
    if (id.length > 8) {
      return '${id.substring(0, 8)}...';
    }
    return id;
  }
}

// === Error Events ===

/// An error occurred.
final class ErrorEvent extends BlueyEvent {
  final String message;
  final Object? error;

  const ErrorEvent({required this.message, this.error, super.source});

  @override
  String toString() => '[Error] $message';
}

// === Debug Events ===

/// Generic debug event for tracing.
final class DebugEvent extends BlueyEvent {
  final String message;

  const DebugEvent({required this.message, super.source});

  @override
  String toString() => '[Debug] $message';
}
