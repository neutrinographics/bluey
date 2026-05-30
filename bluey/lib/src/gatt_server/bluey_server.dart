import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../lifecycle.dart' as lifecycle;
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
import '../peer/peer_client.dart';
import '../peer/server_id.dart';
import '../platform/bluetooth_state.dart';
import '../shared/error_translation.dart';
import '../shared/exceptions.dart';
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import 'lifecycle_server.dart';
import 'server.dart';

/// Concrete implementation of [Server] that delegates to the platform.
class BlueyServer implements Server {
  final platform.BlueyPlatform _platform;
  final EventPublisher _eventBus;
  final BlueyLogger _logger;
  final ServerId _serverId;
  late final LifecycleServer _lifecycle;
  late final Future<platform.PlatformLocalService?> _controlServiceReady;

  // I333/stream-conv: state machine replaces the previous boolean
  // `_isAdvertising`. The public `isAdvertising` getter remains, derived
  // from `_advertisingState == AdvertisingState.advertising`.
  AdvertisingState _advertisingState = AdvertisingState.idle;

  /// Arguments of the currently-active advertisement, captured on
  /// `startAdvertising` and read by `_setAdvertisingState` so the
  /// emitted `AdvertisingStartedEvent` carries the same `name`/`services`
  /// payload as the direct emit it replaced. Cleared on transition back
  /// to `idle` / `invalidated`.
  String? _activeAdvertisingName;
  List<UUID>? _activeAdvertisingServices;

  /// Broadcast controller for advertising-state-change deltas.
  /// `advertisingStateChanges` wraps this in a `Stream.multi` per the
  /// Task 6/7/11 convention so every new subscriber gets the current
  /// state replayed before receiving subsequent deltas.
  final StreamController<AdvertisingState> _advertisingStateController =
      StreamController<AdvertisingState>.broadcast();

  final Map<ClientAddress, BlueyClient> _connectedClients = {};

  /// A client has an *established session* iff it is present in
  /// [_connectedClients] via a real connect/announce (`centralConnections`).
  /// The server services read/write requests only within an established
  /// session — a request from a session-less client is evicted (I338).
  bool _hasEstablishedSession(ClientAddress clientAddress) =>
      _connectedClients.containsKey(clientAddress);

  /// Local handle table populated from `addService`'s populated return
  /// value. Keyed by `(serviceUuid, charUuid)` lowercase. Used by
  /// `notify` / `indicate` / `notifyTo` / `indicateTo` to resolve a
  /// user-supplied UUID into the platform-minted handle the wire
  /// format requires. Public API stays UUID-based for users; only
  /// internal storage moves to handle.
  final Map<(String, String), int> _localCharHandles = {};

  /// User-initiated `addService` futures still in flight. Tracked here
  /// so [startAdvertising] can await them — without this, advertising
  /// could begin while services were still registering and a central
  /// connecting in that window would see an incomplete GATT tree.
  final List<Future<void>> _pendingServiceAdds = [];

  final StreamController<Client> _connectionsController =
      StreamController<Client>.broadcast();
  final StreamController<PeerClient> _peerConnectionsController =
      StreamController<PeerClient>.broadcast();
  final StreamController<ClientAddress> _disconnectionsController =
      StreamController<ClientAddress>.broadcast();

  /// Set of client addresses that have been identified as Bluey peers
  /// (i.e. have sent at least one lifecycle heartbeat in the current
  /// session). Used to fire [PeerClient] emissions exactly once per
  /// identification — not once per heartbeat. Cleared on disconnect so
  /// a reconnect-then-heartbeat re-identifies.
  final Set<ClientAddress> _identifiedPeerClientAddresses = {};

  // Filtered stream controllers — control service requests are intercepted
  // and handled internally, never reaching the public API.
  final StreamController<platform.PlatformReadRequest>
  _filteredReadRequestsController =
      StreamController<platform.PlatformReadRequest>.broadcast();
  final StreamController<platform.PlatformWriteRequest>
  _filteredWriteRequestsController =
      StreamController<platform.PlatformWriteRequest>.broadcast();

  StreamSubscription? _centralConnectionsSub;
  StreamSubscription? _centralDisconnectionsSub;
  StreamSubscription? _platformReadRequestsSub;
  StreamSubscription? _platformWriteRequestsSub;

  // I333: adapter-state invalidation. The server subscribes to
  // platform.stateStream at construction; any non-`on` emission flips
  // [_invalidated] to true and tears down owned streams + caches.
  // Subsequent public calls throw [StaleHandleException].
  bool _invalidated = false;
  BluetoothState? _invalidationState;
  StreamSubscription<platform.BluetoothState>? _stateSubscription;

