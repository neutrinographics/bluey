import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../lifecycle.dart' as lifecycle;

/// Server-side lifecycle management.
///
/// Handles the control service (heartbeat monitoring, interval reads) and
/// detects client disconnection via heartbeat timeouts. Internal to the
/// GATT Server bounded context.
class LifecycleServer {
  final platform.BlueyPlatform _platform;
  final Duration? _interval;
  final void Function(String clientId) onClientGone;
  final void Function(String clientId)? onHeartbeatReceived;

  bool _controlServiceAdded = false;
  final Map<String, Timer> _heartbeatTimers = {};

  LifecycleServer({
    required platform.BlueyPlatform platformApi,
    required Duration? interval,
    required this.onClientGone,
    this.onHeartbeatReceived,
  })  : _platform = platformApi,
        _interval = interval;

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
    if (!lifecycle.isControlServiceCharacteristic(req.characteristicUuid)) {
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

  /// Cancels the heartbeat timer for a specific client.
  void cancelTimer(String clientId) {
    _heartbeatTimers[clientId]?.cancel();
    _heartbeatTimers.remove(clientId);
  }

  /// Cancels all heartbeat timers and cleans up.
  void dispose() {
    for (final timer in _heartbeatTimers.values) {
      timer.cancel();
    }
    _heartbeatTimers.clear();
  }

  void _resetTimer(String clientId) {
    final interval = _interval;
    if (interval == null) return;

    _heartbeatTimers[clientId]?.cancel();
    _heartbeatTimers[clientId] = Timer(interval, () {
      _heartbeatTimers.remove(clientId);
      onClientGone(clientId);
    });
  }
}
