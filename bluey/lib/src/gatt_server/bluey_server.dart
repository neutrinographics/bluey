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

  bool _isAdvertising = false;
  final Map<String, BlueyClient> _connectedClients = {};

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
  final StreamController<String> _disconnectionsController =
      StreamController<String>.broadcast();

  /// Set of clientIds that have been identified as Bluey peers (i.e.
  /// have sent at least one lifecycle heartbeat in the current
  /// session). Used to fire [PeerClient] emissions exactly once per
  /// identification — not once per heartbeat. Cleared on disconnect so
  /// a reconnect-then-heartbeat re-identifies.
  final Set<String> _identifiedPeerClientIds = {};

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
      onClientGone: _handleClientDisconnected,
      onHeartbeatReceived: _trackClientIfNeeded,
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
      _logger.log(
        BlueyLogLevel.info,
        'bluey.server',
        'central connected',
        data: {'clientId': platformCentral.id, 'mtu': platformCentral.mtu},
      );
      _emitEvent(
        ClientConnectedEvent(
          clientId: platformCentral.id,
          mtu: platformCentral.mtu,
          source: 'BlueyServer',
        ),
      );
      final client = BlueyClient(
        id: platformCentral.id,
        mtu: platformCentral.mtu,
      );
      _connectedClients[platformCentral.id] = client;
      _connectionsController.add(client);
      // No heartbeat timer here. The timer starts only when the client sends
      // its first heartbeat write, proving it speaks the lifecycle protocol.
      // Clients that never heartbeat (non-Bluey centrals) are never timed out
      // and remain connected until the platform reports a real disconnection.
    });

    _centralDisconnectionsSub = _platform.centralDisconnections.listen((
      clientId,
    ) {
      _handleClientDisconnected(clientId);
    });

    // Subscribe to platform request streams and route internally.
    // Control service requests are handled here; all others are forwarded
    // to the filtered controllers for the public API.
    _platformReadRequestsSub = _platform.readRequests.listen((req) {
      if (!_lifecycle.handleReadRequest(req)) {
        // Reads always need a response — pend until the app responds.
        _lifecycle.requestStarted(req.centralId, req.requestId);
        _filteredReadRequestsController.add(req);
      }
    });

    _platformWriteRequestsSub = _platform.writeRequests.listen((req) {
      if (!_lifecycle.handleWriteRequest(req)) {
        if (req.responseNeeded) {
          // Write-with-response — pend until the app responds.
          _lifecycle.requestStarted(req.centralId, req.requestId);
        } else {
          // Write-without-response — no obligation to pend; treat as
          // activity (current behaviour).
          _lifecycle.recordActivity(req.centralId);
        }
        _filteredWriteRequestsController.add(req);
      }
    });
  }

  @override
  ServerId get serverId => _serverId;

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Stream<Client> get connections => _connectionsController.stream;

  @override
  Stream<PeerClient> get peerConnections => _peerConnectionsController.stream;

  @override
  Stream<String> get disconnections => _disconnectionsController.stream;

  @override
  List<Client> get connectedClients => _connectedClients.values.toList();

  @override
  Future<void> addService(HostedService service) async {
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

    final advertisedUuids =
        services?.map((u) => u.toString().toLowerCase()).toList() ?? [];
    if (peerDiscoverable &&
        !advertisedUuids.contains(lifecycle.controlServiceUuid)) {
      advertisedUuids.insert(0, lifecycle.controlServiceUuid);
    }
    final config = platform.PlatformAdvertiseConfig(
      name: name,
      serviceUuids: advertisedUuids,
      manufacturerDataCompanyId: manufacturerData?.companyId,
      manufacturerData: manufacturerData?.data,
      timeoutMs: timeout?.inMilliseconds,
      mode: mode == null ? null : _mapAdvertiseModeToPlatform(mode),
    );

    await _platform.startAdvertising(config);
    _isAdvertising = true;
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'advertising started',
      data: {'name': name, 'serviceCount': services?.length ?? 0},
    );
    _emitEvent(
      AdvertisingStartedEvent(
        name: name,
        services: services,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> stopAdvertising() async {
    _logger.log(BlueyLogLevel.info, 'bluey.server', 'stopAdvertising invoked');
    await _platform.stopAdvertising();
    _isAdvertising = false;
    _emitEvent(AdvertisingStoppedEvent(source: 'BlueyServer'));
  }

  @override
  Future<void> notify(UUID characteristic, {required Uint8List data}) async {
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
    final blueyClient = client as BlueyClient;
    final handle = _resolveLocalHandle(characteristic);
    if (handle == null) {
      throw CharacteristicNotFoundException(characteristic);
    }
    await withErrorTranslation(
      () => _platform.notifyCharacteristicTo(
        blueyClient._platformId,
        handle,
        data,
      ),
      operation: 'notifyTo',
      deviceId: client.id,
    );
    _emitEvent(
      NotificationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        clientId: blueyClient._platformId,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> indicate(UUID characteristic, {required Uint8List data}) async {
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
    final blueyClient = client as BlueyClient;
    final handle = _resolveLocalHandle(characteristic);
    if (handle == null) {
      throw CharacteristicNotFoundException(characteristic);
    }
    await withErrorTranslation(
      () => _platform.indicateCharacteristicTo(
        blueyClient._platformId,
        handle,
        data,
      ),
      operation: 'indicateTo',
      deviceId: client.id,
    );
    _emitEvent(
      IndicationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        clientId: blueyClient._platformId,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Stream<ReadRequest> get readRequests {
    return _filteredReadRequestsController.stream.map((platformRequest) {
      final client = _connectedClients[platformRequest.centralId];
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
      final client = _connectedClients[platformRequest.centralId];
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
    final clientId = (request.client as BlueyClient)._platformId;
    // Drain pending state BEFORE the platform call so the obligation is
    // discharged even if respondToReadRequest throws (stale request id,
    // platform error, etc.).
    _lifecycle.requestCompleted(clientId, request.internalRequestId);
    try {
      await withErrorTranslation(
        () => _platform.respondToReadRequest(
          request.internalRequestId,
          _mapGattResponseStatusToPlatform(status),
          value,
        ),
        operation: 'respondToRead',
        deviceId: request.client.id,
      );
    } on GattOperationFailedException catch (e) {
      throw ServerRespondFailedException(
        operation: 'respondToRead',
        status: e.status,
        clientId: request.client.id,
        characteristicId: request.characteristicId,
      );
    }
  }

  @override
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  }) async {
    final clientId = (request.client as BlueyClient)._platformId;
    // Drain pending state BEFORE the platform call — see respondToRead.
    _lifecycle.requestCompleted(clientId, request.internalRequestId);
    try {
      await withErrorTranslation(
        () => _platform.respondToWriteRequest(
          request.internalRequestId,
          _mapGattResponseStatusToPlatform(status),
        ),
        operation: 'respondToWrite',
        deviceId: request.client.id,
      );
    } on GattOperationFailedException catch (e) {
      throw ServerRespondFailedException(
        operation: 'respondToWrite',
        status: e.status,
        clientId: request.client.id,
        characteristicId: request.characteristicId,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_isAdvertising) {
      await stopAdvertising();
    }

    _lifecycle.dispose();

    // Close the GATT server and disconnect all clients
    // This is important on Android to prevent zombie BLE connections
    await _platform.closeServer();

    await _centralConnectionsSub?.cancel();
    await _centralDisconnectionsSub?.cancel();
    await _platformReadRequestsSub?.cancel();
    await _platformWriteRequestsSub?.cancel();
    await _connectionsController.close();
    await _peerConnectionsController.close();
    await _disconnectionsController.close();
    await _filteredReadRequestsController.close();
    await _filteredWriteRequestsController.close();

    _connectedClients.clear();
  }

  /// Tracks a client if not already known. The platform may not always report
  /// connections (Android can miss onConnectionStateChange for cached
  /// connections, iOS has no connection callback at all). A control service
  /// write proves the client is connected.
  void _trackClientIfNeeded(String clientId) {
    final wasNew = !_connectedClients.containsKey(clientId);
    if (wasNew) {
      _emitEvent(
        ClientConnectedEvent(clientId: clientId, source: 'BlueyServer'),
      );
      final client = BlueyClient(
        id: clientId,
        mtu: 23, // Default MTU — actual MTU is unknown without platform event
      );
      _connectedClients[clientId] = client;
      _connectionsController.add(client);
    }

    // Peer identification: this hook fires on every lifecycle heartbeat
    // write, but [PeerClient] is emitted exactly once per identification.
    // Subsequent heartbeats from the same client are no-ops here. The
    // identification set is cleared in [_handleClientDisconnected] so a
    // reconnect-then-heartbeat re-identifies.
    if (_identifiedPeerClientIds.add(clientId)) {
      final client = _connectedClients[clientId]!;
      _logger.log(
        BlueyLogLevel.info,
        'bluey.server',
        'central identified as Bluey peer',
        data: {'clientId': clientId},
      );
      _peerConnectionsController.add(PeerClient.create(client: client));
    }
  }

  void _handleClientDisconnected(String clientId) {
    _logger.log(
      BlueyLogLevel.info,
      'bluey.server',
      'central disconnected',
      data: {'clientId': clientId},
    );
    // Cancel any heartbeat timer for this client
    _lifecycle.cancelTimer(clientId);

    final client = _connectedClients.remove(clientId);
    if (client != null) {
      _emitEvent(
        ClientDisconnectedEvent(clientId: clientId, source: 'BlueyServer'),
      );
    }

    // Clear peer identification — a reconnect-then-heartbeat must
    // re-identify, mirroring the connection-side semantics where
    // `tryUpgrade` is per-connection.
    _identifiedPeerClientIds.remove(clientId);

    // Always emit on the disconnections stream -- even for untracked clients
    // (e.g., stale connections from before a server restart).
    _disconnectionsController.add(clientId);
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
  final String _platformId;
  final int _mtu;

  BlueyClient({required String id, required int mtu})
    : _platformId = id,
      _mtu = mtu;

  @override
  UUID get id {
    // Convert the platform ID to a UUID
    // If it's already a UUID format, use it directly
    if (_platformId.length == 36 && _platformId.contains('-')) {
      return UUID(_platformId);
    }
    // Otherwise, create a UUID from the string by padding
    final bytes = _platformId.codeUnits;
    final padded = List<int>.filled(16, 0);
    for (var i = 0; i < bytes.length && i < 16; i++) {
      padded[i] = bytes[i];
    }
    // Convert to hex string
    final hex = padded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return UUID(hex);
  }

  @override
  int get mtu => _mtu;
}
