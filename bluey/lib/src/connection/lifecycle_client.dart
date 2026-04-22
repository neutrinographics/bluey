import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;

/// Client-side lifecycle management.
///
/// Discovers the server's control service, sends periodic heartbeats,
/// and detects server disconnection via write failures. Internal to the
/// Connection bounded context.
class LifecycleClient {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final int maxFailedHeartbeats;
  final void Function() onServerUnreachable;

  Timer? _heartbeatTimer;
  String? _heartbeatCharUuid;
  int _consecutiveFailures = 0;

  LifecycleClient({
    required platform.BlueyPlatform platformApi,
    required String connectionId,
    this.maxFailedHeartbeats = 1,
    required this.onServerUnreachable,
  }) : _platform = platformApi,
       _connectionId = connectionId;

  /// Whether the lifecycle heartbeat is currently running.
  bool get isRunning => _heartbeatTimer != null;

  /// Starts the heartbeat if the server hosts the control service.
  ///
  /// [allServices] is the full list of discovered services (including the
  /// control service). If the control service or its heartbeat characteristic
  /// is absent, the method returns silently without starting heartbeats.
  void start({required List<RemoteService> allServices}) {
    if (_heartbeatCharUuid != null) return;

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) return;

    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    dev.log('heartbeat started: char=$_heartbeatCharUuid', name: 'bluey.lifecycle');

    // Send the first heartbeat immediately so the server (especially iOS,
    // which has no connection callback) learns about this client as soon as
    // possible — before the interval read round-trip.
    _sendHeartbeat();

    // Find the interval characteristic and read the server's interval
    final intervalChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.intervalCharUuid,
        )
        .firstOrNull;

    if (intervalChar != null) {
      _platform
          .readCharacteristic(_connectionId, intervalChar.uuid.toString())
          .then((bytes) {
        final serverInterval = lifecycle.decodeInterval(bytes);
        final heartbeatInterval = Duration(
          milliseconds: serverInterval.inMilliseconds ~/ 2,
        );
        _beginHeartbeat(heartbeatInterval);
      }).catchError((_) {
        _beginHeartbeat(_defaultHeartbeatInterval);
      });
    } else {
      _beginHeartbeat(_defaultHeartbeatInterval);
    }
  }

  /// Sends a disconnect command to the server's control service.
  Future<void> sendDisconnectCommand() async {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    try {
      await _platform.writeCharacteristic(
        _connectionId,
        charUuid,
        lifecycle.disconnectValue,
        true,
      );
    } catch (_) {
      // Best effort — connection may already be lost
    }
  }

  /// Stops the heartbeat and cleans up.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatCharUuid = null;
    _consecutiveFailures = 0;
  }

  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    dev.log('heartbeat interval set: ${interval.inMilliseconds}ms', name: 'bluey.lifecycle');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    _platform
        .writeCharacteristic(
          _connectionId,
          charUuid,
          lifecycle.heartbeatValue,
          true,
        )
        .then((_) {
      _consecutiveFailures = 0;
    }).catchError((Object error) {
      if (!_isDeadPeerSignal(error)) {
        return;
      }
      _consecutiveFailures++;
      dev.log(
        'heartbeat failed (counted): $_consecutiveFailures/$maxFailedHeartbeats — ${error.runtimeType}',
        name: 'bluey.lifecycle',
        level: 900, // WARNING
      );
      if (_consecutiveFailures >= maxFailedHeartbeats) {
        dev.log(
          'heartbeat threshold reached — invoking onServerUnreachable',
          name: 'bluey.lifecycle',
          level: 1000, // SEVERE
        );
        stop();
        onServerUnreachable();
      }
    });
  }

  /// Whether [error] is evidence that the peer is no longer reachable.
  ///
  /// Treated as dead-peer signals:
  ///
  /// * [platform.GattOperationTimeoutException] — the peer stopped
  ///   acknowledging within the per-op timeout.
  /// * [platform.GattOperationDisconnectedException] — Android's GATT
  ///   queue drained the pending heartbeat when the link dropped.
  /// * [platform.GattOperationStatusFailedException] — the peer returned
  ///   a non-success GATT status. This is the Android-client→iOS-server
  ///   force-kill path: iOS fires a Service Changed indication on the way
  ///   out, which invalidates Android's cached characteristic handle, and
  ///   every subsequent heartbeat write returns GATT_INVALID_HANDLE
  ///   (0x01). The physical link stays up (iOS's BLE stack still answers
  ///   link-layer packets after the app dies), so without this branch we
  ///   would hold the connection open indefinitely.
  /// * [PlatformException] with code `notFound` or `notConnected` — iOS's
  ///   CoreBluetooth invalidates the peer's characteristic handles as
  ///   soon as the peer vanishes, long before `didDisconnect` fires. The
  ///   resulting `BlueyError.notFound` / `.notConnected` reaches Dart as
  ///   a raw [PlatformException] (it's not translated by
  ///   `_translateGattPlatformError`), so we match on the Pigeon error
  ///   code directly.
  ///
  /// Every other error is ignored — there was a time when transient
  /// "operation in flight" rejections on Android produced false positives;
  /// Phase 2a's GATT operation queue eliminates that class of error, but
  /// the safety net remains to guard against future unknowns.
  bool _isDeadPeerSignal(Object error) {
    if (error is platform.GattOperationTimeoutException) return true;
    if (error is platform.GattOperationDisconnectedException) return true;
    if (error is platform.GattOperationStatusFailedException) return true;
    if (error is PlatformException &&
        (error.code == 'notFound' || error.code == 'notConnected')) {
      return true;
    }
    return false;
  }
}
