import 'dart:async';
import 'dart:typed_data';

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;

/// A function that writes to a characteristic.
typedef WriteCharacteristicFn = Future<void> Function(
  String characteristicUuid,
  Uint8List value,
  bool withResponse,
);

/// A function that reads from a characteristic.
typedef ReadCharacteristicFn = Future<Uint8List> Function(
  String characteristicUuid,
);

/// Client-side lifecycle management.
///
/// Discovers the server's control service, sends periodic heartbeats,
/// and detects server disconnection via write failures. Internal to the
/// Connection bounded context.
class LifecycleClient {
  final int maxFailedHeartbeats;
  final void Function() onServerUnreachable;

  Timer? _heartbeatTimer;
  String? _heartbeatCharUuid;
  WriteCharacteristicFn? _writeFn;
  int _consecutiveFailures = 0;

  LifecycleClient({
    this.maxFailedHeartbeats = 1,
    required this.onServerUnreachable,
  });

  /// Whether the lifecycle heartbeat is currently running.
  bool get isRunning => _heartbeatTimer != null;

  /// Returns true if the given UUID is the control service.
  static bool isControlService(String uuid) {
    return lifecycle.isControlService(uuid);
  }

  /// Filters the control service from a list of services.
  static List<T> filterControlServices<T extends RemoteService>(
    List<T> services,
  ) {
    return services
        .where((s) => !lifecycle.isControlService(s.uuid.toString()))
        .toList();
  }

  /// Starts the heartbeat if the server hosts the control service.
  ///
  /// [allServices] is the full list of discovered services (including the
  /// control service). [writeFn] and [readFn] are used to communicate with
  /// the server's control service characteristics.
  void start({
    required List<RemoteService> allServices,
    required WriteCharacteristicFn writeFn,
    required ReadCharacteristicFn readFn,
  }) {
    if (_heartbeatTimer != null) return;

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
    _writeFn = writeFn;

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
      readFn(intervalChar.uuid.toString()).then((bytes) {
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
    final writeFn = _writeFn;
    if (charUuid == null || writeFn == null) return;

    try {
      await writeFn(charUuid, lifecycle.disconnectValue, false);
    } catch (_) {
      // Best effort — connection may already be lost
    }
  }

  /// Stops the heartbeat and cleans up.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatCharUuid = null;
    _writeFn = null;
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
    _sendHeartbeat();
  }

  void _sendHeartbeat() {
    final charUuid = _heartbeatCharUuid;
    final writeFn = _writeFn;
    if (charUuid == null || writeFn == null) return;

    writeFn(charUuid, lifecycle.heartbeatValue, false).then((_) {
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
