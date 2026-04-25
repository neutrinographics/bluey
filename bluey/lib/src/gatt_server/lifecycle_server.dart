import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../lifecycle.dart' as lifecycle;
import '../peer/server_id.dart';

/// Server-side lifecycle management.
///
/// Handles the control service (heartbeat monitoring, interval reads) and
/// detects client disconnection via heartbeat timeouts. Internal to the
/// GATT Server bounded context.
class LifecycleServer {
  final platform.BlueyPlatform _platform;
  final Duration? _interval;
  final ServerId _serverId;
  final void Function(String clientId) onClientGone;
  final void Function(String clientId)? onHeartbeatReceived;

  bool _controlServiceAdded = false;
  final Map<String, _ClientLiveness> _clients = {};

  LifecycleServer({
    required platform.BlueyPlatform platformApi,
    required Duration? interval,
    required ServerId serverId,
    required this.onClientGone,
    this.onHeartbeatReceived,
  })  : _platform = platformApi,
        _interval = interval,
        _serverId = serverId;

  /// Whether lifecycle management is enabled (interval is non-null).
  bool get isEnabled => _interval != null;

  /// Adds the control service to the platform if lifecycle is enabled
  /// and it hasn't been added yet.
  Future<void> addControlServiceIfNeeded() async {
    if (_interval == null || _controlServiceAdded) return;
    await _platform.addService(lifecycle.buildControlService());
    _controlServiceAdded = true;
  }

  /// Handles a write request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleWriteRequest(platform.PlatformWriteRequest req) {
    if (!lifecycle.isControlServiceCharacteristic(req.characteristicUuid)) {
      return false;
    }

    // Auto-respond if the platform requires it
    if (req.responseNeeded) {
      _platform.respondToWriteRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
      );
    }

    final clientId = req.centralId;

    // Notify that we have a live client sending a control-service write.
    // This fires for BOTH heartbeats and disconnect commands so that a
    // disconnect from an un-tracked client still tracks them first (so the
    // disconnection event has a client to remove).
    onHeartbeatReceived?.call(clientId);

    if (req.value.isNotEmpty && req.value[0] == lifecycle.disconnectValue[0]) {
      // Client is disconnecting cleanly
      cancelTimer(clientId);
      onClientGone(clientId);
    } else {
      // Heartbeat — reset the timer
      _resetTimer(clientId);
    }

    return true;
  }

  /// Handles a read request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleReadRequest(platform.PlatformReadRequest req) {
    final uuid = req.characteristicUuid.toLowerCase();

    if (uuid == lifecycle.serverIdCharUuid) {
      _platform.respondToReadRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
        lifecycle.encodeServerId(_serverId),
      );
      return true;
    }

    if (!lifecycle.isControlServiceCharacteristic(uuid)) {
      return false;
    }

    final interval = _interval ?? lifecycle.defaultLifecycleInterval;
    _platform.respondToReadRequest(
      req.requestId,
      platform.PlatformGattStatus.success,
      lifecycle.encodeInterval(interval),
    );

    return true;
  }

  /// Cancels the heartbeat timer for a specific client and clears any
  /// pending-request state. Removes the client entirely from tracking.
  void cancelTimer(String clientId) {
    _clients.remove(clientId)?.timer?.cancel();
  }

  /// Treats any incoming activity from [clientId] as liveness evidence,
  /// refreshing an existing per-client timer so a busy lifecycle client
  /// isn't disconnected while its user-service traffic keeps flowing.
  ///
  /// Only clients that have previously identified themselves via a
  /// heartbeat write are tracked — activity from a non-lifecycle
  /// central (e.g. a generic BLE app reading a hosted service) is
  /// ignored so we don't spuriously fire [onClientGone] for a client
  /// we never promised to track.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void recordActivity(String clientId) {
    if (_interval == null) return;
    if (!_clients.containsKey(clientId)) return;
    _resetTimer(clientId);
  }

  /// Cancels all heartbeat timers and clears all per-client state.
  void dispose() {
    for (final state in _clients.values) {
      state.timer?.cancel();
    }
    _clients.clear();
  }

  void _resetTimer(String clientId) {
    final interval = _interval;
    if (interval == null) return;

    final state = _clients.putIfAbsent(clientId, _ClientLiveness.new);
    state.timer?.cancel();

    if (state.pendingRequests.isNotEmpty) {
      // Paused while pending — see _ClientLiveness doc.
      state.timer = null;
      return;
    }

    state.timer = Timer(interval, () {
      _clients.remove(clientId);
      onClientGone(clientId);
    });
  }
}

/// Per-client liveness state: a (possibly paused) heartbeat-timeout timer
/// and the set of platform request IDs currently pending a server response.
///
/// While [pendingRequests] is non-empty, [timer] is null (paused) — the
/// client is demonstrably engaged with the server and must not be declared
/// gone. Map-key membership in `_clients` is the unambiguous "tracked"
/// signal.
class _ClientLiveness {
  Timer? timer;
  final Set<int> pendingRequests = {};
}