  BlueyServer(
    this._platform,
    this._eventBus, {
    required BlueyLogger logger,
    Duration? lifecycleInterval = lifecycle.defaultLifecycleInterval,
    ServerId? identity,
  }) : _logger = logger,
       _serverId = identity ?? ServerId.generate() {
    _lifecycle = LifecycleServer(
      platformApi: _platform,
      interval: lifecycleInterval,
      serverId: _serverId,
      onClientGone: _handleLifecycleSilence,
      onExplicitDisconnect: _handleClientDisconnected,
      onPeerIdentified: _trackPeerClient,
      logger: logger,
      events: _eventBus,
    );
    // Eagerly add the control service so it's available for incoming
    // connections even before startAdvertising() is called. A client may
    // reconnect via a cached peripheral reference while the server UI is
    // still on the "not advertising" screen.
    //
    // Store the Future so addService() and startAdvertising() can await
    // it — Android's BluetoothGattServer requires services to be added
    // sequentially (no concurrent addService calls).
    _controlServiceReady = _lifecycle.addControlServiceIfNeeded();
    _controlServiceReady.then((populated) {
      if (populated != null) _recordLocalHandles(populated);
    });

    _emitEvent(ServerStartedEvent(source: 'BlueyServer'));
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'server initialized',
      data: {'serverId': _serverId.toString()},
    );

    // Domain ↔ Platform seam: the platform-interface emits `PlatformCentral`
    // (BLE-spec vocabulary). Inside the GATT-Server bounded context the
    // connected GATT central is a `Client`. We translate exactly once, here.
    _centralConnectionsSub = _platform.centralConnections.listen((
      platformCentral,
    ) {
      final clientAddress = ClientAddress(platformCentral.id);
      _logger.log(
        BlueyLogLevel.info,
        'bluey.server',
        'central connected',
        data: {'clientId': clientAddress.value, 'mtu': platformCentral.mtu},
      );
      _emitEvent(
        ClientConnectedEvent(
          clientAddress: clientAddress,
          mtu: platformCentral.mtu,
          source: 'BlueyServer',
        ),
      );
      final client = BlueyClient(
        address: clientAddress,
        mtu: platformCentral.mtu,
      );
      _connectedClients[clientAddress] = client;
      _connectionsController.add(client);
      // No heartbeat timer here. The timer starts only when the client sends
      // its first heartbeat write, proving it speaks the lifecycle protocol.
      // Clients that never heartbeat (non-Bluey centrals) are never timed out
      // and remain connected until the platform reports a real disconnection.
    });

    _centralDisconnectionsSub = _platform.centralDisconnections.listen((
      rawClientId,
    ) {
      _handleClientDisconnected(ClientAddress(rawClientId));
    });

    // I338: re-announce any central that survived a prior server instance so
    // this fresh server re-establishes its session instead of evicting its
    // next request. Fired after the centralConnections/centralDisconnections
    // listeners are attached so the re-announce events are observed. No-op on
    // platforms without surviving centrals (default-no-op base method).
    unawaited(
      _platform.resetServerSessions().catchError((Object e) {
        _logger.log(
          BlueyLogLevel.warn,
          'bluey.server',
          'resetServerSessions failed; surviving centrals may not be re-announced',
          data: {'error': e.toString()},
        );
      }),
    );

    // Subscribe to platform request streams and route internally.
    // Control service requests are handled here; all others are forwarded
    // to the filtered controllers for the public API.
    _platformReadRequestsSub = _platform.readRequests.listen((req) {
      final clientAddress = ClientAddress(req.centralId);
      if (!_hasEstablishedSession(clientAddress)) {
        _logger.log(
          BlueyLogLevel.info,
          'bluey.server',
          'rejecting read from session-less client (eviction)',
          data: {'clientId': clientAddress.toString()},
        );
        // Reads always need a response.
        _platform.respondToReadRequest(
          req.requestId,
          platform.PlatformGattStatus.lifecycleEviction,
          null,
        );
        return;
      }
      if (!_lifecycle.handleReadRequest(req)) {
        // Reads always need a response — pend until the app responds.
        _lifecycle.requestStarted(clientAddress, req.requestId);
        _filteredReadRequestsController.add(req);
      }
    });

