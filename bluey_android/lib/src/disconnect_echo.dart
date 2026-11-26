import 'package:bluey_platform_interface/bluey_platform_interface.dart';

/// Recognises the Android plugin's echo of a local disconnect request, so it
/// can be dropped before it reaches a device's listeners.
///
/// The plugin reports every disconnect request as a `disconnecting` state,
/// even one it then fails (I397). The app already knows it asked, so the echo
/// would only make a link whose close failed look as if the radio were
/// closing it.
class DisconnectEcho {
  final Set<String> _expected = {};

  /// Records that a disconnect of [deviceId] was asked, so its echo is
  /// recognised.
  void expectFor(String deviceId) {
    _expected.add(deviceId);
  }

  /// Whether [state] is the echo of a disconnect asked of [deviceId]. An echo
  /// is recognised once, and a `disconnected` report means none is coming.
  bool isEcho(String deviceId, PlatformConnectionState state) {
    if (state == PlatformConnectionState.disconnected) {
      _expected.remove(deviceId);
    }
    return state == PlatformConnectionState.disconnecting &&
        _expected.remove(deviceId);
  }
}
