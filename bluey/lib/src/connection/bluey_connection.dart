import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;

import '../gatt_client/gatt.dart';
import '../shared/characteristic_properties.dart';
import '../shared/exceptions.dart';
import '../shared/uuid.dart';
import 'android_connection_extensions.dart';
import 'connection.dart';
import 'connection_parameters_mapper.dart';
import 'ios_connection_extensions.dart';
import 'lifecycle_client.dart';
import 'value_objects/attribute_handle.dart';

/// Runs a GATT op through the error-translation pipeline and routes
/// lifecycle signals into [lifecycleClient]. Used by every public GATT
/// op on [BlueyConnection] / [BlueyRemoteCharacteristic] /
/// [BlueyRemoteDescriptor] so user-op accounting and activity signals
/// flow uniformly through one place.
///
/// Lifecycle hooks (all no-ops if [lifecycleClient] is null):
///   * [LifecycleClient.markUserOpStarted] before [body] is awaited.
///   * [LifecycleClient.recordActivity] on success.
///   * [LifecycleClient.recordUserOpFailure] on any caught platform
///     exception, with the *original* (untranslated) exception so the
///     timeout predicate inside [LifecycleClient] can match it.
///   * [LifecycleClient.markUserOpEnded] in `finally`.
///
/// Catches internal platform-interface exceptions and rethrows them
/// as the user-facing [BlueyException] sealed hierarchy:
///
///   * [platform.GattOperationTimeoutException] → [GattTimeoutException]
///   * [platform.GattOperationDisconnectedException] →
///     [DisconnectedException] with [DisconnectReason.linkLoss]
///   * [platform.GattOperationStatusFailedException] →
///     [GattOperationFailedException] carrying the native status
///   * [platform.GattOperationUnknownPlatformException] →
///     [BlueyPlatformException] preserving the wire-level code
///   * [platform.PlatformPermissionDeniedException] →
///     [PermissionDeniedException] wrapping the single denied permission
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body, {
  LifecycleClient? lifecycleClient,
}) async {
  lifecycleClient?.markUserOpStarted();
  try {
    final result = await body();
    lifecycleClient?.recordActivity();
    return result;
  } on platform.GattOperationTimeoutException catch (e) {
    lifecycleClient?.recordUserOpFailure(e);
    throw GattTimeoutException(operation);
  } on platform.GattOperationDisconnectedException catch (e) {
    lifecycleClient?.recordUserOpFailure(e);
    throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
  } on platform.GattOperationStatusFailedException catch (e) {
    lifecycleClient?.recordUserOpFailure(e);
    throw GattOperationFailedException(operation, e.status);
  } on platform.GattOperationUnknownPlatformException catch (e) {
    lifecycleClient?.recordUserOpFailure(e);
    throw BlueyPlatformException(
      e.message ?? 'unknown platform error (${e.code})',
      code: e.code,
      cause: e,
    );
  } on platform.PlatformPermissionDeniedException catch (e) {
    lifecycleClient?.recordUserOpFailure(e);
    throw PermissionDeniedException([e.permission]);
  } on PlatformException catch (e) {
    lifecycleClient?.recordUserOpFailure(e);
    // Defensive backstop: any PlatformException that wasn't translated by
    // the platform adapter (e.g. a new native error code we haven't yet
    // mapped) gets wrapped so user code only ever catches BlueyException.
    throw BlueyPlatformException(
      e.message ?? 'platform error (${e.code})',
      code: e.code,
      cause: e,
    );
  } finally {
    lifecycleClient?.markUserOpEnded();
  }
}

