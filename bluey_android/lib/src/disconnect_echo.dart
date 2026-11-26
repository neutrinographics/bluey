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
  /// is recognised once. Any other report means none is coming: a request
  /// that produced no echo must not swallow a later link's own
  /// `disconnecting`.
  bool isEcho(String deviceId, PlatformConnectionState state) {
    final wasExpected = _expected.remove(deviceId);
    return state == PlatformConnectionState.disconnecting && wasExpected;
  }
}
