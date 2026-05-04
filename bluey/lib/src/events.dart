import 'package:meta/meta.dart';

import 'shared/uuid.dart';

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

  BlueyEvent({DateTime? timestamp, this.source})
    : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$runtimeType] ${_formatTime(timestamp)}';

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}

/// Scan started.
final class ScanStartedEvent extends BlueyEvent {
  final List<UUID>? serviceFilter;
  final Duration? timeout;

  ScanStartedEvent({this.serviceFilter, this.timeout, super.source});

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

  DeviceDiscoveredEvent({
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

  ScanStoppedEvent({this.reason, super.source});

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    return '[Scan] Stopped$r';
  }
}

/// Connection attempt started.
final class ConnectingEvent extends BlueyEvent {
  final UUID deviceId;

  ConnectingEvent({required this.deviceId, super.source});

  @override
  String toString() => '[Connection] Connecting to ${deviceId.toShortString()}';
}

/// Connection established.
final class ConnectedEvent extends BlueyEvent {
  final UUID deviceId;

  ConnectedEvent({required this.deviceId, super.source});

  @override
  String toString() => '[Connection] Connected to ${deviceId.toShortString()}';
}

/// Disconnection occurred.
final class DisconnectedEvent extends BlueyEvent {
  final UUID deviceId;
  final String? reason;

  DisconnectedEvent({required this.deviceId, this.reason, super.source});

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    return '[Connection] Disconnected from ${deviceId.toShortString()}$r';
  }
}

/// Service discovery started.
final class DiscoveringServicesEvent extends BlueyEvent {
  final UUID deviceId;

  DiscoveringServicesEvent({required this.deviceId, super.source});

  @override
  String toString() =>
      '[GATT] Discovering services on ${deviceId.toShortString()}';
}

/// Services discovered.
final class ServicesDiscoveredEvent extends BlueyEvent {
  final UUID deviceId;
  final int serviceCount;

  ServicesDiscoveredEvent({
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

  CharacteristicReadEvent({
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

  CharacteristicWrittenEvent({
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

  NotificationReceivedEvent({
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

  NotificationSubscriptionEvent({
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

/// Server started.
final class ServerStartedEvent extends BlueyEvent {
  ServerStartedEvent({super.source});

  @override
  String toString() => '[Server] Started';
}

/// Service added to server.
final class ServiceAddedEvent extends BlueyEvent {
  final UUID serviceId;

  ServiceAddedEvent({required this.serviceId, super.source});

  @override
  String toString() => '[Server] Added service ${serviceId.toShortString()}';
}

/// Advertising started.
final class AdvertisingStartedEvent extends BlueyEvent {
  final String? name;
  final List<UUID>? services;

  AdvertisingStartedEvent({this.name, this.services, super.source});

  @override
  String toString() {
    final n = name != null ? ' as "$name"' : '';
    return '[Server] Advertising started$n';
  }
}

/// Advertising stopped.
final class AdvertisingStoppedEvent extends BlueyEvent {
  AdvertisingStoppedEvent({super.source});

  @override
  String toString() => '[Server] Advertising stopped';
}

/// Client connected to server.
final class ClientConnectedEvent extends BlueyEvent {
  final String clientId;
  final int? mtu;

  ClientConnectedEvent({required this.clientId, this.mtu, super.source});

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

  ClientDisconnectedEvent({required this.clientId, super.source});

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

  ReadRequestEvent({
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

  WriteRequestEvent({
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

  NotificationSentEvent({
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

  IndicationSentEvent({
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

// Bluey's lifecycle protocol — heartbeat write + dead-peer detection
// — is what distinguishes the library from a raw GATT pipe. Its
// state transitions are the highest-value diagnostic events for
// debugging "why did my peer disconnect?" and "why isn't my server
// noticing the client is gone?". These events surface the protocol's
// behaviour on `bluey.events` for programmatic consumption alongside
// the structured logs.

/// Heartbeat write was sent to the peer (client side).
final class HeartbeatSentEvent extends BlueyEvent {
  final UUID deviceId;

  HeartbeatSentEvent({required this.deviceId, super.source});

  @override
  String toString() =>
      '[Lifecycle] Heartbeat sent to ${deviceId.toShortString()}';
}

/// Heartbeat write was acknowledged by the peer (client side).
final class HeartbeatAcknowledgedEvent extends BlueyEvent {
  final UUID deviceId;

  HeartbeatAcknowledgedEvent({required this.deviceId, super.source});

  @override
  String toString() =>
      '[Lifecycle] Heartbeat ack from ${deviceId.toShortString()}';
}

/// Heartbeat write failed (client side). [isDeadPeerSignal] is `true`
/// when the failure type is one the silence detector counts toward
/// the dead-peer threshold (e.g. timeout, disconnected); `false` when
/// it's a transient error that does not move the silence clock.
final class HeartbeatFailedEvent extends BlueyEvent {
  final UUID deviceId;
  final bool isDeadPeerSignal;
  final String? reason;

  HeartbeatFailedEvent({
    required this.deviceId,
    required this.isDeadPeerSignal,
    this.reason,
    super.source,
  });

  @override
  String toString() {
    final r = reason != null ? ' ($reason)' : '';
    final sig = isDeadPeerSignal ? ' [counts]' : ' [transient]';
    return '[Lifecycle] Heartbeat failed to ${deviceId.toShortString()}$r$sig';
  }
}

/// The lifecycle silence detector tripped — peer has been quiet for
/// long enough that we treat it as gone (client side). Followed by a
/// local disconnect.
final class PeerDeclaredUnreachableEvent extends BlueyEvent {
  final UUID deviceId;

  PeerDeclaredUnreachableEvent({required this.deviceId, super.source});

  @override
  String toString() =>
      '[Lifecycle] Peer ${deviceId.toShortString()} declared unreachable';
}

/// Server-side: a heartbeat-silence threshold was reached and the
/// client is being declared gone. Distinct from
/// [ClientDisconnectedEvent] — the latter fires for any disconnect,
/// while this fires only when the lifecycle protocol detects silence.
final class ClientLifecycleTimeoutEvent extends BlueyEvent {
  final String clientId;

  ClientLifecycleTimeoutEvent({required this.clientId, super.source});

  @override
  String toString() =>
      '[Lifecycle] Client ${_shortId(clientId)} timed out (heartbeat silence)';

  String _shortId(String id) {
    if (id.length > 8) return '${id.substring(0, 8)}...';
    return id;
  }
}

/// Server-side: the lifecycle silence timer was paused because a
/// pending request from this client is in flight. The timer resumes
/// once the request is responded to or drained.
final class LifecyclePausedForPendingRequestEvent extends BlueyEvent {
  final String clientId;

  LifecyclePausedForPendingRequestEvent({required this.clientId, super.source});

  @override
  String toString() =>
      '[Lifecycle] Paused timer for ${_shortId(clientId)} (pending request)';

  String _shortId(String id) {
    if (id.length > 8) return '${id.substring(0, 8)}...';
    return id;
  }
}

/// An error occurred.
final class ErrorEvent extends BlueyEvent {
  final String message;
  final Object? error;

  ErrorEvent({required this.message, this.error, super.source});

  @override
  String toString() => '[Error] $message';
}

/// Generic debug event for tracing.
final class DebugEvent extends BlueyEvent {
  final String message;

  DebugEvent({required this.message, super.source});

  @override
  String toString() => '[Debug] $message';
}
