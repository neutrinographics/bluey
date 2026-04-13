import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'android_scanner.dart';
import 'messages.g.dart';

/// Android implementation of [BlueyPlatform].
final class BlueyAndroid extends BlueyPlatform {
  /// Registers this class as the default instance of [BlueyPlatform].
  static void registerWith() {
    BlueyPlatform.instance = BlueyAndroid();
  }

  final BlueyHostApi _hostApi = BlueyHostApi();
  final _BlueyFlutterApiImpl _flutterApi = _BlueyFlutterApiImpl();
  late final AndroidScanner _scanner = AndroidScanner(_hostApi);

  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();
  final Map<String, StreamController<PlatformConnectionState>>
  _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
  _notificationControllers = {};

  // Server (peripheral) streams
  final StreamController<PlatformCentral> _centralConnectionsController =
      StreamController<PlatformCentral>.broadcast();
  final StreamController<String> _centralDisconnectionsController =
      StreamController<String>.broadcast();
  final StreamController<PlatformReadRequest> _readRequestsController =
      StreamController<PlatformReadRequest>.broadcast();
  final StreamController<PlatformWriteRequest> _writeRequestsController =
      StreamController<PlatformWriteRequest>.broadcast();

  bool _isInitialized = false;

  BlueyAndroid() : super.impl();

  /// Lazily initializes the Flutter API setup.
  /// This is deferred because the Flutter binding may not be ready
  /// when registerWith() is called during plugin registration.
  void _ensureInitialized() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Set up the Flutter API to receive callbacks from platform
    BlueyFlutterApi.setUp(_flutterApi);

    // Wire up callbacks to our streams
    _flutterApi.onStateChangedCallback = (state) {
      _stateController.add(_mapBluetoothState(state));
    };

    _flutterApi.onDeviceDiscoveredCallback = (device) {
      _scanner.onDeviceDiscovered(device);
    };

    _flutterApi.onScanCompleteCallback = () {
      _scanner.onScanComplete();
    };

    _flutterApi.onConnectionStateChangedCallback = (event) {
      final controller = _connectionStateControllers[event.deviceId];
      if (controller != null) {
        controller.add(_mapConnectionState(event.state));
      }
    };

    _flutterApi.onNotificationCallback = (event) {
      final controller = _notificationControllers[event.deviceId];
      if (controller != null) {
        controller.add(
          PlatformNotification(
            deviceId: event.deviceId,
            characteristicUuid: event.characteristicUuid,
            value: event.value,
          ),
        );
      }
    };

    _flutterApi.onMtuChangedCallback = (event) {
      // MTU change is also reflected through the callback
      // Currently we don't expose this as a separate stream
    };

    // Server (peripheral) callbacks
    _flutterApi.onCentralConnectedCallback = (central) {
      _centralConnectionsController.add(
        PlatformCentral(id: central.id, mtu: central.mtu),
      );
    };

    _flutterApi.onCentralDisconnectedCallback = (centralId) {
      _centralDisconnectionsController.add(centralId);
    };

    _flutterApi.onReadRequestCallback = (request) {
      _readRequestsController.add(
        PlatformReadRequest(
          requestId: request.requestId,
          centralId: request.centralId,
          characteristicUuid: request.characteristicUuid,
          offset: request.offset,
        ),
      );
    };

    _flutterApi.onWriteRequestCallback = (request) {
      _writeRequestsController.add(
        PlatformWriteRequest(
          requestId: request.requestId,
          centralId: request.centralId,
          characteristicUuid: request.characteristicUuid,
          value: request.value,
          offset: request.offset,
          responseNeeded: request.responseNeeded,
        ),
      );
    };

    _flutterApi.onCharacteristicSubscribedCallback = (
      centralId,
      characteristicUuid,
    ) {
      // Could expose this as a stream if needed
    };

