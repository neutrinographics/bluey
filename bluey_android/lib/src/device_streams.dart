import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

/// Owns each connected device's state and notification streams, so one place
/// decides when they open and close.
///
/// A device's streams belong to one link. A stream handed out stays attached
/// across a second connect to a device that is still linked, and both
/// streams end on the link's terminal `disconnected` report, so a listener
/// is never left waiting on a stream nobody feeds. The platforms name a link
/// by its device alone, so a signal about a link that has ended (the answer
/// to its disconnect, its last report) is kept with that link and never
/// touches the streams of the device's next link.
class DeviceStreams {
  final Map<String, _DeviceStreamPair> _pairs = {};
  final Set<String> _owedLastReport = {};
  final Set<String> _echoExpected = {};

  /// Makes the device's streams live, keeping any that already are, and
  /// answers whether it created them, so a caller whose connect fails closes
  /// only streams it opened and never those an earlier link handed out.
  bool open(String deviceId) {
    if (_pairs.containsKey(deviceId)) return false;
    _pairs[deviceId] = _DeviceStreamPair();
    return true;
  }

  /// Ends the device's streams and forgets them; safe when it has none.
  Future<void> close(String deviceId) async {
    await _pairs.remove(deviceId)?.close();
  }

  /// Asks the host to disconnect the device with [hostDisconnect], then ends
  /// the streams that were live when it was asked.
  ///
  /// The device may be linked again before the host answers, and that link's
  /// streams are left alone. When the answer ends streams whose
  /// `disconnected` report has not arrived, that report is still to come and
  /// is kept from the next link. A disconnect the host fails ends nothing.
  ///
  /// The next `disconnecting` report is not delivered: the Android plugin
  /// echoes every disconnect request as that state, even one it then fails,
  /// and the app already knows it asked, so the echo would only make a link
  /// whose close failed look as if the radio were closing it.
  Future<void> disconnect(
    String deviceId,
    Future<void> Function() hostDisconnect,
  ) async {
    final asked = _pairs[deviceId];
    _echoExpected.add(deviceId);
    await hostDisconnect();
    if (asked == null || !identical(_pairs[deviceId], asked)) return;
    _owedLastReport.add(deviceId);
    await close(deviceId);
  }

  /// The device's connection states, or a stream that fails with a
  /// [StateError] when the device has no live streams.
  Stream<PlatformConnectionState> statesOf(String deviceId) =>
      _pairs[deviceId]?.states.stream ?? _notConnected(deviceId);

  /// The device's notifications, or a stream that fails with a [StateError]
  /// when the device has no live streams.
  Stream<PlatformNotification> notificationsOf(String deviceId) =>
      _pairs[deviceId]?.notifications.stream ?? _notConnected(deviceId);

  /// Delivers a state to the device's listeners. A `disconnected` state is
  /// the link's last event: once it is delivered both streams end.
  ///
  /// The last report of a link whose disconnect was already answered is
  /// dropped, since it is about that link. Any other report is about the
  /// device's current link, and after one the ended link's last report is
  /// no longer expected, so a platform that never sends it costs nothing.
  void reportState(String deviceId, PlatformConnectionState state) {
    if (_isEcho(deviceId, state)) return;
    final owed = _owedLastReport.remove(deviceId);
    if (owed && state == PlatformConnectionState.disconnected) return;
    final pair = _pairs[deviceId];
    if (pair == null) return;
    pair.states.add(state);
    if (state == PlatformConnectionState.disconnected) {
      unawaited(close(deviceId));
    }
  }

  /// Whether [state] is the echo of a disconnect request, which also stops
  /// being expected once the link's `disconnected` report arrives.
  bool _isEcho(String deviceId, PlatformConnectionState state) {
    if (state == PlatformConnectionState.disconnected) {
      _echoExpected.remove(deviceId);
    }
    return state == PlatformConnectionState.disconnecting &&
        _echoExpected.remove(deviceId);
  }

  /// Delivers a notification to the device's listeners; dropped when the
  /// device has no live streams.
  void reportNotification(String deviceId, PlatformNotification notification) {
    _pairs[deviceId]?.notifications.add(notification);
  }

  Stream<T> _notConnected<T>(String deviceId) =>
      Stream.error(StateError('Device not connected: $deviceId'));
}

/// One link's state and notification streams, opened and ended together.
class _DeviceStreamPair {
  final states = StreamController<PlatformConnectionState>.broadcast();
  final notifications = StreamController<PlatformNotification>.broadcast();

  Future<void> close() async {
    await states.close();
    await notifications.close();
  }
}
