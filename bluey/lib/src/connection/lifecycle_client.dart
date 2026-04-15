import 'dart:async';

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
  /// control service).
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
    }).catchError((_) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxFailedHeartbeats) {
        stop();
        onServerUnreachable();
      }
    });
  }
}
