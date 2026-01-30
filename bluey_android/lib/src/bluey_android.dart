import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'messages.g.dart';

/// Android implementation of [BlueyPlatform].
class BlueyAndroid extends BlueyPlatform {
  /// Registers this class as the default instance of [BlueyPlatform].
  static void registerWith() {
    BlueyPlatform.instance = BlueyAndroid();
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

  BlueyAndroid() {
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
      // Scan completed - close and recreate the controller for next scan
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
        controller.add(PlatformNotification(
          deviceId: event.deviceId,
          characteristicUuid: event.characteristicUuid,
          value: event.value,
        ));
      }
    };

    _flutterApi.onMtuChangedCallback = (event) {
      // MTU change is also reflected through the callback
      // Currently we don't expose this as a separate stream
    };
  }

  @override
  Capabilities get capabilities => Capabilities.android;

  @override
  Stream<BluetoothState> get stateStream => _stateController.stream;

  @override
  Future<BluetoothState> getState() async {
    final state = await _hostApi.getState();
    return _mapBluetoothState(state);
  }

  @override
  Future<bool> requestEnable() async {
    return await _hostApi.requestEnable();
  }

  @override
  Future<void> openSettings() async {
    await _hostApi.openSettings();
  }

  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );

    // Start scan (async, doesn't block)
    _hostApi.startScan(dto);

    return _scanController.stream;
  }

  @override
  Future<void> stopScan() async {
    await _hostApi.stopScan();
  }

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    final dto = ConnectConfigDto(
      timeoutMs: config.timeoutMs,
      mtu: config.mtu,
    );

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
    final controller = _connectionStateControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  // === GATT Operations ===

  @override
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    final services = await _hostApi.discoverServices(deviceId);
    return services.map(_mapService).toList();
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    return await _hostApi.readCharacteristic(deviceId, characteristicUuid);
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
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
    await _hostApi.setNotification(deviceId, characteristicUuid, enable);
  }

  @override
  Stream<PlatformNotification> notificationStream(String deviceId) {
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
    return await _hostApi.readDescriptor(deviceId, descriptorUuid);
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {
    await _hostApi.writeDescriptor(deviceId, descriptorUuid, value);
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    return await _hostApi.requestMtu(deviceId, mtu);
  }

  @override
  Future<int> readRssi(String deviceId) async {
    return await _hostApi.readRssi(deviceId);
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

  PlatformDevice _mapDevice(DeviceDto dto) {
    return PlatformDevice(
      id: dto.id,
      name: dto.name,
      rssi: dto.rssi,
      serviceUuids: dto.serviceUuids,
      manufacturerDataCompanyId: dto.manufacturerDataCompanyId,
      manufacturerData: dto.manufacturerData,
    );
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
}

/// Implementation of Flutter API that receives callbacks from platform.
class _BlueyFlutterApiImpl implements BlueyFlutterApi {
  void Function(BluetoothStateDto)? onStateChangedCallback;
  void Function(DeviceDto)? onDeviceDiscoveredCallback;
  void Function()? onScanCompleteCallback;
  void Function(ConnectionStateEventDto)? onConnectionStateChangedCallback;
  void Function(NotificationEventDto)? onNotificationCallback;
  void Function(MtuChangedEventDto)? onMtuChangedCallback;

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
}
