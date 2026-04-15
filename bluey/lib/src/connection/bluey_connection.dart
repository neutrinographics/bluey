import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/characteristic_properties.dart';
import '../shared/exceptions.dart';
import '../shared/uuid.dart';
import 'connection.dart';
import 'connection_state.dart';
import 'lifecycle_client.dart';

/// Internal implementation of [Connection] that wraps platform calls.
///
/// This class is created by [Bluey.connect] and should not be instantiated
/// directly by users.
class BlueyConnection implements Connection {
  final platform.BlueyPlatform _platform;
  final String _connectionId;

  @override
  final UUID deviceId;

  ConnectionState _state =
      ConnectionState
          .connected; // Start as connected since we're created after successful connection
  int _mtu = 23; // Default BLE MTU
  BondState _bondState = BondState.none;
  Phy _txPhy = Phy.le1m;
  Phy _rxPhy = Phy.le1m;
  ConnectionParameters _connectionParameters = const ConnectionParameters(
    intervalMs: 30.0, // Default 30ms interval
    latency: 0,
    timeoutMs: 4000, // Default 4s timeout
  );

  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<BondState> _bondStateController =
      StreamController<BondState>.broadcast();
  final StreamController<({Phy tx, Phy rx})> _phyController =
      StreamController<({Phy tx, Phy rx})>.broadcast();

  StreamSubscription? _platformStateSubscription;
  StreamSubscription? _platformBondStateSubscription;
  StreamSubscription? _platformPhySubscription;

  // Cached services after discovery
  List<BlueyRemoteService>? _cachedServices;

  late final LifecycleClient _lifecycle;

