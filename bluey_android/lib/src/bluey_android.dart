import 'dart:async';
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

    return await _hostApi.connect(deviceId, dto);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _hostApi.disconnect(deviceId);

    // Clean up connection state controller
    final controller = _connectionStateControllers.remove(deviceId);
    await controller?.close();
  }

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    final controller = _connectionStateControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
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
}

/// Implementation of Flutter API that receives callbacks from platform.
class _BlueyFlutterApiImpl implements BlueyFlutterApi {
  void Function(BluetoothStateDto)? onStateChangedCallback;
  void Function(DeviceDto)? onDeviceDiscoveredCallback;
  void Function()? onScanCompleteCallback;
  void Function(ConnectionStateEventDto)? onConnectionStateChangedCallback;

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
}
