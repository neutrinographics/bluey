import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import 'liveness_monitor.dart';

/// Client-side lifecycle management.
///
/// Owns the GATT write mechanism (Timer.periodic + heartbeat char write).
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
  /// incoming notification. Treats the peer as demonstrably alive.
  /// No-op if the lifecycle isn't running — prevents lingering
  /// notification subscriptions from dirtying monitor state after
  /// [stop] has been called.
  void recordActivity() {
    if (!isRunning) return;
    _monitor.recordActivity();
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
  /// [_tick] both check [isRunning] so no further state mutation is
  /// possible after stop.
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
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(interval, (_) => _tick());
  }

  void _tick() {
    if (!_monitor.shouldSendProbe()) return;
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
        .then((_) => _monitor.recordProbeSuccess())
        .catchError((Object error) {
      if (!_isDeadPeerSignal(error)) {
        // Not a dead-peer signal — release the in-flight flag so the
        // next tick can retry, but do NOT reset the failure counter or
        // refresh activity. The transient error gives no evidence about
        // whether the peer is alive.
        _monitor.cancelProbe();
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
      }
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