/// Wraps [_runGattOp] with start / complete / failed log lines and a
/// stopwatch. Every public GATT op on the Connection / Characteristic /
/// Descriptor surface that wants per-op tracing goes through this so
/// the three log lines stay in lock-step.
///
/// [startDetail] — extra context appended after `deviceId=…` in both
/// the start and failed messages (e.g. `'char=$uuid, bytes=N'`).
/// [completeDetail] — optional result-derived suffix for the complete
/// message (e.g. `'negotiated=$mtu'`).
Future<T> _loggedGattOp<T>({
  required UUID deviceId,
  required String op,
  required Future<T> Function() body,
  String startDetail = '',
  String Function(T result)? completeDetail,
  LifecycleClient? lifecycleClient,
}) async {
  final startSuffix = startDetail.isEmpty ? '' : ', $startDetail';
  dev.log('$op start: deviceId=$deviceId$startSuffix',
      name: 'bluey.gatt', level: 500);
  final sw = Stopwatch()..start();
  try {
    final result = await _runGattOp(
      deviceId,
      op,
      body,
      lifecycleClient: lifecycleClient,
    );
    final detail = completeDetail?.call(result);
    final completeSuffix = (detail == null || detail.isEmpty) ? '' : ', $detail';
    dev.log(
        '$op complete: deviceId=$deviceId$completeSuffix, ${sw.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 500);
    return result;
  } catch (e) {
    final status =
        e is GattOperationFailedException ? ' status=${e.status}' : '';
    dev.log(
        '$op failed: deviceId=$deviceId$startSuffix, exception=${e.runtimeType}$status, ${sw.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 900,
        error: e);
    rethrow;
  }
}

/// Internal implementation of [Connection] that wraps platform calls.
///
/// This class is created by [Bluey.connect] and should not be instantiated
/// directly by users.
///
/// `BlueyConnection` is a *pure GATT connection*. It carries no
/// peer-protocol state (no `serverId`, no [LifecycleClient]); the
/// peer-protocol surface lives entirely in `PeerConnection` /
/// `_BlueyPeerConnection`, which composes a `BlueyConnection`
/// underneath.
class BlueyConnection implements Connection {
  final platform.BlueyPlatform _platform;
  final String _connectionId;

  /// The platform-level connection identifier.
  ///
  /// Exposed for internal use by peer orchestration (the
  /// [LifecycleClient] that lives inside `_BlueyPeerConnection` reads
  /// this to drive heartbeat writes). Not part of the public
  /// [Connection] interface.
  String get connectionId => _connectionId;

  @override
  final UUID deviceId;

  // Start as `linked` since we're constructed after a successful platform
  // connect — the link is up but services have not yet been discovered.
  // The first `services()` call promotes us to `ready`. See I067.
  ConnectionState _state = ConnectionState.linked;
  int _mtu = 23; // Default BLE MTU
  BondState _bondState = BondState.none;
  Phy _txPhy = Phy.le1m;
  Phy _rxPhy = Phy.le1m;
  ConnectionParameters _connectionParameters = _defaultConnectionParameters();

  static ConnectionParameters _defaultConnectionParameters() =>
      ConnectionParameters(
        interval: ConnectionInterval(30), // Default 30ms interval
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000), // Default 4s timeout
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

  /// Creates a new connection instance.
  ///
  /// This is called internally by Bluey and should not be used directly.
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
  }) : _platform = platformInstance,
       _connectionId = connectionId {
    // Subscribe to platform connection state changes.
    //
    // The platform reports four states (connecting / connected /
    // disconnecting / disconnected); we map them onto our five-state
    // domain enum, with the platform's `connected` becoming `linked`
    // (the link is up; services not yet discovered). Promotion to
    // `ready` is driven from `services()` once GATT discovery
    // completes — see [_setState] for the idempotent / non-regressing
    // transition logic.
    _platformStateSubscription = _platform
        .connectionStateStream(_connectionId)
        .listen(
          (platformState) {
            _setState(_mapConnectionState(platformState));
          },
          onError: (error) {
            _stateController.addError(error);
          },
        );

    // Bond / PHY / connection-parameter subscriptions and initial fetches
    // are guarded by [Capabilities]. Platforms that don't support an
    // operation throw `UnimplementedError` from the corresponding stub
    // (e.g. Android post-I035 Stage A); calling them unconditionally
    // would crash every connect on those platforms. The default field
    // values seeded above (BondState.none, le1m PHY, 30 ms / 0 / 4 s
    // connection parameters) stand in when the capability is absent.
    final caps = _platform.capabilities;

    if (caps.canBond) {
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

      _platform.getBondState(_connectionId).then((platformBondState) {
        _bondState = _mapBondState(platformBondState);
      });
    }

    if (caps.canRequestPhy) {
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

      _platform.getPhy(_connectionId).then((platformPhy) {
        _txPhy = _mapPhy(platformPhy.tx);
        _rxPhy = _mapPhy(platformPhy.rx);
      });
    }

    if (caps.canRequestConnectionParameters) {
      _platform.getConnectionParameters(_connectionId).then((params) {
        _connectionParameters = connectionParametersFromPlatform(params);
      });
    }
  }

  /// Throws [DisconnectedException] if the connection is not in a
  /// state that can carry GATT operations. The "live" states are
  /// [ConnectionState.linked] (link up, services not yet discovered)
  /// and [ConnectionState.ready] (link up, services discovered or
  /// upgraded). Every other state — `connecting`, `disconnecting`,
  /// `disconnected` — fails the gate.
  ///
  /// Called at the top of every public GATT-op method on the connection
  /// itself, and from `BlueyRemoteCharacteristic` /
  /// `BlueyRemoteDescriptor` via the closure threaded through their
  /// constructors. Without this gate, calling read/write/etc. on a
  /// dead connection lets a raw [PlatformException] escape from the
  /// platform layer (I002).
  void _ensureConnected() {
    if (_state == ConnectionState.linked || _state == ConnectionState.ready) {
      return;
    }
    throw DisconnectedException(deviceId, DisconnectReason.unknown);
  }

  /// Idempotent, non-regressing state transition. Skips the emit if the
  /// new state matches the current one. Also refuses to walk backwards
  /// from `ready` to `linked` if the platform happens to re-emit a
  /// CONNECTED event after services have already been discovered (the
  /// platform doesn't model the linked → ready distinction, so its
  /// repeats would otherwise downgrade us).
  void _setState(ConnectionState newState) {
    if (_state == newState) return;
    if (_state == ConnectionState.ready &&
        newState == ConnectionState.linked) {
      return;
    }
    _state = newState;
    dev.log(
      'state transition: → $_state',
      name: 'bluey.connection',
    );
    _stateController.add(_state);
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  Mtu get mtu => Mtu.fromPlatform(_mtu);

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
  Future<List<RemoteService>> services({bool cache = false}) async {
    _ensureConnected();
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
    _cachedServices =
        platformServices.map((ps) => _mapService(ps)).toList();

    dev.log(
      'services complete: deviceId=$deviceId, count=${_cachedServices!.length}, ${stopwatch.elapsedMilliseconds}ms',
      name: 'bluey.gatt',
      level: 500, // Level.FINE — per-op chatter; suppressed in default log views
    );

    // Services discovered → promote linked → ready.
    _setState(ConnectionState.ready);

    return _cachedServices!;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    final svcs = await services(cache: true);
    return svcs.any((s) => s.uuid == uuid);
  }

  @override
  Future<Mtu> requestMtu(Mtu mtu) async {
    _ensureConnected();
    final requested = mtu.value;
    _mtu = await _loggedGattOp(
      deviceId: deviceId,
      op: 'requestMtu',
      startDetail: 'requested=$requested',
      body: () => _platform.requestMtu(_connectionId, requested),
      completeDetail: (negotiated) =>
          'requested=$requested, negotiated=$negotiated',
    );
    return Mtu.fromPlatform(_mtu);
  }

  @override
  Future<int> readRssi() async {
    _ensureConnected();
    return _loggedGattOp(
      deviceId: deviceId,
      op: 'readRssi',
      body: () => _platform.readRssi(_connectionId),
      completeDetail: (rssi) => 'rssi=${rssi}dBm',
    );
  }

  // === Platform-specific extensions ===

  AndroidConnectionExtensions? _androidExtensions;

  @override
  AndroidConnectionExtensions? get android {
    final caps = _platform.capabilities;
    if (caps.canBond ||
        caps.canRequestPhy ||
        caps.canRequestConnectionParameters) {
      return _androidExtensions ??= _AndroidConnectionExtensionsImpl(this);
    }
    return null;
  }

  @override
  IosConnectionExtensions? get ios {
    final caps = _platform.capabilities;
    // Heuristic: a platform with NONE of the Android-only flags is
    // treated as iOS-flavored. If [Capabilities] ever gains a dedicated
    // `isIos` flag, this should be replaced with a precise check.
    if (!caps.canBond &&
        !caps.canRequestPhy &&
        !caps.canRequestConnectionParameters) {
      return _iosExtensions;
    }
    return null;
  }

  @override
  Future<void> disconnect() async {
    // Idempotent: if already disconnected or disconnecting, do nothing
    if (_state == ConnectionState.disconnected ||
        _state == ConnectionState.disconnecting) {
      return;
    }

    _setState(ConnectionState.disconnecting);

    await _platform.disconnect(_connectionId);

    _setState(ConnectionState.disconnected);

    await _cleanup();
  }

  // === Bonding (private; exposed via connection.android?.X) ===

  BondState get _bondStateValue => _bondState;

  Stream<BondState> get _bondStateChanges => _bondStateController.stream;

  Future<void> _bondImpl() async {
    _ensureConnected();
    await _platform.bond(_connectionId);
  }

  Future<void> _removeBondImpl() async {
    _ensureConnected();
    await _platform.removeBond(_connectionId);
  }

  // === PHY (private; exposed via connection.android?.X) ===

  Phy get _txPhyValue => _txPhy;

  Phy get _rxPhyValue => _rxPhy;

  Stream<({Phy tx, Phy rx})> get _phyChanges => _phyController.stream;

  Future<void> _requestPhyImpl({Phy? txPhy, Phy? rxPhy}) async {
    _ensureConnected();
    await _platform.requestPhy(
      _connectionId,
      txPhy != null ? _mapPhyToPlatform(txPhy) : null,
      rxPhy != null ? _mapPhyToPlatform(rxPhy) : null,
    );
  }

  // === Connection Parameters (private; exposed via connection.android?.X) ===

  ConnectionParameters get _connectionParametersValue => _connectionParameters;

  Future<void> _requestConnectionParametersImpl(
    ConnectionParameters params,
  ) async {
    _ensureConnected();
    await _platform.requestConnectionParameters(
      _connectionId,
      connectionParametersToPlatform(params),
    );
    _connectionParameters = params;
  }

  /// Clean up resources.
  Future<void> _cleanup() async {
    await _platformStateSubscription?.cancel();
    await _platformBondStateSubscription?.cancel();
    await _platformPhySubscription?.cancel();
    await _stateController.close();
    await _bondStateController.close();
    await _phyController.close();

    // I003 — dispose every cached service before nulling the cache, so
    // each BlueyRemoteCharacteristic's lazily-built notification
    // controller is closed and its platform subscription cancelled.
    // Without this walk, controllers persisted across connect/disconnect
    // cycles and memory grew monotonically.
    final cached = _cachedServices;
    _cachedServices = null;
    if (cached != null) {
      for (final service in cached) {
        await service.dispose();
      }
    }
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
        // Platform doesn't model the linked → ready distinction; the
        // promotion to ready is driven domain-side from `services()`.
        // See I067.
        return ConnectionState.linked;
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
    // BlueyConnection itself carries no lifecycle (post-C.6 the
    // peer-protocol surface lives entirely in `PeerConnection`).
    // Characteristics are constructed without a lifecycleClient — the
    // getter remains on `BlueyRemoteCharacteristic` for tests / future
    // consumers that wire activity feedback externally.
    final platformHandle = pc.handle;
    if (platformHandle == null) {
      throw StateError(
        'BlueyRemoteCharacteristic constructed without a handle. '
        'This indicates a Bluey internal bug or stale platform implementation '
        'that has not been updated to emit handles in CharacteristicDto.',
      );
    }
    return BlueyRemoteCharacteristic(
      platform: _platform,
      connectionId: _connectionId,
      deviceId: deviceId,
      uuid: UUID(pc.uuid),
      handle: AttributeHandle(platformHandle),
      properties: CharacteristicProperties(
        canRead: pc.properties.canRead,
        canWrite: pc.properties.canWrite,
        canWriteWithoutResponse: pc.properties.canWriteWithoutResponse,
        canNotify: pc.properties.canNotify,
        canIndicate: pc.properties.canIndicate,
      ),
      descriptors: pc.descriptors.map(_mapDescriptor).toList(),
      ensureConnected: _ensureConnected,
    );
  }

  BlueyRemoteDescriptor _mapDescriptor(platform.PlatformDescriptor pd) {
    final platformHandle = pd.handle;
    if (platformHandle == null) {
      throw StateError(
        'BlueyRemoteDescriptor constructed without a handle. '
        'This indicates a Bluey internal bug or stale platform implementation '
        'that has not been updated to emit handles in DescriptorDto.',
      );
    }
    return BlueyRemoteDescriptor(
      platform: _platform,
      connectionId: _connectionId,
      deviceId: deviceId,
      uuid: UUID(pd.uuid),
      handle: AttributeHandle(platformHandle),
      ensureConnected: _ensureConnected,
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

  /// Releases per-characteristic resources (notification subscriptions
  /// and broadcast controllers) for every characteristic in this
  /// service. Called by [BlueyConnection._cleanup] on disconnect to
  /// prevent the leak documented in I003. Included services are
  /// disposed recursively. Idempotent.
  Future<void> dispose() async {
    for (final char in characteristics) {
      if (char is BlueyRemoteCharacteristic) {
        await char.dispose();
      }
    }
    for (final included in includedServices) {
      if (included is BlueyRemoteService) {
        await included.dispose();
      }
    }
  }
}

/// Internal implementation of [RemoteCharacteristic].
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final UUID _deviceId;
  final LifecycleClient? Function() _lifecycle;
  final void Function() _ensureConnected;

  @override
  final UUID uuid;

  @override
  final AttributeHandle handle;

  @override
  final CharacteristicProperties properties;

  @override
  final List<RemoteDescriptor> descriptors;

  StreamSubscription? _notificationSubscription;
  StreamController<Uint8List>? _notificationController;

  /// [lifecycleClient] is a getter rather than a value because the
  /// characteristic may be constructed before the connection upgrades
  /// to the Bluey lifecycle protocol. Reading the field at call time
  /// ensures user ops on characteristics built during initial service
  /// discovery still feed activity / failure signals into the
  /// lifecycle once it starts.
  ///
  /// [ensureConnected] is the connection's pre-flight gate (I002).
  /// Invoked at the top of every public op; throws
  /// [DisconnectedException] if the owning connection is no longer
  /// in `linked` or `ready`. Defaults to a no-op for tests that
  /// build a characteristic without a parent connection.
  BlueyRemoteCharacteristic({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
    required this.handle,
    required this.properties,
    required this.descriptors,
    LifecycleClient? Function()? lifecycleClient,
    void Function()? ensureConnected,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId,
       _lifecycle = lifecycleClient ?? (() => null),
       _ensureConnected = ensureConnected ?? (() {});

  @override
  Future<Uint8List> read() async {
    _ensureConnected();
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    return _loggedGattOp(
      deviceId: _deviceId,
      op: 'readCharacteristic',
      startDetail: 'char=$uuid',
      body: () => _platform.readCharacteristic(_connectionId, uuid.toString()),
      completeDetail: (value) => 'char=$uuid, bytes=${value.length}',
      lifecycleClient: _lifecycle(),
    );
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    _ensureConnected();
    if (withResponse && !properties.canWrite) {
      throw const OperationNotSupportedException('write');
    }
    if (!withResponse && !properties.canWriteWithoutResponse) {
      throw const OperationNotSupportedException('writeWithoutResponse');
    }
    return _loggedGattOp<void>(
      deviceId: _deviceId,
      op: 'writeCharacteristic',
      startDetail: 'char=$uuid, bytes=${value.length}',
      body: () => _platform.writeCharacteristic(
        _connectionId,
        uuid.toString(),
        value,
        withResponse,
      ),
      completeDetail: (_) => 'char=$uuid',
      lifecycleClient: _lifecycle(),
    );
  }

  @override
  Stream<Uint8List> get notifications {
    _ensureConnected();
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
      lifecycleClient: _lifecycle(),
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
            // Inbound notifications are demonstrable peer activity but
            // not user ops, so we record activity without the
            // start/end/failure wrapping used for outbound ops.
            _lifecycle()?.recordActivity();
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
      lifecycleClient: _lifecycle(),
    ).catchError((Object _) {});

    // Cancel subscription
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  /// Releases this characteristic's notification resources. Called by
  /// the owning [BlueyRemoteService.dispose] when the connection is
  /// torn down (I003). Cancels the platform notification subscription
  /// and closes the lazily-built broadcast controller. Idempotent and
  /// safe when no consumer ever subscribed (controller was never
  /// created).
  Future<void> dispose() async {
    final sub = _notificationSubscription;
    _notificationSubscription = null;
    await sub?.cancel();

    final controller = _notificationController;
    _notificationController = null;
    await controller?.close();
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
  final LifecycleClient? Function() _lifecycle;
  final void Function() _ensureConnected;

  @override
  final UUID uuid;

  @override
  final AttributeHandle handle;

  /// [lifecycleClient] is a getter rather than a value: descriptors are
  /// constructed during service discovery, before the connection
  /// upgrades to the Bluey lifecycle protocol. See
  /// [BlueyRemoteCharacteristic] for the same pattern and reasoning.
  ///
  /// [ensureConnected] is the connection's pre-flight gate (I002).
  /// Defaults to a no-op for tests that build a descriptor without a
  /// parent connection.
  BlueyRemoteDescriptor({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
    required this.handle,
    LifecycleClient? Function()? lifecycleClient,
    void Function()? ensureConnected,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId,
       _lifecycle = lifecycleClient ?? (() => null),
       _ensureConnected = ensureConnected ?? (() {});

  @override
  Future<Uint8List> read() async {
    _ensureConnected();
    return _runGattOp(
      _deviceId,
      'readDescriptor',
      () => _platform.readDescriptor(_connectionId, uuid.toString()),
      lifecycleClient: _lifecycle(),
    );
  }

  @override
  Future<void> write(Uint8List value) async {
    _ensureConnected();
    return _runGattOp(
      _deviceId,
      'writeDescriptor',
      () => _platform.writeDescriptor(_connectionId, uuid.toString(), value),
      lifecycleClient: _lifecycle(),
    );
  }
}

/// Thin facade over a [BlueyConnection] that exposes the Android-only
/// surface (bonding, PHY, connection parameters) without duplicating
/// logic. Returned from `BlueyConnection.android` when the platform
/// reports any of the Android-only capability flags. Created at most
/// once per connection and lazy-cached.
///
/// Each member delegates straight back to the corresponding private
/// member on the wrapping [BlueyConnection]. The bond/PHY/conn-params
/// members are private on [BlueyConnection] (since B.3 removed them
/// from the [Connection] interface) and only reachable via this
/// facade.
class _AndroidConnectionExtensionsImpl implements AndroidConnectionExtensions {
  final BlueyConnection _conn;

  _AndroidConnectionExtensionsImpl(this._conn);

  @override
  BondState get bondState => _conn._bondStateValue;

  @override
  Stream<BondState> get bondStateChanges => _conn._bondStateChanges;

  @override
  Future<void> bond() => _conn._bondImpl();

  @override
  Future<void> removeBond() => _conn._removeBondImpl();

  @override
  Phy get txPhy => _conn._txPhyValue;

  @override
  Phy get rxPhy => _conn._rxPhyValue;

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => _conn._phyChanges;

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) =>
      _conn._requestPhyImpl(txPhy: txPhy, rxPhy: rxPhy);

  @override
  ConnectionParameters get connectionParameters =>
      _conn._connectionParametersValue;

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) =>
      _conn._requestConnectionParametersImpl(params);
}

/// Empty const singleton implementing [IosConnectionExtensions]. Reserved
/// for future iOS-specific features; see [IosConnectionExtensions] for
/// the rationale.
class _IosConnectionExtensionsImpl implements IosConnectionExtensions {
  const _IosConnectionExtensionsImpl();
}

const _iosExtensions = _IosConnectionExtensionsImpl();
