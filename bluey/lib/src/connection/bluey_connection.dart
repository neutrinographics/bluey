import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import '../peer/server_id.dart';
import '../shared/characteristic_properties.dart';
import '../shared/exceptions.dart';
import '../shared/uuid.dart';
import 'connection.dart';
import 'lifecycle_client.dart';

/// Runs a GATT op through the error-translation pipeline. Catches the
/// internal platform-interface exceptions and rethrows them as the
/// user-facing [BlueyException] sealed hierarchy:
///
///   * [platform.GattOperationTimeoutException] → [GattTimeoutException]
///   * [platform.GattOperationDisconnectedException] →
///     [DisconnectedException] with [DisconnectReason.linkLoss]
///   * [platform.GattOperationStatusFailedException] →
///     [GattOperationFailedException] carrying the native status
///
/// The platform-interface types stay internal: only [LifecycleClient] (an
/// internal collaborator) catches them directly. Public callers see only
/// [BlueyException] subtypes, so they can pattern-match exhaustively.
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on platform.GattOperationTimeoutException {
    throw GattTimeoutException(operation);
  } on platform.GattOperationDisconnectedException {
    throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
  } on platform.GattOperationStatusFailedException catch (e) {
    throw GattOperationFailedException(operation, e.status);
  }
}

/// Internal implementation of [Connection] that wraps platform calls.
///
/// This class is created by [Bluey.connect] and should not be instantiated
/// directly by users.
class BlueyConnection implements Connection {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final int _maxFailedHeartbeats;

  /// The platform-level connection identifier.
  ///
  /// Exposed for internal use by [LifecycleClient] and peer orchestration.
  /// Not part of the public [Connection] interface.
  String get connectionId => _connectionId;

  @override
  final UUID deviceId;

  LifecycleClient? _lifecycle;
  ServerId? _serverId;

  @override
  bool get isBlueyServer => _lifecycle != null;

  @override
  ServerId? get serverId => _serverId;

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
  StreamSubscription? _serviceChangeSubscription;
  bool _upgrading = false;

  // Cached services after discovery
  List<BlueyRemoteService>? _cachedServices;

