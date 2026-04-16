import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../lifecycle.dart' as lifecycle;
import '../peer/server_id.dart';
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import 'lifecycle_server.dart';
import 'server.dart';

/// Concrete implementation of [Server] that delegates to the platform.
class BlueyServer implements Server {
  final platform.BlueyPlatform _platform;
  final BlueyEventBus _eventBus;
  final ServerId _serverId;
  late final LifecycleServer _lifecycle;
  late final Future<void> _controlServiceReady;

  bool _isAdvertising = false;
  final Map<String, BlueyClient> _connectedClients = {};

  final StreamController<Client> _connectionsController =
      StreamController<Client>.broadcast();
  final StreamController<String> _disconnectionsController =
      StreamController<String>.broadcast();

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
    Duration? lifecycleInterval = lifecycle.defaultLifecycleInterval,
    ServerId? identity,
  }) : _serverId = identity ?? ServerId.generate() {
    _lifecycle = LifecycleServer(
      platformApi: _platform,
      interval: lifecycleInterval,
      serverId: _serverId,
      onClientGone: _handleClientDisconnected,
      onHeartbeatReceived: _trackClientIfNeeded,
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

    _emitEvent(ServerStartedEvent(source: 'BlueyServer'));

    _centralConnectionsSub = _platform.centralConnections.listen((
      platformCentral,
    ) {
      _emitEvent(
        ClientConnectedEvent(
          clientId: platformCentral.id,
          mtu: platformCentral.mtu,
          source: 'BlueyServer',
        ),
      );
      final client = BlueyClient(
        platform: _platform,
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
        _filteredReadRequestsController.add(req);
      }
    });

    _platformWriteRequestsSub = _platform.writeRequests.listen((req) {
      if (!_lifecycle.handleWriteRequest(req)) {
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
  Stream<String> get disconnections => _disconnectionsController.stream;

  @override
  List<Client> get connectedClients => _connectedClients.values.toList();

  @override
  Future<void> addService(HostedService service) async {
    // Wait for the eagerly-registered control service to finish before
    // adding app services — Android requires sequential addService calls.
    await _controlServiceReady;
    final platformService = _mapHostedServiceToPlatform(service);
    await _platform.addService(platformService);
    _emitEvent(
      ServiceAddedEvent(serviceId: service.uuid, source: 'BlueyServer'),
    );
  }

  @override
  void removeService(UUID uuid) {
    _platform.removeService(uuid.toString());
  }

  @override
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  }) async {
    // Ensure the eagerly-registered control service has completed before
    // advertising. The Future is cached and completes only once.
    await _controlServiceReady;

    final config = platform.PlatformAdvertiseConfig(
      name: name,
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      manufacturerDataCompanyId: manufacturerData?.companyId,
      manufacturerData: manufacturerData?.data,
      timeoutMs: timeout?.inMilliseconds,
    );

    await _platform.startAdvertising(config);
    _isAdvertising = true;
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
    await _platform.stopAdvertising();
    _isAdvertising = false;
    _emitEvent(AdvertisingStoppedEvent(source: 'BlueyServer'));
  }

  @override
  Future<void> notify(UUID characteristic, {required Uint8List data}) async {
    await _platform.notifyCharacteristic(characteristic.toString(), data);
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
    await _platform.notifyCharacteristicTo(
      blueyClient._platformId,
      characteristic.toString(),
      data,
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
    await _platform.indicateCharacteristic(characteristic.toString(), data);
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
    await _platform.indicateCharacteristicTo(
      blueyClient._platformId,
      characteristic.toString(),
      data,
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
    await _platform.respondToReadRequest(
      request.internalRequestId,
      _mapGattResponseStatusToPlatform(status),
      value,
    );
  }

  @override
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  }) async {
    await _platform.respondToWriteRequest(
      request.internalRequestId,
      _mapGattResponseStatusToPlatform(status),
    );
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
    await _disconnectionsController.close();
    await _filteredReadRequestsController.close();
    await _filteredWriteRequestsController.close();

    _connectedClients.clear();
  }

  // === Client tracking ===

  /// Tracks a client if not already known. The platform may not always report
  /// connections (Android can miss onConnectionStateChange for cached
  /// connections, iOS has no connection callback at all). A control service
  /// write proves the client is connected.
  void _trackClientIfNeeded(String clientId) {
    if (_connectedClients.containsKey(clientId)) return;

    _emitEvent(
      ClientConnectedEvent(
        clientId: clientId,
        source: 'BlueyServer',
      ),
    );
    final client = BlueyClient(
      platform: _platform,
      id: clientId,
      mtu: 23, // Default MTU — actual MTU is unknown without platform event
    );
    _connectedClients[clientId] = client;
    _connectionsController.add(client);
  }

  // === Lifecycle management ===

  void _handleClientDisconnected(String clientId) {
    // Cancel any heartbeat timer for this client
    _lifecycle.cancelTimer(clientId);

    final client = _connectedClients.remove(clientId);
    if (client != null) {
      _emitEvent(
        ClientDisconnectedEvent(clientId: clientId, source: 'BlueyServer'),
      );
    }

    // Always emit on the disconnections stream -- even for untracked clients
    // (e.g., stale connections from before a server restart).
    _disconnectionsController.add(clientId);
  }

  // === Private mapping methods ===

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
class BlueyClient implements Client {
  final platform.BlueyPlatform _platform;
  final String _platformId;
  final int _mtu;

  BlueyClient({
    required platform.BlueyPlatform platform,
    required String id,
    required int mtu,
  }) : _platform = platform,
       _platformId = id,
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

  @override
  Future<void> disconnect() async {
    await _platform.disconnectCentral(_platformId);
  }
}
