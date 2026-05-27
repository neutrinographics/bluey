import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

/// Minimal [platform.BlueyPlatform] for service-locator tests in the
/// example package.
///
/// Only the surface exercised by [Bluey.create] is implemented:
/// - [capabilities]
/// - [currentState]
/// - [stateStream]
/// - [logEvents]
/// - [setLogLevel]
///
/// Everything else throws [UnimplementedError] via [noSuchMethod].
base class FakeBlueyPlatformForExample extends platform.BlueyPlatform {
  FakeBlueyPlatformForExample() : super.impl();

  platform.BluetoothState _state = platform.BluetoothState.unknown;
  final StreamController<platform.BluetoothState> _stateController =
      StreamController<platform.BluetoothState>.broadcast();

  /// Set the Bluetooth state and push it onto [stateStream].
  void setState(platform.BluetoothState state) {
    _state = state;
    _stateController.add(state);
  }

  @override
  platform.Capabilities get capabilities => platform.Capabilities.android;

  @override
  platform.BluetoothState get currentState => _state;

  @override
  Stream<platform.BluetoothState> get stateStream => _stateController.stream;

  @override
  Stream<platform.PlatformLogEvent> get logEvents => const Stream.empty();

  @override
  Future<void> setLogLevel(platform.PlatformLogLevel level) async {}

  @override
  Future<void> configure(platform.BlueyConfig config) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'FakeBlueyPlatformForExample: '
        '${invocation.memberName} not implemented',
      );
}
