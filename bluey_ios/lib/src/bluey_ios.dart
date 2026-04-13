import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'ios_connection_manager.dart';
import 'ios_scanner.dart';
import 'messages.g.dart';
import 'uuid_utils.dart';

/// iOS implementation of [BlueyPlatform].
final class BlueyIos extends BlueyPlatform {
  /// Registers this class as the default instance of [BlueyPlatform].
  static void registerWith() {
    BlueyPlatform.instance = BlueyIos();
  }

  final BlueyHostApi _hostApi = BlueyHostApi();
  final _BlueyFlutterApiImpl _flutterApi = _BlueyFlutterApiImpl();
  late final IosScanner _scanner = IosScanner(_hostApi);
  late final IosConnectionManager _connectionManager =
      IosConnectionManager(_hostApi);

  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();

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

  BlueyIos() : super.impl();

  /// Lazily initializes the Flutter API setup.
  void _ensureInitialized() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Set up the Flutter API to receive callbacks from platform
    BlueyFlutterApi.setUp(_flutterApi);

    // Wire up callbacks to our streams
    _flutterApi.onStateChangedCallback = (state) {
      _stateController.add(_mapBluetoothState(state));
    };

    _flutterApi.onDeviceDiscoveredCallback = _scanner.onDeviceDiscovered;

    _flutterApi.onScanCompleteCallback = _scanner.onScanComplete;

    _flutterApi.onConnectionStateChangedCallback =
        _connectionManager.onConnectionStateChanged;

    _flutterApi.onNotificationCallback = _connectionManager.onNotification;

    _flutterApi.onMtuChangedCallback = _connectionManager.onMtuChanged;

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
          characteristicUuid: expandUuid(request.characteristicUuid),
          offset: request.offset,
        ),
      );
    };

    _flutterApi.onWriteRequestCallback = (request) {
      _writeRequestsController.add(
        PlatformWriteRequest(
          requestId: request.requestId,
          centralId: request.centralId,
          characteristicUuid: expandUuid(request.characteristicUuid),
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
      // Note: characteristicUuid would need expandUuid if exposed
    };

    _flutterApi.onCharacteristicUnsubscribedCallback = (
      centralId,
      characteristicUuid,
    ) {
      // Could expose this as a stream if needed
      // Note: characteristicUuid would need expandUuid if exposed
    };
  }

  @override
  Capabilities get capabilities => Capabilities.iOS;

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
    // iOS cannot enable Bluetooth programmatically
    throw UnsupportedError(
      'iOS does not support enabling Bluetooth programmatically. '
      'Use openSettings() to direct the user to Settings.',
    );
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
    return await _connectionManager.connect(deviceId, config);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _ensureInitialized();
    await _connectionManager.disconnect(deviceId);
  }

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    _ensureInitialized();
    return _connectionManager.connectionStateStream(deviceId);
  }

  // === GATT Operations ===

  @override
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    _ensureInitialized();
    return await _connectionManager.discoverServices(deviceId);
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    _ensureInitialized();
    return await _connectionManager.readCharacteristic(
      deviceId,
      characteristicUuid,
    );
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    _ensureInitialized();
    await _connectionManager.writeCharacteristic(
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
    await _connectionManager.setNotification(
      deviceId,
      characteristicUuid,
      enable,
    );
  }

  @override
  Stream<PlatformNotification> notificationStream(String deviceId) {
    _ensureInitialized();
    return _connectionManager.notificationStream(deviceId);
  }

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    _ensureInitialized();
    return await _connectionManager.readDescriptor(deviceId, descriptorUuid);
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _connectionManager.writeDescriptor(deviceId, descriptorUuid, value);
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    return await _connectionManager.requestMtu(deviceId, mtu);
  }

  @override
  Future<int> readRssi(String deviceId) async {
    _ensureInitialized();
    return await _connectionManager.readRssi(deviceId);
  }

  // === Bonding (iOS handles automatically) ===

  @override
  Future<PlatformBondState> getBondState(String deviceId) async {
    return await _connectionManager.getBondState(deviceId);
  }

  @override
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    return _connectionManager.bondStateStream(deviceId);
  }

  @override
  Future<void> bond(String deviceId) async {
    await _connectionManager.bond(deviceId);
  }

  @override
  Future<void> removeBond(String deviceId) async {
    await _connectionManager.removeBond(deviceId);
  }

  @override
  Future<List<PlatformDevice>> getBondedDevices() async {
    return await _connectionManager.getBondedDevices();
  }

  // === PHY (limited iOS support) ===

  @override
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    return await _connectionManager.getPhy(deviceId);
  }

  @override
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    return _connectionManager.phyStream(deviceId);
  }

  @override
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    await _connectionManager.requestPhy(deviceId, txPhy, rxPhy);
  }

  // === Connection Parameters (not available on iOS) ===

  @override
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    return await _connectionManager.getConnectionParameters(deviceId);
  }

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    await _connectionManager.requestConnectionParameters(deviceId, params);
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
    );
    await _hostApi.startAdvertising(dto);
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
    // iOS uses the same updateValue method for both notifications and indications
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

  // === Mapping functions ===

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
