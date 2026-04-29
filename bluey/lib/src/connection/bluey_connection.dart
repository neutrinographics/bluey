import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../gatt_client/gatt.dart';
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
import '../shared/characteristic_properties.dart';
import '../shared/error_translation.dart';
import '../shared/exceptions.dart';
import '../shared/uuid.dart';
import 'android_connection_extensions.dart';
import 'connection.dart';
import 'connection_parameters_mapper.dart';
import 'ios_connection_extensions.dart';
import 'lifecycle_client.dart';
import 'value_objects/attribute_handle.dart';

/// Thin wrapper over [withErrorTranslation] preserved for call-site
/// readability — every public GATT op on [BlueyConnection] /
/// [BlueyRemoteCharacteristic] / [BlueyRemoteDescriptor] flows through
/// this so the lifecycle accounting and exception translation stay in
/// one place. See [withErrorTranslation] for the full hook contract.
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body, {
  LifecycleClient? lifecycleClient,
}) {
  return withErrorTranslation(
    body,
    operation: operation,
    deviceId: deviceId,
    lifecycleClient: lifecycleClient,
  );
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
  BlueyLogger? logger,
}) async {
  logger?.log(
    BlueyLogLevel.debug,
    'bluey.gatt',
    '$op start',
    data: {
      'deviceId': deviceId.toString(),
      'op': op,
      if (startDetail.isNotEmpty) 'detail': startDetail,
    },
  );
  final sw = Stopwatch()..start();
  try {
    final result = await _runGattOp(
      deviceId,
      op,
      body,
      lifecycleClient: lifecycleClient,
    );
    final detail = completeDetail?.call(result);
    logger?.log(
      BlueyLogLevel.debug,
      'bluey.gatt',
      '$op complete',
      data: {
        'deviceId': deviceId.toString(),
        'op': op,
        'durationMs': sw.elapsedMilliseconds,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      },
    );
    return result;
  } catch (e) {
    logger?.log(
      BlueyLogLevel.error,
      'bluey.gatt',
      '$op failed',
      data: {
        'deviceId': deviceId.toString(),
        'op': op,
        'exception': e.runtimeType.toString(),
        'durationMs': sw.elapsedMilliseconds,
        if (e is GattOperationFailedException) 'status': e.status,
        if (startDetail.isNotEmpty) 'detail': startDetail,
      },
      errorCode: e.runtimeType.toString(),
    );
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
  final BlueyLogger _logger;

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
  final StreamController<List<RemoteService>> _servicesChangesController =
      StreamController<List<RemoteService>>.broadcast();

  StreamSubscription? _platformStateSubscription;
  StreamSubscription? _platformBondStateSubscription;
  StreamSubscription? _platformPhySubscription;
  StreamSubscription? _platformServiceChangesSubscription;

  // Cached services after discovery
  List<BlueyRemoteService>? _cachedServices;

  // I088 D.11 — in-flight GATT-op aborters. Each call to a public GATT
  // op on the connection / characteristic / descriptor surface
  // registers a completer here for the lifetime of the underlying
  // platform call. On Service Changed, every entry is failed with
  // [AttributeHandleInvalidatedException] so callers stop waiting on
  // futures whose handles are now stale and re-discover instead.
  final Set<Completer<Object?>> _pendingGattOpAborters = {};

  /// Creates a new connection instance.
  ///
  /// This is called internally by Bluey and should not be used directly.
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
    required BlueyLogger logger,
  }) : _platform = platformInstance,
       _connectionId = connectionId,
       _logger = logger {
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

    // I088 D.11 — Service Changed invalidates the entire discovered
    // attribute tree. Native sides have already cleared their handle
    // tables by the time this event fires (D.3 Android, D.5 iOS). Here
    // we mirror that on the Dart side: drop the cached services so the
    // next `services()` call re-discovers, and abort every in-flight
    // GATT op with a typed exception so callers stop waiting on
    // futures whose handles are now stale.
    _platformServiceChangesSubscription = _platform.serviceChanges
        .where((id) => id == _connectionId)
        .listen((_) {
      _onServiceChanged();
    });

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

  /// I088 D.11 — wraps [body] so that a Service Changed event fired
  /// while the call is in flight surfaces the typed
  /// [AttributeHandleInvalidatedException] on the original future, even
  /// if the platform layer never produces a response. The aborter token
  /// is registered for the lifetime of the platform call; whichever of
  /// (platform completion, abort) fires first wins.
  Future<T> _trackInFlight<T>(Future<T> Function() body) {
    final aborter = Completer<Object?>();
    _pendingGattOpAborters.add(aborter);
    body().then(
      (value) {
        if (!aborter.isCompleted) aborter.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!aborter.isCompleted) aborter.completeError(error, stack);
      },
    );
    return aborter.future
        .whenComplete(() => _pendingGattOpAborters.remove(aborter))
        .then((value) => value as T);
  }

  /// Service Changed handler. Drops the cached service tree and aborts
  /// every in-flight op. Idempotent: a second event with no in-flight
  /// ops is a no-op.
  ///
  /// After clearing the cache, kicks off a fresh re-discovery and emits
  /// the new service list on [servicesChanges] for proactive consumers
  /// (e.g. the lifecycle client refreshing its heartbeat-char handle).
  void _onServiceChanged() {
    _logger.log(
      BlueyLogLevel.warn,
      'bluey.connection',
      'Service Changed received',
      data: {
        'deviceId': deviceId.toString(),
        'inFlight': _pendingGattOpAborters.length,
      },
    );
    _cachedServices = null;
    _logger.log(
      BlueyLogLevel.warn,
      'bluey.connection',
      'service cache cleared, re-discovery pending',
      data: {'deviceId': deviceId.toString()},
    );
    if (_pendingGattOpAborters.isNotEmpty) {
      final aborters = _pendingGattOpAborters.toList(growable: false);
      _pendingGattOpAborters.clear();
      for (final aborter in aborters) {
        if (!aborter.isCompleted) {
          aborter.completeError(AttributeHandleInvalidatedException());
        }
      }
    }

    // Eagerly re-discover so consumers get a fresh service tree without
    // having to call services() themselves. Fire-and-forget; errors
    // surface as a stream error to subscribers (rather than an
    // unhandled future).
    services().then((fresh) {
      if (_servicesChangesController.isClosed) return;
      _servicesChangesController.add(fresh);
    }).catchError((Object e, StackTrace st) {
      if (_servicesChangesController.isClosed) return;
      _servicesChangesController.addError(e, st);
    });
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
    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'state transition',
      data: {
        'deviceId': deviceId.toString(),
        'state': _state.toString(),
      },
    );
    _stateController.add(_state);
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  Stream<List<RemoteService>> get servicesChanges =>
      _servicesChangesController.stream;

  @override
  Mtu get mtu => Mtu.fromPlatform(_mtu);

  @override
  RemoteService service(UUID uuid) {
    if (_cachedServices == null) {
      throw ServiceNotFoundException(uuid);
    }

    final matches = <RemoteService>[
      for (final svc in _cachedServices!)
        if (svc.uuid == uuid) svc,
    ];
    if (matches.isEmpty) {
      throw ServiceNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'service',
      );
    }
    return matches.single;
  }

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    _ensureConnected();
    if (cache && _cachedServices != null) {
      return _cachedServices!;
    }

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'services discovery started',
      data: {'deviceId': deviceId.toString()},
    );
    final stopwatch = Stopwatch()..start();
    final platformServices = await _trackInFlight(() => _runGattOp(
          deviceId,
          'discoverServices',
          () => _platform.discoverServices(_connectionId),
        ));
    _cachedServices =
        platformServices.map((ps) => _mapService(ps)).toList();

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'services discovery resolved',
      data: {
        'deviceId': deviceId.toString(),
        'count': _cachedServices!.length,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
    );

    // Trace-level enumeration of every discovered service UUID. Useful
    // for debugging UUID-canonicalization mismatches (e.g. peer-detection
    // failing because the lifecycle control service UUID arrives in a
    // different form than expected).
    if (_cachedServices!.isNotEmpty) {
      _logger.log(
        BlueyLogLevel.trace,
        'bluey.connection',
        'services discovered',
        data: {
          'deviceId': deviceId.toString(),
          'uuids': _cachedServices!.map((s) => s.uuid.toString()).toList(),
        },
      );
    }

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
    _mtu = await _trackInFlight(() => _loggedGattOp(
          deviceId: deviceId,
          op: 'requestMtu',
          startDetail: 'requested=$requested',
          body: () => _platform.requestMtu(_connectionId, requested),
          completeDetail: (negotiated) =>
              'requested=$requested, negotiated=$negotiated',
          logger: _logger,
        ));
    return Mtu.fromPlatform(_mtu);
  }

  @override
  Future<int> readRssi() async {
    _ensureConnected();
    return _trackInFlight(() => _loggedGattOp(
          deviceId: deviceId,
          op: 'readRssi',
          body: () => _platform.readRssi(_connectionId),
          completeDetail: (rssi) => 'rssi=${rssi}dBm',
          logger: _logger,
        ));
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

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'disconnect entered',
      data: {'deviceId': deviceId.toString()},
    );

    _setState(ConnectionState.disconnecting);

    await _platform.disconnect(_connectionId);

    _setState(ConnectionState.disconnected);

    await _cleanup();

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'disconnect resolved',
      data: {'deviceId': deviceId.toString()},
    );
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
    await _platformServiceChangesSubscription?.cancel();
    await _stateController.close();
    await _bondStateController.close();
    await _phyController.close();
    await _servicesChangesController.close();

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
    final characteristicHandle = AttributeHandle(pc.handle);
    return BlueyRemoteCharacteristic(
      platform: _platform,
      connectionId: _connectionId,
      deviceId: deviceId,
      uuid: UUID(pc.uuid),
      handle: characteristicHandle,
      properties: CharacteristicProperties(
        canRead: pc.properties.canRead,
        canWrite: pc.properties.canWrite,
        canWriteWithoutResponse: pc.properties.canWriteWithoutResponse,
        canNotify: pc.properties.canNotify,
        canIndicate: pc.properties.canIndicate,
      ),
      descriptors: pc.descriptors
          .map((pd) => _mapDescriptor(pd, characteristicHandle))
          .toList(),
      ensureConnected: _ensureConnected,
      trackInFlight: _trackInFlight,
      logger: _logger,
    );
  }

  BlueyRemoteDescriptor _mapDescriptor(
    platform.PlatformDescriptor pd,
    AttributeHandle characteristicHandle,
  ) {
    return BlueyRemoteDescriptor(
      platform: _platform,
      connectionId: _connectionId,
      deviceId: deviceId,
      uuid: UUID(pd.uuid),
      handle: AttributeHandle(pd.handle),
      characteristicHandle: characteristicHandle,
      ensureConnected: _ensureConnected,
      trackInFlight: _trackInFlight,
      logger: _logger,
    );
  }
}

