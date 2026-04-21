import 'dart:async';
// ignore_for_file: avoid_print
// [DIAG:lifecycle-force-kill] Temporary diagnostic prints for investigating
// why iOS client doesn't detect an Android server force-kill. Revert once
// the root cause is identified.

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

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
    if (_heartbeatCharUuid != null) {
      print('[DIAG:lifecycle] start: already running, skipping');
      return;
    }
    print(
      '[DIAG:lifecycle] start: ${allServices.length} services discovered: '
      '${allServices.map((s) => s.uuid.toString()).join(', ')}',
    );

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) {
      print(
        '[DIAG:lifecycle] start: NO CONTROL SERVICE — heartbeat disabled. '
        'Expected ${lifecycle.controlServiceUuid}',
      );
      return;
    }

    final heartbeatChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) {
      print('[DIAG:lifecycle] start: control service has no heartbeat char');
      return;
    }

    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    print('[DIAG:lifecycle] start: heartbeat char found, firing initial send');

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
    print('[DIAG:lifecycle] beginHeartbeat: interval=${interval.inMilliseconds}ms');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    print('[DIAG:lifecycle] heartbeat →');
    _platform
        .writeCharacteristic(
          _connectionId,
          charUuid,
          lifecycle.heartbeatValue,
          true,
        )
        .then((_) {
      print('[DIAG:lifecycle] heartbeat ack');
      _consecutiveFailures = 0;
    }).catchError((Object error) {
      print(
        '[DIAG:lifecycle] heartbeat error: '
        '${error.runtimeType}: $error',
      );
      // Only timeouts indicate the remote peer is unreachable. Other errors
      // (e.g. a transient "operation in flight" rejection on Android, or a
      // missing characteristic from a stale GATT cache after Service Changed)
      // are not evidence of absence and must not trip the failure counter.
      if (error is! platform.GattOperationTimeoutException) {
        print('[DIAG:lifecycle] error NOT counted (non-timeout)');
        return;
      }
      _consecutiveFailures++;
      print(
        '[DIAG:lifecycle] timeout counted: $_consecutiveFailures/'
        '$maxFailedHeartbeats',
      );
      if (_consecutiveFailures >= maxFailedHeartbeats) {
        print('[DIAG:lifecycle] TRIPPED → onServerUnreachable');
        stop();
        onServerUnreachable();
      }
    });
  }
}