    _flutterApi.onCharacteristicUnsubscribedCallback = (
      centralId,
      characteristicUuid,
    ) {
      // Could expose this as a stream if needed
    };
  }

  @override
  Capabilities get capabilities => Capabilities.android;

  @override
  Future<void> configure(BlueyConfig config) async {
    _ensureInitialized();
    final dto = BlueyConfigDto(
      cleanupOnActivityDestroy: config.cleanupOnActivityDestroy,
    );
    await _hostApi.configure(dto);
  }

  @override
  Stream<BluetoothState> get stateStream {
    _ensureInitialized();
    return _stateController.stream;
  }

  @override
  Future<BluetoothState> getState() async {
    _ensureInitialized();
    final state = await _hostApi.getState();
    return _mapBluetoothState(state);
  }

  @override
  Future<bool> requestEnable() async {
    _ensureInitialized();
    return await _hostApi.requestEnable();
  }

  @override
  Future<bool> authorize() async {
    _ensureInitialized();
    return await _hostApi.authorize();
  }

  @override
  Future<void> openSettings() async {
    _ensureInitialized();
    await _hostApi.openSettings();
  }

  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    _ensureInitialized();
    return _scanner.scan(config);
  }

  @override
  Future<void> stopScan() async {
    _ensureInitialized();
    await _scanner.stopScan();
  }

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    _ensureInitialized();
    final dto = ConnectConfigDto(timeoutMs: config.timeoutMs, mtu: config.mtu);

    // Create connection state controller for this device
    _connectionStateControllers[deviceId] =
        StreamController<PlatformConnectionState>.broadcast();

    // Create notification controller for this device
    _notificationControllers[deviceId] =
        StreamController<PlatformNotification>.broadcast();

    return await _hostApi.connect(deviceId, dto);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _ensureInitialized();
    await _hostApi.disconnect(deviceId);

    // Clean up connection state controller
    final stateController = _connectionStateControllers.remove(deviceId);
    await stateController?.close();

    // Clean up notification controller
    final notificationController = _notificationControllers.remove(deviceId);
    await notificationController?.close();
  }

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    _ensureInitialized();
    final controller = _connectionStateControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  // === GATT Operations ===

  @override
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    _ensureInitialized();
    final services = await _hostApi.discoverServices(deviceId);
    return services.map(_mapService).toList();
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    _ensureInitialized();
    return await _hostApi.readCharacteristic(deviceId, characteristicUuid);
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    _ensureInitialized();
    await _hostApi.writeCharacteristic(
      deviceId,
      characteristicUuid,
      value,
      withResponse,
    );
  }

  @override
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {
    _ensureInitialized();
    await _hostApi.setNotification(deviceId, characteristicUuid, enable);
  }

  @override
  Stream<PlatformNotification> notificationStream(String deviceId) {
    _ensureInitialized();
    final controller = _notificationControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    _ensureInitialized();
    return await _hostApi.readDescriptor(deviceId, descriptorUuid);
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _hostApi.writeDescriptor(deviceId, descriptorUuid, value);
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    _ensureInitialized();
    return await _hostApi.requestMtu(deviceId, mtu);
  }

  @override
  Future<int> readRssi(String deviceId) async {
    _ensureInitialized();
    return await _hostApi.readRssi(deviceId);
  }

  // === Bonding ===

  @override
  Future<PlatformBondState> getBondState(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports bonding
    return PlatformBondState.none;
  }

  @override
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    // TODO: Implement when Android Pigeon API supports bonding
    return const Stream.empty();
  }

  @override
  Future<void> bond(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports bonding
  }

  @override
  Future<void> removeBond(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports bonding
  }

  @override
  Future<List<PlatformDevice>> getBondedDevices() async {
    // TODO: Implement when Android Pigeon API supports bonding
    return [];
  }

  // === PHY ===

  @override
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports PHY
    return (tx: PlatformPhy.le1m, rx: PlatformPhy.le1m);
  }

  @override
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    // TODO: Implement when Android Pigeon API supports PHY
    return const Stream.empty();
  }

  @override
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    // TODO: Implement when Android Pigeon API supports PHY
  }

  // === Connection Parameters ===

  @override
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    // TODO: Implement when Android Pigeon API supports connection parameters
    return const PlatformConnectionParameters(
      intervalMs: 30,
      latency: 0,
      timeoutMs: 5000,
    );
  }

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    // TODO: Implement when Android Pigeon API supports connection parameters
  }

  // === Server (Peripheral) Operations ===

  @override
  Future<void> addService(PlatformLocalService service) async {
    _ensureInitialized();
    final dto = _mapLocalServiceToDto(service);
    await _hostApi.addService(dto);
  }

  @override
  Future<void> removeService(String serviceUuid) async {
    _ensureInitialized();
    await _hostApi.removeService(serviceUuid);
  }

  @override
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
    _ensureInitialized();
    final dto = AdvertiseConfigDto(
      name: config.name,
      serviceUuids: config.serviceUuids,
      manufacturerDataCompanyId: config.manufacturerDataCompanyId,
      manufacturerData: config.manufacturerData,
      timeoutMs: config.timeoutMs,
      mode: _mapAdvertiseModeToDto(config.mode),
    );
    await _hostApi.startAdvertising(dto);
  }

  AdvertiseModeDto? _mapAdvertiseModeToDto(PlatformAdvertiseMode? mode) {
    if (mode == null) return null;
    switch (mode) {
      case PlatformAdvertiseMode.lowPower:
        return AdvertiseModeDto.lowPower;
      case PlatformAdvertiseMode.balanced:
        return AdvertiseModeDto.balanced;
      case PlatformAdvertiseMode.lowLatency:
        return AdvertiseModeDto.lowLatency;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    _ensureInitialized();
    await _hostApi.stopAdvertising();
  }

  @override
  Future<void> notifyCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _hostApi.notifyCharacteristic(characteristicUuid, value);
  }

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _hostApi.notifyCharacteristicTo(centralId, characteristicUuid, value);
  }

  @override
  Future<void> indicateCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {
    _ensureInitialized();
    // Android uses the same API for notifications and indications
    // The characteristic's properties determine which is used
    await _hostApi.notifyCharacteristic(characteristicUuid, value);
  }

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _hostApi.notifyCharacteristicTo(centralId, characteristicUuid, value);
  }

  @override
  Stream<PlatformCentral> get centralConnections {
    _ensureInitialized();
    return _centralConnectionsController.stream;
  }

  @override
  Stream<String> get centralDisconnections {
    _ensureInitialized();
    return _centralDisconnectionsController.stream;
  }

  @override
  Stream<PlatformReadRequest> get readRequests {
    _ensureInitialized();
    return _readRequestsController.stream;
  }

  @override
  Stream<PlatformWriteRequest> get writeRequests {
    _ensureInitialized();
    return _writeRequestsController.stream;
  }

  @override
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    _ensureInitialized();
    await _hostApi.respondToReadRequest(
      requestId,
      _mapGattStatusToDto(status),
      value,
    );
  }

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    PlatformGattStatus status,
  ) async {
    _ensureInitialized();
    await _hostApi.respondToWriteRequest(
      requestId,
      _mapGattStatusToDto(status),
    );
  }

  @override
  Future<void> disconnectCentral(String centralId) async {
    _ensureInitialized();
    await _hostApi.disconnectCentral(centralId);
  }

  @override
  Future<void> closeServer() async {
    _ensureInitialized();
    await _hostApi.closeServer();
  }

  // Mapping functions from DTOs to platform interface types

  BluetoothState _mapBluetoothState(BluetoothStateDto dto) {
    switch (dto) {
      case BluetoothStateDto.unknown:
        return BluetoothState.unknown;
      case BluetoothStateDto.unsupported:
        return BluetoothState.unsupported;
      case BluetoothStateDto.unauthorized:
        return BluetoothState.unauthorized;
      case BluetoothStateDto.off:
        return BluetoothState.off;
      case BluetoothStateDto.on:
        return BluetoothState.on;
    }
  }

  PlatformConnectionState _mapConnectionState(ConnectionStateDto dto) {
    switch (dto) {
      case ConnectionStateDto.disconnected:
        return PlatformConnectionState.disconnected;
      case ConnectionStateDto.connecting:
        return PlatformConnectionState.connecting;
      case ConnectionStateDto.connected:
        return PlatformConnectionState.connected;
      case ConnectionStateDto.disconnecting:
        return PlatformConnectionState.disconnecting;
    }
  }

  PlatformService _mapService(ServiceDto dto) {
    return PlatformService(
      uuid: dto.uuid,
      isPrimary: dto.isPrimary,
      characteristics: dto.characteristics.map(_mapCharacteristic).toList(),
      includedServices: dto.includedServices.map(_mapService).toList(),
    );
  }

  PlatformCharacteristic _mapCharacteristic(CharacteristicDto dto) {
    return PlatformCharacteristic(
      uuid: dto.uuid,
      properties: PlatformCharacteristicProperties(
        canRead: dto.properties.canRead,
        canWrite: dto.properties.canWrite,
        canWriteWithoutResponse: dto.properties.canWriteWithoutResponse,
        canNotify: dto.properties.canNotify,
        canIndicate: dto.properties.canIndicate,
      ),
      descriptors: dto.descriptors.map(_mapDescriptor).toList(),
    );
  }

  PlatformDescriptor _mapDescriptor(DescriptorDto dto) {
    return PlatformDescriptor(uuid: dto.uuid);
  }

  // Mapping functions for Server types

  LocalServiceDto _mapLocalServiceToDto(PlatformLocalService service) {
    return LocalServiceDto(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics:
          service.characteristics.map(_mapLocalCharacteristicToDto).toList(),
      includedServices:
          service.includedServices.map(_mapLocalServiceToDto).toList(),
    );
  }

  LocalCharacteristicDto _mapLocalCharacteristicToDto(
    PlatformLocalCharacteristic characteristic,
  ) {
    return LocalCharacteristicDto(
      uuid: characteristic.uuid,
      properties: CharacteristicPropertiesDto(
        canRead: characteristic.properties.canRead,
        canWrite: characteristic.properties.canWrite,
        canWriteWithoutResponse:
            characteristic.properties.canWriteWithoutResponse,
        canNotify: characteristic.properties.canNotify,
        canIndicate: characteristic.properties.canIndicate,
      ),
      permissions:
          characteristic.permissions.map(_mapGattPermissionToDto).toList(),
      descriptors:
          characteristic.descriptors.map(_mapLocalDescriptorToDto).toList(),
    );
  }

  LocalDescriptorDto _mapLocalDescriptorToDto(
    PlatformLocalDescriptor descriptor,
  ) {
    return LocalDescriptorDto(
      uuid: descriptor.uuid,
      permissions: descriptor.permissions.map(_mapGattPermissionToDto).toList(),
      value: descriptor.value,
    );
  }

  GattPermissionDto _mapGattPermissionToDto(PlatformGattPermission permission) {
    switch (permission) {
      case PlatformGattPermission.read:
        return GattPermissionDto.read;
      case PlatformGattPermission.readEncrypted:
        return GattPermissionDto.readEncrypted;
      case PlatformGattPermission.write:
        return GattPermissionDto.write;
      case PlatformGattPermission.writeEncrypted:
        return GattPermissionDto.writeEncrypted;
    }
  }

  GattStatusDto _mapGattStatusToDto(PlatformGattStatus status) {
    switch (status) {
      case PlatformGattStatus.success:
        return GattStatusDto.success;
      case PlatformGattStatus.readNotPermitted:
        return GattStatusDto.readNotPermitted;
      case PlatformGattStatus.writeNotPermitted:
        return GattStatusDto.writeNotPermitted;
      case PlatformGattStatus.invalidOffset:
        return GattStatusDto.invalidOffset;
      case PlatformGattStatus.invalidAttributeLength:
        return GattStatusDto.invalidAttributeLength;
      case PlatformGattStatus.insufficientAuthentication:
        return GattStatusDto.insufficientAuthentication;
      case PlatformGattStatus.insufficientEncryption:
        return GattStatusDto.insufficientEncryption;
      case PlatformGattStatus.requestNotSupported:
        return GattStatusDto.requestNotSupported;
    }
  }
}