  /// Creates a new connection instance.
  ///
  /// This is called internally by Bluey and should not be used directly.
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
    int maxFailedHeartbeats = 1,
  }) : _platform = platformInstance,
       _connectionId = connectionId,
       _maxFailedHeartbeats = maxFailedHeartbeats {
    // Subscribe to platform connection state changes
    _platformStateSubscription = _platform
        .connectionStateStream(_connectionId)
        .listen(
          (platformState) {
            _state = _mapConnectionState(platformState);
            dev.log(
              'state transition: → $_state',
              name: 'bluey.connection',
            );
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

    // Subscribe to service changes for late upgrade
    _serviceChangeSubscription = _platform.serviceChanges
        .where((deviceId) => deviceId == _connectionId)
        .listen((_) {
          dev.log(
            'Service Changed received: deviceId=$deviceId',
            name: 'bluey.gatt',
          );
          _handleServiceChange();
        });
  }

  /// Upgrades this connection to use the Bluey lifecycle protocol.
  ///
  /// Called internally when the control service is discovered during
  /// auto-upgrade or peer connect. Sets [isBlueyServer] to true and
  /// enables service filtering and lifecycle disconnect commands.
  ///
  /// Not part of the public [Connection] interface.
  void upgrade({
    required LifecycleClient lifecycleClient,
    required ServerId serverId,
  }) {
    _lifecycle = lifecycleClient;
    _serverId = serverId;
    _cachedServices = null; // invalidate so next services() call filters
    dev.log(
      'state transition: → ${ConnectionState.connected}',
      name: 'bluey.connection',
    );
    _stateController.add(ConnectionState.connected);
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  int get mtu => _mtu;

  @override
  RemoteService service(UUID uuid) {
    if (isBlueyServer && lifecycle.isControlService(uuid.toString())) {
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

    dev.log(
      'services start: deviceId=$deviceId',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );
    final stopwatch = Stopwatch()..start();
    final platformServices = await _runGattOp(
      deviceId,
      'discoverServices',
      () => _platform.discoverServices(_connectionId),
    );
    final allServices = platformServices.map((ps) => _mapService(ps)).toList();

    if (isBlueyServer) {
      _cachedServices =
          allServices
              .where((s) => !lifecycle.isControlService(s.uuid.toString()))
              .toList();
    } else {
      // Check if the control service appeared (e.g., server finished
      // initializing after we connected). If so, upgrade in place.
      await _tryUpgrade(allServices);
      _cachedServices =
          isBlueyServer
              ? allServices
                  .where((s) => !lifecycle.isControlService(s.uuid.toString()))
                  .toList()
              : allServices;
    }

    dev.log(
      'services complete: deviceId=$deviceId, count=${_cachedServices!.length}, ${stopwatch.elapsedMilliseconds}ms',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );

    return _cachedServices!;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    if (isBlueyServer && lifecycle.isControlService(uuid.toString())) {
      return false;
    }
    final svcs = await services(cache: true);
    return svcs.any((s) => s.uuid == uuid);
  }

  @override
  Future<int> requestMtu(int mtu) async {
    dev.log(
      'requestMtu start: deviceId=$deviceId, requested=$mtu',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );
    final stopwatch = Stopwatch()..start();
    try {
      final negotiatedMtu = await _runGattOp(
        deviceId,
        'requestMtu',
        () => _platform.requestMtu(_connectionId, mtu),
      );
      _mtu = negotiatedMtu;
      dev.log(
        'requestMtu complete: deviceId=$deviceId, requested=$mtu, negotiated=$negotiatedMtu, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 500, // Level.FINE — per-op chatter; suppressed in default log views
      );
      return _mtu;
    } catch (e) {
      dev.log(
        'requestMtu failed: deviceId=$deviceId, requested=$mtu, exception=${e.runtimeType}, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 900, // Level.WARNING
        error: e,
      );
      rethrow;
    }
  }

  @override
  Future<int> readRssi() async {
    dev.log(
      'readRssi start: deviceId=$deviceId',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );
    final stopwatch = Stopwatch()..start();
    try {
      final rssi = await _runGattOp(
        deviceId,
        'readRssi',
        () => _platform.readRssi(_connectionId),
      );
      dev.log(
        'readRssi complete: deviceId=$deviceId, rssi=${rssi}dBm, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 500, // Level.FINE — per-op chatter; suppressed in default log views
      );
      return rssi;
    } catch (e) {
      dev.log(
        'readRssi failed: deviceId=$deviceId, exception=${e.runtimeType}, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 900, // Level.WARNING
        error: e,
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    // Idempotent: if already disconnected or disconnecting, do nothing
    if (_state == ConnectionState.disconnected ||
        _state == ConnectionState.disconnecting) {
      return;
    }

    _state = ConnectionState.disconnecting;
    dev.log(
      'state transition: → $_state',
      name: 'bluey.connection',
    );
    _stateController.add(_state);

    // Send lifecycle disconnect command if upgraded to Bluey protocol.
    if (_lifecycle != null) {
      await _lifecycle!.sendDisconnectCommand();
      _lifecycle!.stop();
    }

    await _platform.disconnect(_connectionId);

    _state = ConnectionState.disconnected;
    dev.log(
      'state transition: → $_state',
      name: 'bluey.connection',
    );
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

  /// Handles a service change notification by re-discovering services
  /// and upgrading to the Bluey protocol if the control service appeared.
  Future<void> _handleServiceChange() async {
    if (isBlueyServer || _upgrading) return;
    _upgrading = true;
    try {
      _cachedServices = null;
      final allServices = await services();
      await _tryUpgrade(allServices);
    } catch (_) {
      // Service discovery failed -- stay as raw connection
    } finally {
      _upgrading = false;
    }
  }

  /// Checks whether [allServices] contains the Bluey control service.
  /// If so, reads the ServerId, starts the lifecycle heartbeat, and
  /// upgrades this connection in place. No-op if already upgraded.
  Future<void> _tryUpgrade(List<RemoteService> allServices) async {
    if (isBlueyServer) return;

    final controlService =
        allServices
            .where((s) => lifecycle.isControlService(s.uuid.toString()))
            .firstOrNull;
    if (controlService == null) return;

    // Read serverId if available
    final serverIdChar =
        controlService.characteristics
            .where(
              (c) =>
                  c.uuid.toString().toLowerCase() == lifecycle.serverIdCharUuid,
            )
            .firstOrNull;

    ServerId? serverId;
    if (serverIdChar != null) {
      try {
        final bytes = await serverIdChar.read();
        serverId = lifecycle.decodeServerId(bytes);
      } catch (_) {}
    }

    // Start lifecycle heartbeat
    final lifecycleClient = LifecycleClient(
      platformApi: _platform,
      connectionId: _connectionId,
      maxFailedHeartbeats: _maxFailedHeartbeats,
      onServerUnreachable: () {
        disconnect().catchError((_) {});
      },
    );
    lifecycleClient.start(allServices: allServices);

    upgrade(
      lifecycleClient: lifecycleClient,
      serverId: serverId ?? ServerId.generate(),
    );
  }

  /// Clean up resources.
  Future<void> _cleanup() async {
    _lifecycle?.stop();
    _lifecycle = null;
    await _serviceChangeSubscription?.cancel();
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
      deviceId: deviceId,
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
      deviceId: deviceId,
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
  final UUID _deviceId;

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
    required UUID deviceId,
    required this.uuid,
    required this.properties,
    required this.descriptors,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId;

  @override
  Future<Uint8List> read() async {
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    dev.log(
      'read start: deviceId=$_deviceId, char=$uuid',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );
    final stopwatch = Stopwatch()..start();
    try {
      final value = await _runGattOp(
        _deviceId,
        'readCharacteristic',
        () => _platform.readCharacteristic(_connectionId, uuid.toString()),
      );
      dev.log(
        'read complete: deviceId=$_deviceId, char=$uuid, bytes=${value.length}, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 500, // Level.FINE — per-op chatter; suppressed in default log views
      );
      return value;
    } catch (e) {
      final status = e is GattOperationFailedException ? ' status=${e.status}' : '';
      dev.log(
        'read failed: deviceId=$_deviceId, char=$uuid, exception=${e.runtimeType}$status, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 900, // Level.WARNING
        error: e,
      );
      rethrow;
    }
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    if (withResponse && !properties.canWrite) {
      throw const OperationNotSupportedException('write');
    }
    if (!withResponse && !properties.canWriteWithoutResponse) {
      throw const OperationNotSupportedException('writeWithoutResponse');
    }
    dev.log(
      'write start: deviceId=$_deviceId, char=$uuid, bytes=${value.length}',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );
    final stopwatch = Stopwatch()..start();
    try {
      await _runGattOp(
        _deviceId,
        'writeCharacteristic',
        () => _platform.writeCharacteristic(
          _connectionId,
          uuid.toString(),
          value,
          withResponse,
        ),
      );
      dev.log(
        'write complete: deviceId=$_deviceId, char=$uuid, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 500, // Level.FINE — per-op chatter; suppressed in default log views
      );
    } catch (e) {
      final status = e is GattOperationFailedException ? ' status=${e.status}' : '';
      dev.log(
        'write failed: deviceId=$_deviceId, char=$uuid, exception=${e.runtimeType}$status, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 900, // Level.WARNING
        error: e,
      );
      rethrow;
    }
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
    // Enable notifications on the platform. Fire-and-forget by design —
    // StreamController's onListen callback is synchronous. A platform
    // failure here (e.g. mid-op disconnect drained by the Android queue)
    // must surface on the notification stream so subscribers see it
    // instead of it becoming an unhandled async error.
    _runGattOp(
      _deviceId,
      'setNotification',
      () => _platform.setNotification(_connectionId, uuid.toString(), true),
    ).catchError((Object error) {
      _notificationController?.addError(error);
    });

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
    // Disable notifications on the platform. Fire-and-forget; the last
    // subscriber has just cancelled, so there is no natural recipient for
    // errors. Swallow silently to keep teardown best-effort — a link-loss
    // race on shutdown is an expected condition, not a test failure.
    _runGattOp(
      _deviceId,
      'setNotification',
      () => _platform.setNotification(_connectionId, uuid.toString(), false),
    ).catchError((Object _) {});

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
  final UUID _deviceId;

  @override
  final UUID uuid;

  BlueyRemoteDescriptor({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId;

  @override
  Future<Uint8List> read() async {
    return _runGattOp(
      _deviceId,
      'readDescriptor',
      () => _platform.readDescriptor(_connectionId, uuid.toString()),
    );
  }

  @override
  Future<void> write(Uint8List value) async {
    return _runGattOp(
      _deviceId,
      'writeDescriptor',
      () => _platform.writeDescriptor(_connectionId, uuid.toString(), value),
    );
  }
}
