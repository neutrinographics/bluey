import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'messages.g.dart';

/// Bluetooth SIG base UUID suffix for short UUID expansion.
const _bluetoothBaseUuidSuffix = '-0000-1000-8000-00805f9b34fb';

/// Expands a short UUID (4 or 8 hex chars) to full 128-bit UUID string.
///
/// CoreBluetooth may return UUIDs in short form. This function normalizes
/// them to the full 128-bit format expected by the domain layer.
///
/// Examples:
/// - "180F" -> "0000180f-0000-1000-8000-00805f9b34fb"
/// - "12345678" -> "12345678-0000-1000-8000-00805f9b34fb"
/// - Full UUID -> returned as-is (lowercased with hyphens)
String _expandUuid(String uuid) {
  // Remove any existing hyphens and lowercase
  final clean = uuid.replaceAll('-', '').toLowerCase();

  // 16-bit short UUID (4 hex chars)
  if (clean.length == 4) {
    return '0000$clean$_bluetoothBaseUuidSuffix';
  }

  // 32-bit short UUID (8 hex chars)
  if (clean.length == 8) {
    return '$clean$_bluetoothBaseUuidSuffix';
  }

  // Full 128-bit UUID (32 hex chars) - add hyphens in standard format
  if (clean.length == 32) {
    return '${clean.substring(0, 8)}-'
        '${clean.substring(8, 12)}-'
        '${clean.substring(12, 16)}-'
        '${clean.substring(16, 20)}-'
        '${clean.substring(20, 32)}';
  }

  // Unknown format - return as-is and let the domain layer handle validation
  return uuid.toLowerCase();
}

/// iOS implementation of [BlueyPlatform].
final class BlueyIos extends BlueyPlatform {
  /// Registers this class as the default instance of [BlueyPlatform].
  static void registerWith() {
    BlueyPlatform.instance = BlueyIos();
  }

  final BlueyHostApi _hostApi = BlueyHostApi();
  final _BlueyFlutterApiImpl _flutterApi = _BlueyFlutterApiImpl();

  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();
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

    _flutterApi.onDeviceDiscoveredCallback = (device) {
      _scanController.add(_mapDevice(device));
    };

    _flutterApi.onScanCompleteCallback = () {
      // Scan completed
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
            characteristicUuid: _expandUuid(event.characteristicUuid),
            value: event.value,
          ),
        );
      }
    };

    _flutterApi.onMtuChangedCallback = (event) {
      // MTU change callback
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
          characteristicUuid: _expandUuid(request.characteristicUuid),
          offset: request.offset,
        ),
      );
    };

    _flutterApi.onWriteRequestCallback = (request) {
      _writeRequestsController.add(
        PlatformWriteRequest(
          requestId: request.requestId,
          centralId: request.centralId,
          characteristicUuid: _expandUuid(request.characteristicUuid),
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
      // Note: characteristicUuid would need _expandUuid if exposed
    };

    _flutterApi.onCharacteristicUnsubscribedCallback = (
      centralId,
      characteristicUuid,
    ) {
      // Could expose this as a stream if needed
      // Note: characteristicUuid would need _expandUuid if exposed
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
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );

    _hostApi.startScan(dto);

    return _scanController.stream;
  }

  @override
  Future<void> stopScan() async {
    _ensureInitialized();
    await _hostApi.stopScan();
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

    // Clean up controllers
    final stateController = _connectionStateControllers.remove(deviceId);
    await stateController?.close();

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
    // iOS automatically negotiates MTU, cannot request specific MTU
    throw UnsupportedError(
      'iOS does not support requesting a specific MTU. '
      'MTU is automatically negotiated by the system.',
    );
  }

  @override
  Future<int> readRssi(String deviceId) async {
    _ensureInitialized();
    return await _hostApi.readRssi(deviceId);
  }

  // === Bonding (iOS handles automatically) ===

  @override
  Future<PlatformBondState> getBondState(String deviceId) async {
    // iOS doesn't expose bond state
    return PlatformBondState.none;
  }

  @override
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    // iOS doesn't expose bond state changes
    return const Stream.empty();
  }

  @override
  Future<void> bond(String deviceId) async {
    // iOS handles bonding automatically when accessing encrypted characteristics
    // No-op on iOS
  }

  @override
  Future<void> removeBond(String deviceId) async {
    // iOS doesn't allow programmatic bond removal
    throw UnsupportedError(
      'iOS does not support removing bonds programmatically. '
      'Users must remove the device from Settings > Bluetooth.',
    );
  }

  @override
  Future<List<PlatformDevice>> getBondedDevices() async {
    // iOS doesn't provide a list of bonded devices
    return [];
  }

  // === PHY (limited iOS support) ===

  @override
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    // iOS doesn't expose PHY information
    throw UnsupportedError('iOS does not support reading PHY information.');
  }

  @override
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    // iOS doesn't expose PHY changes
    return const Stream.empty();
  }

  @override
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    // iOS doesn't support requesting PHY
    throw UnsupportedError('iOS does not support requesting PHY settings.');
  }

  // === Connection Parameters (not available on iOS) ===

  @override
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    throw UnsupportedError(
      'iOS does not support reading connection parameters.',
    );
  }

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    throw UnsupportedError(
      'iOS does not support requesting connection parameters.',
    );
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

  PlatformDevice _mapDevice(DeviceDto dto) {
    return PlatformDevice(
      id: dto.id,
      name: dto.name,
      rssi: dto.rssi,
      // Expand short UUIDs from CoreBluetooth to full 128-bit format
      serviceUuids: dto.serviceUuids.map(_expandUuid).toList(),
      manufacturerDataCompanyId: dto.manufacturerDataCompanyId,
      manufacturerData: dto.manufacturerData,
    );
  }

  PlatformService _mapService(ServiceDto dto) {
    return PlatformService(
      uuid: _expandUuid(dto.uuid),
      isPrimary: dto.isPrimary,
      characteristics: dto.characteristics.map(_mapCharacteristic).toList(),
      includedServices: dto.includedServices.map(_mapService).toList(),
    );
  }

  PlatformCharacteristic _mapCharacteristic(CharacteristicDto dto) {
    return PlatformCharacteristic(
      uuid: _expandUuid(dto.uuid),
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
    return PlatformDescriptor(uuid: _expandUuid(dto.uuid));
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