/// Implementation of Flutter API that receives callbacks from platform.
class _BlueyFlutterApiImpl implements BlueyFlutterApi {
  void Function(BluetoothStateDto)? onStateChangedCallback;
  void Function(DeviceDto)? onDeviceDiscoveredCallback;
  void Function()? onScanCompleteCallback;
  void Function(ConnectionStateEventDto)? onConnectionStateChangedCallback;
  void Function(NotificationEventDto)? onNotificationCallback;
  void Function(MtuChangedEventDto)? onMtuChangedCallback;

  // Server (peripheral) callbacks
  void Function(CentralDto)? onCentralConnectedCallback;
  void Function(String)? onCentralDisconnectedCallback;
  void Function(ReadRequestDto)? onReadRequestCallback;
  void Function(WriteRequestDto)? onWriteRequestCallback;
  void Function(String, String)? onCharacteristicSubscribedCallback;
  void Function(String, String)? onCharacteristicUnsubscribedCallback;

  @override
  void onStateChanged(BluetoothStateDto state) {
    onStateChangedCallback?.call(state);
  }

  @override
  void onDeviceDiscovered(DeviceDto device) {
    onDeviceDiscoveredCallback?.call(device);
  }

  @override
  void onScanComplete() {
    onScanCompleteCallback?.call();
  }

  @override
  void onConnectionStateChanged(ConnectionStateEventDto event) {
    onConnectionStateChangedCallback?.call(event);
  }

  @override
  void onNotification(NotificationEventDto event) {
    onNotificationCallback?.call(event);
  }

  @override
  void onMtuChanged(MtuChangedEventDto event) {
    onMtuChangedCallback?.call(event);
  }

  // Server (peripheral) callbacks

  @override
  void onCentralConnected(CentralDto central) {
    onCentralConnectedCallback?.call(central);
  }

  @override
  void onCentralDisconnected(String centralId) {
    onCentralDisconnectedCallback?.call(centralId);
  }

  @override
  void onReadRequest(ReadRequestDto request) {
    onReadRequestCallback?.call(request);
  }

  @override
  void onWriteRequest(WriteRequestDto request) {
    onWriteRequestCallback?.call(request);
  }

  @override
  void onCharacteristicSubscribed(String centralId, String characteristicUuid) {
    onCharacteristicSubscribedCallback?.call(centralId, characteristicUuid);
  }

  @override
  void onCharacteristicUnsubscribed(
    String centralId,
    String characteristicUuid,
  ) {
    onCharacteristicUnsubscribedCallback?.call(centralId, characteristicUuid);
  }
}
