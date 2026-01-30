import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'characteristic_properties.dart';
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

  // Cached services after discovery
  List<BlueyRemoteService>? _cachedServices;

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
    if (_cachedServices == null) {
      throw ServiceNotFoundException(uuid);
    }

    for (final svc in _cachedServices!) {
      if (svc.uuid == uuid) {
        return svc;
      }
    }

    throw ServiceNotFoundException(uuid);
  }

  @override
  Future<List<RemoteService>> get services async {
    if (_cachedServices != null) {
      return _cachedServices!;
    }

    final platformServices = await _platform.discoverServices(_connectionId);
    _cachedServices = platformServices.map((ps) => _mapService(ps)).toList();
    return _cachedServices!;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    final svcs = await services;
    return svcs.any((s) => s.uuid == uuid);
  }

  @override
  Future<int> requestMtu(int mtu) async {
    final negotiatedMtu = await _platform.requestMtu(_connectionId, mtu);
    _mtu = negotiatedMtu;
    return _mtu;
  }

  @override
  Future<int> readRssi() async {
    return await _platform.readRssi(_connectionId);
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
    _cachedServices = null;
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

  BlueyRemoteService _mapService(platform.PlatformService ps) {
    return BlueyRemoteService(
      platform: _platform,
      connectionId: _connectionId,
      uuid: UUID(ps.uuid),
      characteristics:
          ps.characteristics.map((pc) => _mapCharacteristic(pc)).toList(),
      includedServices:
          ps.includedServices.map((is_) => _mapService(is_)).toList(),
    );
  }

  BlueyRemoteCharacteristic _mapCharacteristic(
      platform.PlatformCharacteristic pc) {
    return BlueyRemoteCharacteristic(
      platform: _platform,
      connectionId: _connectionId,
      uuid: UUID(pc.uuid),
      properties: CharacteristicProperties(
        canRead: pc.properties.canRead,
        canWrite: pc.properties.canWrite,
        canWriteWithoutResponse: pc.properties.canWriteWithoutResponse,
        canNotify: pc.properties.canNotify,
        canIndicate: pc.properties.canIndicate,
      ),
      descriptors: pc.descriptors.map((pd) => _mapDescriptor(pd)).toList(),
    );
  }

  BlueyRemoteDescriptor _mapDescriptor(platform.PlatformDescriptor pd) {
    return BlueyRemoteDescriptor(
      platform: _platform,
      connectionId: _connectionId,
      uuid: UUID(pd.uuid),
    );
  }
}

/// Internal implementation of [RemoteService].
class BlueyRemoteService implements RemoteService {
  @override
  final UUID uuid;

  @override
  final List<RemoteCharacteristic> characteristics;

  @override
  final List<RemoteService> includedServices;

  BlueyRemoteService({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required this.uuid,
    required this.characteristics,
    required this.includedServices,
  });

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    for (final char in characteristics) {
      if (char.uuid == uuid) {
        return char;
      }
    }
    throw CharacteristicNotFoundException(uuid);
  }
}

/// Internal implementation of [RemoteCharacteristic].
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _connectionId;

  @override
  final UUID uuid;

  @override
  final CharacteristicProperties properties;

  @override
  final List<RemoteDescriptor> descriptors;

  StreamSubscription? _notificationSubscription;
  StreamController<Uint8List>? _notificationController;

  BlueyRemoteCharacteristic({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required this.uuid,
    required this.properties,
    required this.descriptors,
  })  : _platform = platform,
        _connectionId = connectionId;

  @override
  Future<Uint8List> read() async {
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    return await _platform.readCharacteristic(_connectionId, uuid.toString());
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    if (withResponse && !properties.canWrite) {
      throw const OperationNotSupportedException('write');
    }
    if (!withResponse && !properties.canWriteWithoutResponse) {
      throw const OperationNotSupportedException('writeWithoutResponse');
    }
    await _platform.writeCharacteristic(
      _connectionId,
      uuid.toString(),
      value,
      withResponse,
    );
  }

  @override
  Stream<Uint8List> get notifications {
    if (!properties.canSubscribe) {
      throw const OperationNotSupportedException('notify');
    }

    // Create a new controller if needed
    if (_notificationController == null) {
      _notificationController = StreamController<Uint8List>.broadcast(
        onListen: _onFirstListen,
        onCancel: _onLastCancel,
      );
    }

    return _notificationController!.stream;
  }

  void _onFirstListen() {
    // Enable notifications on the platform
    _platform.setNotification(_connectionId, uuid.toString(), true);

    // Subscribe to platform notifications
    _notificationSubscription = _platform
        .notificationStream(_connectionId)
        .where((n) =>
            n.characteristicUuid.toLowerCase() == uuid.toString().toLowerCase())
        .listen(
      (notification) {
        _notificationController?.add(notification.value);
      },
      onError: (error) {
        _notificationController?.addError(error);
      },
    );
  }

  void _onLastCancel() {
    // Disable notifications on the platform
    _platform.setNotification(_connectionId, uuid.toString(), false);

    // Cancel subscription
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  @override
  RemoteDescriptor descriptor(UUID uuid) {
    for (final desc in descriptors) {
      if (desc.uuid == uuid) {
        return desc;
      }
    }
    throw CharacteristicNotFoundException(uuid);
  }
}

/// Internal implementation of [RemoteDescriptor].
class BlueyRemoteDescriptor implements RemoteDescriptor {
  final platform.BlueyPlatform _platform;
  final String _connectionId;

  @override
  final UUID uuid;

  BlueyRemoteDescriptor({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required this.uuid,
  })  : _platform = platform,
        _connectionId = connectionId;

  @override
  Future<Uint8List> read() async {
    return await _platform.readDescriptor(_connectionId, uuid.toString());
  }

  @override
  Future<void> write(Uint8List value) async {
    await _platform.writeDescriptor(_connectionId, uuid.toString(), value);
  }
}
