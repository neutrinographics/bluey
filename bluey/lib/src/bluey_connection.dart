import 'dart:async';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'connection.dart';
import 'connection_state.dart';
import 'exceptions.dart';
import 'gatt.dart';
import 'uuid.dart';

/// Internal implementation of [Connection] that wraps platform calls.
///
/// This class is created by [Bluey.connect] and should not be instantiated
/// directly by users.
class BlueyConnection implements Connection {
  final platform.BlueyPlatform _platform;
  final String _connectionId;

  @override
  final UUID deviceId;

  ConnectionState _state = ConnectionState.connecting;
  int _mtu = 23; // Default BLE MTU

  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();

  StreamSubscription? _platformStateSubscription;

  /// Creates a new connection instance.
  ///
  /// This is called internally by Bluey and should not be used directly.
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
  })  : _platform = platformInstance,
        _connectionId = connectionId {
    // Subscribe to platform connection state changes
    _platformStateSubscription =
        _platform.connectionStateStream(_connectionId).listen(
      (platformState) {
        _state = _mapConnectionState(platformState);
        _stateController.add(_state);
      },
      onError: (error) {
        _stateController.addError(error);
      },
    );
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  int get mtu => _mtu;

  @override
  RemoteService service(UUID uuid) {
    // TODO: Implement when platform supports service discovery
    throw ServiceNotFoundException(uuid);
  }

  @override
  Future<List<RemoteService>> get services async {
    // TODO: Implement when platform supports service discovery
    return [];
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    final svcs = await services;
    return svcs.any((s) => s.uuid == uuid);
  }

  @override
  Future<int> requestMtu(int mtu) async {
    // TODO: Implement when platform supports MTU negotiation
    // For now, just pretend we got what we asked for (up to 512)
    _mtu = mtu > 512 ? 512 : mtu;
    return _mtu;
  }

  @override
  Future<int> readRssi() async {
    // TODO: Implement when platform supports RSSI reading
    return -60; // Placeholder
  }

  @override
  Future<void> disconnect() async {
    _state = ConnectionState.disconnecting;
    _stateController.add(_state);

    await _platform.disconnect(_connectionId);

    _state = ConnectionState.disconnected;
    _stateController.add(_state);

    await _cleanup();
  }

  /// Clean up resources.
  Future<void> _cleanup() async {
    await _platformStateSubscription?.cancel();
    await _stateController.close();
  }

  ConnectionState _mapConnectionState(
      platform.PlatformConnectionState platformState) {
    switch (platformState) {
      case platform.PlatformConnectionState.disconnected:
        return ConnectionState.disconnected;
      case platform.PlatformConnectionState.connecting:
        return ConnectionState.connecting;
      case platform.PlatformConnectionState.connected:
        return ConnectionState.connected;
      case platform.PlatformConnectionState.disconnecting:
        return ConnectionState.disconnecting;
    }
  }
}