/// Internal implementation of [RemoteService].
class BlueyRemoteService implements RemoteService {
  @override
  final UUID uuid;

  @override
  final bool isPrimary;

  /// All characteristics in this service. Stored as the full discovered
  /// list; the public surface is [characteristics] (filterable) and
  /// [characteristic] (singular, throws on ambiguity).
  final List<RemoteCharacteristic> _characteristics;

  @override
  final List<RemoteService> includedServices;

  BlueyRemoteService({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required this.uuid,
    required this.isPrimary,
    required List<RemoteCharacteristic> characteristics,
    required this.includedServices,
  }) : _characteristics = characteristics;

  @override
  List<RemoteCharacteristic> characteristics({UUID? uuid}) {
    if (uuid == null) return List.unmodifiable(_characteristics);
    return List.unmodifiable(
      _characteristics.where((c) => c.uuid == uuid),
    );
  }

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    final matches = _characteristics.where((c) => c.uuid == uuid).toList();
    if (matches.isEmpty) {
      throw CharacteristicNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'characteristic',
      );
    }
    return matches.single;
  }

  /// Releases per-characteristic resources (notification subscriptions
  /// and broadcast controllers) for every characteristic in this
  /// service. Called by [BlueyConnection._cleanup] on disconnect to
  /// prevent the leak documented in I003. Included services are
  /// disposed recursively. Idempotent.
  Future<void> dispose() async {
    for (final char in _characteristics) {
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

/// Type signature of the in-flight aborter wrapper threaded from
/// [BlueyConnection] into characteristics and descriptors. Wraps a
/// platform-call body so a Service Changed event fired mid-flight
/// causes the returned future to fail with
/// [AttributeHandleInvalidatedException].
typedef _TrackInFlight = Future<T> Function<T>(Future<T> Function() body);

Future<T> _passthroughInFlight<T>(Future<T> Function() body) => body();

/// Internal implementation of [RemoteCharacteristic].
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final UUID _deviceId;
  final LifecycleClient? Function() _lifecycle;
  final void Function() _ensureConnected;
  final _TrackInFlight _trackInFlight;
  final BlueyLogger? _logger;

  @override
  final UUID uuid;

  @override
  final AttributeHandle handle;

  @override
  final CharacteristicProperties properties;

  /// All descriptors of this characteristic. Stored as the full
  /// discovered list; the public surface is [descriptors] (filterable)
  /// and [descriptor] (singular, throws on ambiguity).
  final List<RemoteDescriptor> _descriptors;

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
    required List<RemoteDescriptor> descriptors,
    LifecycleClient? Function()? lifecycleClient,
    void Function()? ensureConnected,
    _TrackInFlight? trackInFlight,
    BlueyLogger? logger,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId,
       _descriptors = descriptors,
       _lifecycle = lifecycleClient ?? (() => null),
       _ensureConnected = ensureConnected ?? (() {}),
       _trackInFlight = trackInFlight ?? _passthroughInFlight,
       _logger = logger;

  @override
  Future<Uint8List> read() async {
    _ensureConnected();
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    return _trackInFlight(() => _loggedGattOp(
          deviceId: _deviceId,
          op: 'readCharacteristic',
          startDetail: 'char=$uuid',
          body: () => _platform.readCharacteristic(
            _connectionId,
            handle.value,
          ),
          completeDetail: (value) => 'char=$uuid, bytes=${value.length}',
          lifecycleClient: _lifecycle(),
          logger: _logger,
        ));
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
    return _trackInFlight<void>(() => _loggedGattOp<void>(
          deviceId: _deviceId,
          op: 'writeCharacteristic',
          startDetail: 'char=$uuid, bytes=${value.length}',
          body: () => _platform.writeCharacteristic(
            _connectionId,
            handle.value,
            value,
            withResponse,
          ),
          completeDetail: (_) => 'char=$uuid',
          lifecycleClient: _lifecycle(),
          logger: _logger,
        ));
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
      () => _platform.setNotification(
        _connectionId,
        handle.value,
        true,
      ),
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
      () => _platform.setNotification(
        _connectionId,
        handle.value,
        false,
      ),
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
  List<RemoteDescriptor> descriptors({UUID? uuid}) {
    if (uuid == null) return List.unmodifiable(_descriptors);
    return List.unmodifiable(_descriptors.where((d) => d.uuid == uuid));
  }

  @override
  RemoteDescriptor descriptor(UUID uuid) {
    final matches = _descriptors.where((d) => d.uuid == uuid).toList();
    if (matches.isEmpty) {
      throw CharacteristicNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'descriptor',
      );
    }
    return matches.single;
  }
}

/// Internal implementation of [RemoteDescriptor].
class BlueyRemoteDescriptor implements RemoteDescriptor {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final UUID _deviceId;
  final LifecycleClient? Function() _lifecycle;
  final void Function() _ensureConnected;
  final _TrackInFlight _trackInFlight;
  // ignore: unused_field
  final BlueyLogger? _logger;

  /// Handle of the parent characteristic. Threaded onto the wire
  /// alongside [handle] so native receivers can route descriptor ops
  /// through the same handle table used for the owning characteristic.
  final AttributeHandle _characteristicHandle;

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
  ///
  /// [characteristicHandle] is the parent characteristic's handle; it
  /// rides on every descriptor op so native receivers can prefer
  /// handle-keyed lookup over UUID-keyed lookup.
  BlueyRemoteDescriptor({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
    required this.handle,
    required AttributeHandle characteristicHandle,
    LifecycleClient? Function()? lifecycleClient,
    void Function()? ensureConnected,
    _TrackInFlight? trackInFlight,
    BlueyLogger? logger,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId,
       _characteristicHandle = characteristicHandle,
       _lifecycle = lifecycleClient ?? (() => null),
       _ensureConnected = ensureConnected ?? (() {}),
       _trackInFlight = trackInFlight ?? _passthroughInFlight,
       _logger = logger;

  @override
  Future<Uint8List> read() async {
    _ensureConnected();
    return _trackInFlight(() => _runGattOp(
          _deviceId,
          'readDescriptor',
          () => _platform.readDescriptor(
            _connectionId,
            _characteristicHandle.value,
            handle.value,
          ),
          lifecycleClient: _lifecycle(),
        ));
  }

  @override
  Future<void> write(Uint8List value) async {
    _ensureConnected();
    return _trackInFlight<void>(() => _runGattOp(
          _deviceId,
          'writeDescriptor',
          () => _platform.writeDescriptor(
            _connectionId,
            _characteristicHandle.value,
            handle.value,
            value,
          ),
          lifecycleClient: _lifecycle(),
        ));
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
