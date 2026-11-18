import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

/// Owns each connected device's state and notification streams, so one place
/// decides when they open and close.
///
/// A stream handed out stays attached across a second connect to the same
/// device, and both streams end on the device's terminal `disconnected`
/// report, so a listener is never left waiting on a stream nobody feeds.
class DeviceStreams {
  final Map<String, StreamController<PlatformConnectionState>> _states = {};
  final Map<String, StreamController<PlatformNotification>> _notifications = {};

  /// Makes the device's streams live, keeping any that already are, and
  /// answers whether it created them, so a caller whose connect fails closes
  /// only streams it opened and never those an earlier link handed out.
  ///
  /// A reused pair still belongs to the device, not to this caller: a
  /// `disconnected` report that arrives while the caller is reconnecting
  /// ends it, and the reconnected link then has no streams.
  bool open(String deviceId) {
    if (_states.containsKey(deviceId)) return false;
    _states[deviceId] = StreamController<PlatformConnectionState>.broadcast();
    _notifications[deviceId] =
        StreamController<PlatformNotification>.broadcast();
    return true;
  }

  /// Ends the device's streams and forgets them; safe when it has none.
  Future<void> close(String deviceId) async {
    final states = _states.remove(deviceId);
    final notifications = _notifications.remove(deviceId);
    await states?.close();
    await notifications?.close();
  }

  /// The device's connection states, or a stream that fails with a
  /// [StateError] when the device has no live streams.
  Stream<PlatformConnectionState> statesOf(String deviceId) =>
      _states[deviceId]?.stream ?? _notConnected(deviceId);

  /// The device's notifications, or a stream that fails with a [StateError]
  /// when the device has no live streams.
  Stream<PlatformNotification> notificationsOf(String deviceId) =>
      _notifications[deviceId]?.stream ?? _notConnected(deviceId);

  /// Delivers a state to the device's listeners. A `disconnected` state is
  /// the device's last event: once it is delivered both streams end.
  void reportState(String deviceId, PlatformConnectionState state) {
    final controller = _states[deviceId];
    if (controller == null) return;
    controller.add(state);
    if (state == PlatformConnectionState.disconnected) {
      unawaited(close(deviceId));
    }
  }

  /// Delivers a notification to the device's listeners; dropped when the
  /// device has no live streams.
  void reportNotification(String deviceId, PlatformNotification notification) {
    _notifications[deviceId]?.add(notification);
  }

  Stream<T> _notConnected<T>(String deviceId) =>
      Stream.error(StateError('Device not connected: $deviceId'));
}