  /// Creates a new connection instance.
  ///
  /// This is called internally by Bluey and should not be used directly.
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
    int maxFailedHeartbeats = 1,
  }) : _platform = platformInstance,
       _connectionId = connectionId {
    // Subscribe to platform connection state changes
    _platformStateSubscription = _platform
        .connectionStateStream(_connectionId)
        .listen(
          (platformState) {
            _state = _mapConnectionState(platformState);
            _stateController.add(_state);
          },
          onError: (error) {
            _stateController.addError(error);
          },
        );

    // Subscribe to platform bond state changes
    _platformBondStateSubscription = _platform
        .bondStateStream(_connectionId)
        .listen(
          (platformBondState) {
            _bondState = _mapBondState(platformBondState);
            _bondStateController.add(_bondState);
          },
          onError: (error) {
            _bondStateController.addError(error);
          },
        );

    // Initialize bond state
    _platform.getBondState(_connectionId).then((platformBondState) {
      _bondState = _mapBondState(platformBondState);
    });

    // Subscribe to platform PHY changes
    _platformPhySubscription = _platform
        .phyStream(_connectionId)
        .listen(
          (platformPhy) {
            _txPhy = _mapPhy(platformPhy.tx);
            _rxPhy = _mapPhy(platformPhy.rx);
            _phyController.add((tx: _txPhy, rx: _rxPhy));
          },
          onError: (error) {
            _phyController.addError(error);
          },
        );

    // Initialize PHY
    _platform.getPhy(_connectionId).then((platformPhy) {
      _txPhy = _mapPhy(platformPhy.tx);
      _rxPhy = _mapPhy(platformPhy.rx);
    });

    // Initialize connection parameters
    _platform.getConnectionParameters(_connectionId).then((params) {
      _connectionParameters = _mapConnectionParameters(params);
    });

    _lifecycle = LifecycleClient(
      platformApi: _platform,
      connectionId: _connectionId,
      maxFailedHeartbeats: maxFailedHeartbeats,
      onServerUnreachable: _handleServerUnreachable,
    );
  }

  void _handleServerUnreachable() {
    _state = ConnectionState.disconnected;
    _stateController.add(_state);
    _cleanup();
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  int get mtu => _mtu;

  @override
  RemoteService service(UUID uuid) {
    if (lifecycle.isControlService(uuid.toString())) {
      throw ServiceNotFoundException(uuid);
    }
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
  Future<List<RemoteService>> services({bool cache = false}) async {
    if (cache && _cachedServices != null) {
      return _cachedServices!;
    }

    final platformServices = await _platform.discoverServices(_connectionId);
    final allServices =
        platformServices.map((ps) => _mapService(ps)).toList();

    // Start lifecycle heartbeat if the server hosts the control service
    _lifecycle.start(allServices: allServices);

    // Filter the control service from the public result
    _cachedServices = allServices
        .where((s) => !lifecycle.isControlService(s.uuid.toString()))
        .toList();
    return _cachedServices!;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    if (lifecycle.isControlService(uuid.toString())) return false;
    final svcs = await services(cache: true);
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
    // Idempotent: if already disconnected or disconnecting, do nothing
    if (_state == ConnectionState.disconnected ||
        _state == ConnectionState.disconnecting) {
      return;
    }

    _state = ConnectionState.disconnecting;
    _stateController.add(_state);

    // Send disconnect command to the server's control service so it can
    // clean up immediately. Best-effort — the connection may already be lost.
    await _lifecycle.sendDisconnectCommand();

    await _platform.disconnect(_connectionId);

    _state = ConnectionState.disconnected;
    _stateController.add(_state);

    await _cleanup();
  }

  // === Bonding ===

  @override
  BondState get bondState => _bondState;

  @override
  Stream<BondState> get bondStateChanges => _bondStateController.stream;

  @override
  Future<void> bond() async {
    await _platform.bond(_connectionId);
  }

  @override
  Future<void> removeBond() async {
    await _platform.removeBond(_connectionId);
  }

  // === PHY ===

  @override
  Phy get txPhy => _txPhy;

  @override
  Phy get rxPhy => _rxPhy;

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => _phyController.stream;

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) async {
    await _platform.requestPhy(
      _connectionId,
      txPhy != null ? _mapPhyToPlatform(txPhy) : null,
      rxPhy != null ? _mapPhyToPlatform(rxPhy) : null,
    );
  }

  // === Connection Parameters ===

  @override
  ConnectionParameters get connectionParameters => _connectionParameters;

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) async {
    await _platform.requestConnectionParameters(
      _connectionId,
      platform.PlatformConnectionParameters(
        intervalMs: params.intervalMs,
        latency: params.latency,
        timeoutMs: params.timeoutMs,
      ),
    );
    _connectionParameters = params;
  }

  /// Clean up resources.
  Future<void> _cleanup() async {
    _lifecycle.stop();
    await _platformStateSubscription?.cancel();
    await _platformBondStateSubscription?.cancel();
    await _platformPhySubscription?.cancel();
    await _stateController.close();
    await _bondStateController.close();
    await _phyController.close();
    _cachedServices = null;
  }

  ConnectionState _mapConnectionState(
    platform.PlatformConnectionState platformState,
  ) {
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

  BondState _mapBondState(platform.PlatformBondState platformBondState) {
    switch (platformBondState) {
      case platform.PlatformBondState.none:
        return BondState.none;
      case platform.PlatformBondState.bonding:
        return BondState.bonding;
      case platform.PlatformBondState.bonded:
        return BondState.bonded;
    }
  }

  Phy _mapPhy(platform.PlatformPhy platformPhy) {
    switch (platformPhy) {
      case platform.PlatformPhy.le1m:
        return Phy.le1m;
      case platform.PlatformPhy.le2m:
        return Phy.le2m;
      case platform.PlatformPhy.leCoded:
        return Phy.leCoded;
    }
  }

  platform.PlatformPhy _mapPhyToPlatform(Phy phy) {
    switch (phy) {
      case Phy.le1m:
        return platform.PlatformPhy.le1m;
      case Phy.le2m:
        return platform.PlatformPhy.le2m;
      case Phy.leCoded:
        return platform.PlatformPhy.leCoded;
    }
  }

  ConnectionParameters _mapConnectionParameters(
    platform.PlatformConnectionParameters params,
  ) {
    return ConnectionParameters(
      intervalMs: params.intervalMs,
      latency: params.latency,
      timeoutMs: params.timeoutMs,
    );
  }

  BlueyRemoteService _mapService(platform.PlatformService ps) {
    return BlueyRemoteService(
      platform: _platform,
      connectionId: _connectionId,
      uuid: UUID(ps.uuid),
      isPrimary: ps.isPrimary,
      characteristics:
          ps.characteristics.map((pc) => _mapCharacteristic(pc)).toList(),
      includedServices:
          ps.includedServices.map((is_) => _mapService(is_)).toList(),
    );
  }

  BlueyRemoteCharacteristic _mapCharacteristic(
    platform.PlatformCharacteristic pc,
  ) {
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
  final bool isPrimary;

  @override
  final List<RemoteCharacteristic> characteristics;

  @override
  final List<RemoteService> includedServices;

  BlueyRemoteService({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required this.uuid,
    required this.isPrimary,
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
  }) : _platform = platform,
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
        .where(
          (n) =>
              n.characteristicUuid.toLowerCase() ==
              uuid.toString().toLowerCase(),
        )
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
  }) : _platform = platform,
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
