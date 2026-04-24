import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import 'liveness_monitor.dart';

/// Client-side lifecycle management.
///
/// Owns the GATT write mechanism (deadline-scheduled Timer + heartbeat
/// char write).
/// Delegates all liveness policy decisions to an internal [LivenessMonitor]:
/// when to send a probe, when failures count, when to tear down.
///
/// Internal to the Connection bounded context.
class LifecycleClient {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final int _maxFailedHeartbeats;
  final void Function() onServerUnreachable;

  late LivenessMonitor _monitor;
  Timer? _probeTimer;
  String? _heartbeatCharUuid;

  LifecycleClient({
    required platform.BlueyPlatform platformApi,
    required String connectionId,
    int maxFailedHeartbeats = 1,
    required this.onServerUnreachable,
  })  : _platform = platformApi,
        _connectionId = connectionId,
        _maxFailedHeartbeats = maxFailedHeartbeats {
    _monitor = LivenessMonitor(
      maxFailedProbes: maxFailedHeartbeats,
      activityWindow: _defaultHeartbeatInterval,
    );
  }

  /// Also exposed for [BlueyConnection] tests to inspect: public for
  /// consistency with the rest of the Connection bounded context.
  int get maxFailedHeartbeats => _maxFailedHeartbeats;

  /// Whether the heartbeat timer is currently running.
  bool get isRunning => _probeTimer != null;

  /// Forwarded from [BlueyConnection] on any successful GATT op or
  /// incoming notification. Treats the peer as demonstrably alive and
  /// shifts the probe deadline forward by [_monitor.activityWindow].
  /// No-op if the lifecycle isn't running — prevents lingering
  /// notification subscriptions from dirtying monitor state after
  /// [stop] has been called.
  void recordActivity() {
    if (!isRunning) return;
    _monitor.recordActivity();
    // Deadline shifted — supersede the pending timer.
    _scheduleProbe();
  }

  /// Starts the heartbeat if the server hosts the control service.
  ///
  /// [allServices] is the full list of discovered services. If the
  /// control service or its heartbeat characteristic is absent, the
  /// method returns silently without starting heartbeats.
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

    // Send the first heartbeat immediately so the server (especially
    // iOS, which has no connection callback) learns about this client
    // as soon as possible — before the interval read round-trip.
    _sendProbe();

    // Find the interval characteristic and read the server's interval.
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

  /// Stops the heartbeat timer and clears the char reference. The
  /// monitor keeps its accumulated state, but [recordActivity] and
  /// [_scheduleProbe] both check [isRunning] / [_heartbeatCharUuid] so
  /// no further state mutation is possible after stop.
  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
  }

  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    dev.log('heartbeat interval set: ${interval.inMilliseconds}ms', name: 'bluey.lifecycle');
    // Update the monitor in place so a probe in flight from the initial
    // synchronous send keeps its markProbeInFlight flag intact.
    _monitor.updateActivityWindow(interval);
    _scheduleProbe();
  }

  /// Cancel any pending scheduled probe and schedule a new one.
  ///
  /// If [after] is null (default), the delay is computed from the
  /// monitor's current deadline — appropriate after a probe success or
  /// after external [recordActivity] shifts the deadline forward.
  ///
  /// If [after] is non-null, the delay is that explicit duration —
  /// appropriate after a probe failure, where the monitor's deadline
  /// would already have elapsed (producing an immediate-retry cadence
  /// that diverges from the original polling behaviour). Failure paths
  /// pass [_monitor.activityWindow] to preserve the roughly-one-probe-
  /// per-window rate-limit that polling produced implicitly.
  ///
  /// No-op if the client has been stopped.
  void _scheduleProbe({Duration? after}) {
    if (_heartbeatCharUuid == null) return;
    _probeTimer?.cancel();
    final delay = after ?? _monitor.timeUntilNextProbe();
    _probeTimer = Timer(delay, _sendProbeOrDefer);
  }

  /// Timer callback. Sends a probe unless one is already in flight
  /// (in which case the in-flight probe's completion handler will
  /// reschedule). Re-verifies the deadline in case [recordActivity]
  /// raced the timer firing — if activity just shifted the deadline
  /// forward, reschedule instead of probing now.
  void _sendProbeOrDefer() {
    if (_heartbeatCharUuid == null) return;
    if (_monitor.probeInFlight) return;
    if (_monitor.timeUntilNextProbe() > Duration.zero) {
      _scheduleProbe();
      return;
    }
    _sendProbe();
  }

  void _sendProbe() {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    _monitor.markProbeInFlight();
    _platform
        .writeCharacteristic(
          _connectionId,
          charUuid,
          lifecycle.heartbeatValue,
          true,
        )
        .then((_) {
      _monitor.recordProbeSuccess();
      // Success refreshed lastActivity → monitor deadline is now
      // exactly activityWindow from now. No explicit override.
      _scheduleProbe();
    }).catchError((Object error) {
      if (!_isDeadPeerSignal(error)) {
        // Transient platform error — release in-flight, retry after a
        // full activityWindow (the monitor deadline has already elapsed
        // by the time we got here, so without the explicit delay we'd
        // hammer the peer with immediate retries).
        _monitor.cancelProbe();
        _scheduleProbe(after: _monitor.activityWindow);
        return;
      }
      final tripped = _monitor.recordProbeFailure();
      dev.log(
        'heartbeat failed (counted): ${error.runtimeType}',
        name: 'bluey.lifecycle',
        level: 900, // WARNING
      );
      if (tripped) {
        dev.log(
          'heartbeat threshold reached — invoking onServerUnreachable',
          name: 'bluey.lifecycle',
          level: 1000, // SEVERE
        );
        stop();
        onServerUnreachable();
        // No reschedule — connection is tearing down.
        return;
      }
      // Under-threshold dead-peer signal: retry one activityWindow later
      // (same rate-limit as the transient path).
      _scheduleProbe(after: _monitor.activityWindow);
    });
  }

  /// Whether [error] is evidence that the peer is no longer reachable.
  ///
  /// Treated as dead-peer signals:
  ///
  /// * [platform.GattOperationTimeoutException] — the peer stopped
  ///   acknowledging within the per-op timeout.
  /// * [platform.GattOperationDisconnectedException] — drained on link
  ///   drop. iOS maps `BlueyError.notFound` / `notConnected` through
  ///   `gatt-disconnected` to this exception so the translation below
  ///   is unchanged from Android's behaviour.
  /// * [platform.GattOperationStatusFailedException] — Android-client→
  ///   iOS-server force-kill path: iOS fires a Service Changed
  ///   indication on the way out, invalidating Android's cached handle;
  ///   every subsequent heartbeat write returns GATT_INVALID_HANDLE
  ///   (0x01). Also covers iOS client→iOS server ATT errors now that
  ///   `CBATTErrorDomain` NSErrors surface as typed.
  bool _isDeadPeerSignal(Object error) {
    if (error is platform.GattOperationTimeoutException) return true;
    if (error is platform.GattOperationDisconnectedException) return true;
    if (error is platform.GattOperationStatusFailedException) return true;
    return false;
  }
}