    _platformWriteRequestsSub = _platform.writeRequests.listen((req) {
      final clientAddress = ClientAddress(req.centralId);
      if (!_hasEstablishedSession(clientAddress)) {
        _logger.log(
          BlueyLogLevel.info,
          'bluey.server',
          'rejecting write from session-less client (eviction)',
          data: {'clientId': clientAddress.toString()},
        );
        if (req.responseNeeded) {
          _platform.respondToWriteRequest(
            req.requestId,
            platform.PlatformGattStatus.lifecycleEviction,
          );
        }
        return;
      }
      if (!_lifecycle.handleWriteRequest(req)) {
        if (req.responseNeeded) {
          // Write-with-response — pend until the app responds.
          _lifecycle.requestStarted(clientAddress, req.requestId);
        } else {
          // Write-without-response — no obligation to pend; treat as
          // activity (current behaviour).
          _lifecycle.recordActivity(clientAddress);
        }
        _filteredWriteRequestsController.add(req);
      }
    });

    // I333: invalidate on any non-`on` adapter state. The platform
    // stream emits the platform-interface enum; map to the domain enum
    // before deciding so the carried [triggeringState] surfaces as the
    // domain type. Errors surfaced by the platform stream are treated
    // as invalidation with `unknown` as the triggering state — we
    // don't know the real adapter state, so the conservative choice
    // is to kill the server and force the consumer to recreate.
    _stateSubscription = _platform.stateStream.listen(
      (platformState) {
        final domainState = _mapPlatformState(platformState);
        if (domainState != BluetoothState.on) {
          _invalidate(domainState);
        }
      },
      onError: (_) => _invalidate(BluetoothState.unknown),
    );
  }

  /// Maps the platform-interface [platform.BluetoothState] to the
  /// domain [BluetoothState]. Mirrors `Bluey._mapState`; kept local so
  /// the server doesn't reach across bounded contexts.
  BluetoothState _mapPlatformState(platform.BluetoothState s) {
    switch (s) {
      case platform.BluetoothState.unknown:
        return BluetoothState.unknown;
      case platform.BluetoothState.unsupported:
        return BluetoothState.unsupported;
      case platform.BluetoothState.unauthorized:
        return BluetoothState.unauthorized;
      case platform.BluetoothState.off:
        return BluetoothState.off;
      case platform.BluetoothState.on:
        return BluetoothState.on;
    }
  }

  /// Marks this server as terminal-failed. Idempotent — re-entry is a
  /// no-op. Cancels the state subscription, closes owned streams, and
  /// fails subsequent calls with [StaleHandleException].
  void _invalidate(BluetoothState triggeringState) {
    if (_invalidated) return;
    _invalidated = true;
    _invalidationState = triggeringState;
    _stateSubscription?.cancel();
    _stateSubscription = null;

    // Cancel the platform-event subscriptions so they can't call .add(...)
    // on a closed controller. Android's STATE_TURNING_OFF is regularly
    // followed by a flurry of disconnect / onConnectionStateChange callbacks,
    // which would otherwise crash the listener with a StateError.
    _centralConnectionsSub?.cancel();
    _centralConnectionsSub = null;
    _centralDisconnectionsSub?.cancel();
    _centralDisconnectionsSub = null;
    _platformReadRequestsSub?.cancel();
    _platformReadRequestsSub = null;
    _platformWriteRequestsSub?.cancel();
    _platformWriteRequestsSub = null;

    // Tear down the LifecycleServer so heartbeat timers stop firing. An
    // armed timer firing post-invalidation would hit `onClientGone` →
    // `_handleLifecycleSilence` → `.add(...)` on the now-closed
    // disconnections controller. `dispose()` is idempotent so calling it
    // again from `dispose()` is safe.
    _lifecycle.dispose();

    // Close every StreamController owned by this server.
    _connectionsController.close();
    _disconnectionsController.close();
    _peerConnectionsController.close();
    _filteredReadRequestsController.close();
    _filteredWriteRequestsController.close();

    // Clear cached state — connected clients are gone with the adapter.
    _connectedClients.clear();
    _identifiedPeerClientAddresses.clear();

    // Transition the advertising state machine into its terminal
    // `invalidated` state and close the broadcast controller so the
    // per-subscriber `advertisingStateChanges` streams see `onDone`
    // after delivering the replay. Re-entry into _setAdvertisingState
    // is guarded by the same-state short-circuit.
    _setAdvertisingState(AdvertisingState.invalidated);
    if (!_advertisingStateController.isClosed) {
      _advertisingStateController.close();
    }
  }

  /// Throws [StaleHandleException] if this server has been invalidated
  /// by a prior adapter-state transition.
  void _ensureValid() {
    if (_invalidated) {
      throw StaleHandleException(
        triggeringState: _invalidationState!,
        instanceType: InvalidatedInstance.server,
      );
    }
  }

  @override
  ServerId get serverId => _serverId;

  @override
  AdvertisingState get advertisingState => _advertisingState;

  @override
  Stream<AdvertisingState> get advertisingStateChanges =>
      Stream<AdvertisingState>.multi(
    (controller) {
      // Convention 3 (terminal-signal) — late subscribers after
      // invalidation see the terminal `AdvertisingState.invalidated`
      // value followed by `onDone`. Matches the explicit pattern used
      // in `BlueyConnection.stateChanges` so all Type A streams in
      // bluey share the same late-subscriber shape.
      if (_invalidated) {
        controller.add(AdvertisingState.invalidated);
        controller.close();
        return;
      }
      // Convention 2 (replay-on-subscribe) — replay the current state
      // before bridging future deltas.
      controller.add(_advertisingState);
      final sub = _advertisingStateController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    },
    isBroadcast: true,
  );

  @override
  bool get isAdvertising => _advertisingState == AdvertisingState.advertising;

  /// Transition helper. Pushes the new state onto
  /// [_advertisingStateController] and emits the corresponding lifecycle
  /// event on [_eventBus] when one is defined for the transition.
  /// Idempotent for same-state writes.
  void _setAdvertisingState(AdvertisingState newState) {
    if (_advertisingState == newState) return;
    final old = _advertisingState;
    _advertisingState = newState;
    if (!_advertisingStateController.isClosed) {
      _advertisingStateController.add(newState);
    }
    switch (newState) {
      case AdvertisingState.starting:
        _eventBus.emit(AdvertisingStartingEvent(source: 'BlueyServer'));
      case AdvertisingState.advertising:
        _eventBus.emit(AdvertisingStartedEvent(
          name: _activeAdvertisingName,
          services: _activeAdvertisingServices,
          source: 'BlueyServer',
        ));
      case AdvertisingState.stopping:
        _eventBus.emit(AdvertisingStoppingEvent(source: 'BlueyServer'));
      case AdvertisingState.idle:
        if (old != AdvertisingState.idle) {
          _eventBus.emit(AdvertisingStoppedEvent(source: 'BlueyServer'));
        }
        _activeAdvertisingName = null;
        _activeAdvertisingServices = null;
      case AdvertisingState.invalidated:
        // No event — the advertisingStateChanges terminal close and I333
        // instance invalidation are sufficient signals.
        _activeAdvertisingName = null;
        _activeAdvertisingServices = null;
    }
  }

  @override
  Stream<Client> get connections => _connectionsController.stream;

  @override
  Stream<PeerClient> get peerConnections => _peerConnectionsController.stream;

  @override
  Stream<ClientAddress> get disconnections => _disconnectionsController.stream;

  @override
  List<Client> get connectedClients {
    _ensureValid();
    return _connectedClients.values.toList();
  }

  @override
  bool isClientConnected(ClientAddress address) {
    _ensureValid();
    return _connectedClients.containsKey(address);
  }

  @override
  Future<void> addService(HostedService service) async {
    _ensureValid();
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'addService entered',
      data: {'serviceUuid': service.uuid.toString()},
    );
    // Wait for the eagerly-registered control service to finish before
    // adding app services — Android requires sequential addService calls.
    await _controlServiceReady;
    final platformService = _mapHostedServiceToPlatform(service);

    // Track this addService so startAdvertising can wait for it even if
    // the user fires addService and startAdvertising without awaiting
    // in between.
    final platformFuture = _platform.addService(platformService);
    _pendingServiceAdds.add(platformFuture);
    try {
      final populated = await platformFuture;
      _recordLocalHandles(populated);
      _logger.log(
        BlueyLogLevel.info,
        'bluey.server',
        'addService resolved',
        data: {
          'serviceUuid': service.uuid.toString(),
          'charCount': populated.characteristics.length,
        },
      );
      _emitEvent(
        ServiceAddedEvent(serviceId: service.uuid, source: 'BlueyServer'),
      );
    } catch (e) {
      _logger.log(
        BlueyLogLevel.error,
        'bluey.server',
        'addService failed',
        data: {
          'serviceUuid': service.uuid.toString(),
          'exception': e.runtimeType.toString(),
        },
        errorCode: e.runtimeType.toString(),
      );
      rethrow;
    } finally {
      _pendingServiceAdds.remove(platformFuture);
    }
  }

  /// Walks [populated] and stamps each (serviceUuid, charUuid) ->
  /// handle pair into [_localCharHandles] so subsequent notify /
  /// indicate calls can resolve UUID -> handle. Recurses into included
  /// services.
  void _recordLocalHandles(platform.PlatformLocalService populated) {
    final svcKey = populated.uuid.toLowerCase();
    for (final c in populated.characteristics) {
      _localCharHandles[(svcKey, c.uuid.toLowerCase())] = c.handle;
    }
    for (final inc in populated.includedServices) {
      _recordLocalHandles(inc);
    }
  }

  /// Throws [UnsupportedOperationException] tagged with this server's
  /// platform name when [flag] is false. Used by capability-gated
  /// methods (e.g. `startAdvertising` with manufacturer data) to fail
  /// loudly on platforms that silently ignore the option.
  void _requireCapability(bool flag, String op) {
    if (!flag) {
      throw UnsupportedOperationException(
        op,
        _platform.capabilities.platformKind.name,
      );
    }
  }

  /// Resolves [characteristic] to a platform handle. Falls back to a
  /// scan across every recorded service when the caller hasn't passed a
  /// service UUID — `notify(charUuid)` in the public API only carries
  /// the characteristic UUID. If the same UUID is hosted under multiple
  /// services the first match wins; users that need to disambiguate
  /// should host the UUID under exactly one service.
  int? _resolveLocalHandle(UUID characteristic) {
    final lc = characteristic.toString().toLowerCase();
    for (final entry in _localCharHandles.entries) {
      if (entry.key.$2 == lc) return entry.value;
    }
    return null;
  }

  @override
  Future<void> removeService(UUID uuid) async {
    _ensureValid();
    await _platform.removeService(uuid.toString());
  }

  @override
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
    AdvertiseMode? mode,
    bool peerDiscoverable = false,
  }) async {
    _ensureValid();
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'startAdvertising entered',
      data: {'name': name, 'serviceCount': services?.length ?? 0},
    );
    if (manufacturerData != null) {
      _requireCapability(
        _platform.capabilities.canAdvertiseManufacturerData,
        'startAdvertising(manufacturerData)',
      );
    }
    // Ensure the eagerly-registered control service has completed before
    // advertising. The Future is cached and completes only once.
    await _controlServiceReady;

    // Wait for any user-initiated addService calls still in flight so a
    // central connecting after advertising starts sees the full GATT
    // tree. Failures are reported via the original addService Future;
    // here we just need to let the in-flight call settle before
    // advertising. Snapshot the list because addService removes from
    // _pendingServiceAdds in its finally block.
    final pending = List<Future<void>>.from(_pendingServiceAdds);
    for (final f in pending) {
      try {
        await f;
      } on Object {
        // Surfaced via the original addService Future.
      }
    }

    final primaryUuids =
        services?.map((u) => u.toString().toLowerCase()).toList() ?? [];
    // I313: route the lifecycle control UUID to scan-response (Android's
    // separate 31-byte buffer) so it doesn't compete with the user's UUIDs
    // for the primary-AD budget. iOS ignores scanResponseServiceUuids —
    // CoreBluetooth's overflow area already handles the equivalent.
    //
    // If the caller listed the control UUID explicitly in `services`, we
    // honour that and skip scan-response promotion to avoid emitting the
    // same UUID twice.
    final scanResponseUuids = <String>[
      if (peerDiscoverable &&
          !primaryUuids.contains(lifecycle.controlServiceUuid))
        lifecycle.controlServiceUuid,
    ];
    final config = platform.PlatformAdvertiseConfig(
      name: name,
      serviceUuids: primaryUuids,
      scanResponseServiceUuids: scanResponseUuids,
      manufacturerDataCompanyId: manufacturerData?.companyId,
      manufacturerData: manufacturerData?.data,
      timeoutMs: timeout?.inMilliseconds,
      mode: mode == null ? null : _mapAdvertiseModeToPlatform(mode),
    );

    // Stash the advertise args so `_setAdvertisingState` can ride them
    // through to the emitted AdvertisingStartedEvent. Cleared when we
    // transition back to idle/invalidated.
    _activeAdvertisingName = name;
    _activeAdvertisingServices = services;

    // idle -> starting. Emits AdvertisingStartingEvent via
    // _setAdvertisingState.
    _setAdvertisingState(AdvertisingState.starting);
    try {
      await _platform.startAdvertising(config);
    } catch (_) {
      // Roll back to idle on platform failure. This transition fires
      // AdvertisingStoppedEvent (paired with the AdvertisingStartingEvent
      // already emitted), matching Scanner's behavior on a failed
      // _platform.scan() — consumers see Starting → Stopped without an
      // intervening Started.
      _setAdvertisingState(AdvertisingState.idle);
      rethrow;
    }
    _setAdvertisingState(AdvertisingState.advertising);
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'advertising started',
      data: {'name': name, 'serviceCount': services?.length ?? 0},
    );
  }

  @override
  Future<void> stopAdvertising() async {
    _ensureValid();
    _logger.log(BlueyLogLevel.info, 'bluey.server', 'stopAdvertising invoked');
    // Idempotent: nothing to do unless we are currently advertising.
    if (_advertisingState != AdvertisingState.advertising) return;
    _setAdvertisingState(AdvertisingState.stopping);
    await _platform.stopAdvertising();
    _setAdvertisingState(AdvertisingState.idle);
  }

  @override
  Future<void> notify(UUID characteristic, {required Uint8List data}) async {
    _ensureValid();
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server',
      'notify entered',
      data: {
        'characteristicUuid': characteristic.toString(),
        'length': data.length,
      },
    );
    final handle = _resolveLocalHandle(characteristic);
    if (handle == null) {
      throw CharacteristicNotFoundException(characteristic);
    }
    await withErrorTranslation(
      () => _platform.notifyCharacteristic(handle, data),
      operation: 'notify',
    );
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server',
      'notify resolved',
      data: {
        'characteristicUuid': characteristic.toString(),
        'characteristicHandle': handle,
      },
    );
    _emitEvent(
      NotificationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> notifyTo(
    Client client,
    UUID characteristic, {
    required Uint8List data,
  }) async {
    _ensureValid();
    final blueyClient = client as BlueyClient;
    final handle = _resolveLocalHandle(characteristic);
    if (handle == null) {
      throw CharacteristicNotFoundException(characteristic);
    }
    await withErrorTranslation(
      () => _platform.notifyCharacteristicTo(
        blueyClient.address.value,
        handle,
        data,
      ),
      operation: 'notifyTo',
      address: blueyClient.address.value,
    );
    _emitEvent(
      NotificationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        clientAddress: blueyClient.address,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> indicate(UUID characteristic, {required Uint8List data}) async {
    _ensureValid();
    final handle = _resolveLocalHandle(characteristic);
    if (handle == null) {
      throw CharacteristicNotFoundException(characteristic);
    }
    await withErrorTranslation(
      () => _platform.indicateCharacteristic(handle, data),
      operation: 'indicate',
    );
    _emitEvent(
      IndicationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> indicateTo(
    Client client,
    UUID characteristic, {
    required Uint8List data,
  }) async {
    _ensureValid();
    final blueyClient = client as BlueyClient;
    final handle = _resolveLocalHandle(characteristic);
    if (handle == null) {
      throw CharacteristicNotFoundException(characteristic);
    }
    await withErrorTranslation(
      () => _platform.indicateCharacteristicTo(
        blueyClient.address.value,
        handle,
        data,
      ),
      operation: 'indicateTo',
      address: blueyClient.address.value,
    );
    _emitEvent(
      IndicationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        clientAddress: blueyClient.address,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Stream<ReadRequest> get readRequests {
    return _filteredReadRequestsController.stream.map((platformRequest) {
      final client = _connectedClients[ClientAddress(platformRequest.centralId)];
      if (client == null) {
        throw StateError(
          'Read request from unknown client: ${platformRequest.centralId}',
        );
      }
      return ReadRequest(
        client: client,
        characteristicId: UUID(platformRequest.characteristicUuid),
        offset: platformRequest.offset,
        internalRequestId: platformRequest.requestId,
      );
    });
  }

  @override
  Stream<WriteRequest> get writeRequests {
    return _filteredWriteRequestsController.stream.map((platformRequest) {
      final client = _connectedClients[ClientAddress(platformRequest.centralId)];
      if (client == null) {
        throw StateError(
          'Write request from unknown client: ${platformRequest.centralId}',
        );
      }
      return WriteRequest(
        client: client,
        characteristicId: UUID(platformRequest.characteristicUuid),
        value: platformRequest.value,
        offset: platformRequest.offset,
        responseNeeded: platformRequest.responseNeeded,
        internalRequestId: platformRequest.requestId,
      );
    });
  }

  @override
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  }) async {
    _ensureValid();
    final blueyClient = request.client as BlueyClient;
    final clientAddress = blueyClient.address;
    // Drain pending state BEFORE the platform call so the obligation is
    // discharged even if respondToReadRequest throws (stale request id,
    // platform error, etc.).
    _lifecycle.requestCompleted(clientAddress, request.internalRequestId);
    try {
      await withErrorTranslation(
        () => _platform.respondToReadRequest(
          request.internalRequestId,
          _mapGattResponseStatusToPlatform(status),
          value,
        ),
        operation: 'respondToRead',
        address: clientAddress.value,
      );
    } on GattOperationFailedException catch (e) {
      throw ServerRespondFailedException(
        operation: 'respondToRead',
        status: e.status,
        clientAddress: clientAddress,
        characteristicId: request.characteristicId,
      );
    }
  }

  @override
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  }) async {
    _ensureValid();
    final blueyClient = request.client as BlueyClient;
    final clientAddress = blueyClient.address;
    // Drain pending state BEFORE the platform call — see respondToRead.
    _lifecycle.requestCompleted(clientAddress, request.internalRequestId);
    try {
      await withErrorTranslation(
        () => _platform.respondToWriteRequest(
          request.internalRequestId,
          _mapGattResponseStatusToPlatform(status),
        ),
        operation: 'respondToWrite',
        address: clientAddress.value,
      );
    } on GattOperationFailedException catch (e) {
      throw ServerRespondFailedException(
        operation: 'respondToWrite',
        status: e.status,
        clientAddress: clientAddress,
        characteristicId: request.characteristicId,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (!_invalidated &&
        _advertisingState == AdvertisingState.advertising) {
      await stopAdvertising();
    }

    _lifecycle.dispose();

    // Close the GATT server and disconnect all clients
    // This is important on Android to prevent zombie BLE connections
    await _platform.closeServer();

    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _centralConnectionsSub?.cancel();
    await _centralDisconnectionsSub?.cancel();
    await _platformReadRequestsSub?.cancel();
    await _platformWriteRequestsSub?.cancel();
    // Stream controllers may already be closed by _invalidate; close()
    // is a no-op on an already-closed controller.
    await _connectionsController.close();
    await _peerConnectionsController.close();
    await _disconnectionsController.close();
    await _filteredReadRequestsController.close();
    await _filteredWriteRequestsController.close();
    if (!_advertisingStateController.isClosed) {
      await _advertisingStateController.close();
    }

    _connectedClients.clear();
  }

  /// Tracks a peer client identified through a lifecycle write.
  ///
  /// The platform may not always report connections (Android can miss
  /// onConnectionStateChange for cached connections, iOS has no
  /// connection callback at all). A control-service write proves the
  /// client is connected and — after the I-series wire-format change —
  /// also carries the central's stable [ServerId].
  ///
  /// [PeerClient] is emitted exactly once per identification; subsequent
  /// heartbeats from the same client are no-ops here. The identification
  /// set is cleared in [_handleClientDisconnected] so a reconnect-then-
  /// heartbeat re-identifies.
  void _trackPeerClient(ClientAddress clientAddress, ServerId senderId) {
    // Identification only — never establishes a session. A heartbeat from a
    // client with no established session is rejected at the chokepoint before
    // it can reach here (I338); if one still arrives (defensive), ignore it
    // rather than silently re-creating the client and re-emitting
    // peerConnections.
    final client = _connectedClients[clientAddress];
    if (client == null) return;

    if (_identifiedPeerClientAddresses.add(clientAddress)) {
      _logger.log(
        BlueyLogLevel.info,
        'bluey.server',
        'central identified as Bluey peer',
        data: {'clientId': clientAddress.toString(), 'senderId': senderId.toString()},
      );
      _peerConnectionsController.add(
        PeerClient.create(client: client, serverId: senderId),
      );
    }
  }

  /// Lifecycle heartbeat-silence timeout for [clientAddress].
  ///
  /// Distinct from a real platform disconnect (`_handleClientDisconnected`).
  /// On platforms that report central disconnects natively the silence is
  /// advisory only — the platform callback remains the sole source of
  /// `disconnections`. On inferring platforms (iOS) silence is the disconnect
  /// signal and is forwarded to the disconnect path. (Stage 2 adds session
  /// removal + eviction on the inferring path.)
  void _handleLifecycleSilence(ClientAddress clientAddress) {
    if (_platform.capabilities.reportsCentralDisconnects) {
      // Advisory only. The ClientLifecycleTimeoutEvent was already emitted by
      // LifecycleServer; the platform's onConnectionStateChange will drive any
      // real disconnect. Do not emit disconnections or clear identification.
      return;
    }
    // Inferring platform: silence is the best disconnect signal available.
    _handleClientDisconnected(clientAddress);
  }

  void _handleClientDisconnected(ClientAddress clientAddress) {
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'central disconnected',
      data: {'clientId': clientAddress.toString()},
    );
    // Cancel any heartbeat timer for this client
    _lifecycle.cancelTimer(clientAddress);

    final client = _connectedClients.remove(clientAddress);
    if (client != null) {
      _emitEvent(
        ClientDisconnectedEvent(clientAddress: clientAddress, source: 'BlueyServer'),
      );
    }

    // Clear peer identification — a reconnect-then-heartbeat must
    // re-identify, mirroring the connection-side semantics where
    // `tryUpgrade` is per-connection.
    _identifiedPeerClientAddresses.remove(clientAddress);

    // Always emit on the disconnections stream -- even for untracked clients
    // (e.g., stale connections from before a server restart).
    _disconnectionsController.add(clientAddress);
  }

  platform.PlatformLocalService _mapHostedServiceToPlatform(
    HostedService service,
  ) {
    return platform.PlatformLocalService(
      uuid: service.uuid.toString(),
      isPrimary: service.isPrimary,
      characteristics:
          service.characteristics
              .map(_mapHostedCharacteristicToPlatform)
              .toList(),
      includedServices:
          service.includedServices.map(_mapHostedServiceToPlatform).toList(),
    );
  }

  platform.PlatformLocalCharacteristic _mapHostedCharacteristicToPlatform(
    HostedCharacteristic characteristic,
  ) {
    return platform.PlatformLocalCharacteristic(
      uuid: characteristic.uuid.toString(),
      properties: platform.PlatformCharacteristicProperties(
        canRead: characteristic.properties.canRead,
        canWrite: characteristic.properties.canWrite,
        canWriteWithoutResponse:
            characteristic.properties.canWriteWithoutResponse,
        canNotify: characteristic.properties.canNotify,
        canIndicate: characteristic.properties.canIndicate,
      ),
      permissions:
          characteristic.permissions.map(_mapGattPermissionToPlatform).toList(),
      descriptors:
          characteristic.descriptors
              .map(_mapHostedDescriptorToPlatform)
              .toList(),
    );
  }

  platform.PlatformLocalDescriptor _mapHostedDescriptorToPlatform(
    HostedDescriptor descriptor,
  ) {
    return platform.PlatformLocalDescriptor(
      uuid: descriptor.uuid.toString(),
      permissions:
          descriptor.permissions.map(_mapGattPermissionToPlatform).toList(),
      value: descriptor.value,
    );
  }

  platform.PlatformGattPermission _mapGattPermissionToPlatform(
    GattPermission permission,
  ) {
    switch (permission) {
      case GattPermission.read:
        return platform.PlatformGattPermission.read;
      case GattPermission.readEncrypted:
        return platform.PlatformGattPermission.readEncrypted;
      case GattPermission.write:
        return platform.PlatformGattPermission.write;
      case GattPermission.writeEncrypted:
        return platform.PlatformGattPermission.writeEncrypted;
    }
  }

  platform.PlatformAdvertiseMode _mapAdvertiseModeToPlatform(
    AdvertiseMode mode,
  ) {
    switch (mode) {
      case AdvertiseMode.lowPower:
        return platform.PlatformAdvertiseMode.lowPower;
      case AdvertiseMode.balanced:
        return platform.PlatformAdvertiseMode.balanced;
      case AdvertiseMode.lowLatency:
        return platform.PlatformAdvertiseMode.lowLatency;
    }
  }

  platform.PlatformGattStatus _mapGattResponseStatusToPlatform(
    GattResponseStatus status,
  ) {
    switch (status) {
      case GattResponseStatus.success:
        return platform.PlatformGattStatus.success;
      case GattResponseStatus.readNotPermitted:
        return platform.PlatformGattStatus.readNotPermitted;
      case GattResponseStatus.writeNotPermitted:
        return platform.PlatformGattStatus.writeNotPermitted;
      case GattResponseStatus.invalidOffset:
        return platform.PlatformGattStatus.invalidOffset;
      case GattResponseStatus.invalidAttributeLength:
        return platform.PlatformGattStatus.invalidAttributeLength;
      case GattResponseStatus.insufficientAuthentication:
        return platform.PlatformGattStatus.insufficientAuthentication;
      case GattResponseStatus.insufficientEncryption:
        return platform.PlatformGattStatus.insufficientEncryption;
      case GattResponseStatus.requestNotSupported:
        return platform.PlatformGattStatus.requestNotSupported;
    }
  }

  void _emitEvent(BlueyEvent event) {
    _eventBus.emit(event);
  }
}

/// Concrete implementation of [Client].
///
/// Wraps a `PlatformCentral` from the platform-interface layer for use
/// inside the GATT-Server bounded context, where the connected GATT
/// central is named `Client` (not `Central`). The translation is
/// intentional: domain vocabulary is bounded-context-aligned, while the
/// platform interface follows the BLE-spec terms. See the Ubiquitous
/// Language section in `CLAUDE.md`.
class BlueyClient implements Client {
  final ClientAddress _address;
  final int _mtu;

  BlueyClient({required ClientAddress address, required int mtu})
    : _address = address,
      _mtu = mtu;

  @override
  ClientAddress get address => _address;

  @override
  int get mtu => _mtu;
}
