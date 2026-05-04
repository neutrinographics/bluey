import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'ios_connection_manager.dart';
import 'ios_scanner.dart';
import 'ios_server.dart';
import 'messages.g.dart';

/// iOS implementation of [BlueyPlatform].
final class BlueyIos extends BlueyPlatform {
  /// Registers this class as the default instance of [BlueyPlatform].
  static void registerWith() {
    BlueyPlatform.instance = BlueyIos();
  }

  final BlueyHostApi _hostApi = BlueyHostApi();
  final _BlueyFlutterApiImpl _flutterApi = _BlueyFlutterApiImpl();
  late final IosScanner _scanner = IosScanner(_hostApi);
  late final IosConnectionManager _connectionManager = IosConnectionManager(
    _hostApi,
  );
  late final IosServer _server = IosServer(_hostApi);

  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();
  final StreamController<String> _serviceChangesController =
      StreamController<String>.broadcast();

  final StreamController<PlatformLogEvent> _logEventsController =
      StreamController<PlatformLogEvent>.broadcast();

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
    _flutterApi.onCentralConnectedCallback = _server.onCentralConnected;
    _flutterApi.onCentralDisconnectedCallback = _server.onCentralDisconnected;
    _flutterApi.onReadRequestCallback = _server.onReadRequest;
    _flutterApi.onWriteRequestCallback = _server.onWriteRequest;

    _flutterApi.onServicesChangedCallback = (deviceId) {
      _serviceChangesController.add(deviceId);
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

    _flutterApi.onLogCallback = (event) {
      _logEventsController.add(_mapLogEventDto(event));
    };
  }

  @override
  Capabilities get capabilities => Capabilities.iOS;

  @override
  Future<void> configure(BlueyConfig config) async {
    _ensureInitialized();
    final dto = BlueyConfigDto(
      cleanupOnActivityDestroy: config.cleanupOnActivityDestroy,
      discoverServicesTimeoutMs: config.discoverServicesTimeoutMs,
      readCharacteristicTimeoutMs: config.readCharacteristicTimeoutMs,
      writeCharacteristicTimeoutMs: config.writeCharacteristicTimeoutMs,
      readDescriptorTimeoutMs: config.readDescriptorTimeoutMs,
      writeDescriptorTimeoutMs: config.writeDescriptorTimeoutMs,
      readRssiTimeoutMs: config.readRssiTimeoutMs,
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
    int characteristicHandle,
  ) async {
    _ensureInitialized();
    return await _connectionManager.readCharacteristic(
      deviceId,
      characteristicHandle,
    );
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  ) async {
    _ensureInitialized();
    await _connectionManager.writeCharacteristic(
      deviceId,
      characteristicHandle,
      value,
      withResponse,
    );
  }

  @override
  Future<void> setNotification(
    String deviceId,
    int characteristicHandle,
    bool enable,
  ) async {
    _ensureInitialized();
    await _connectionManager.setNotification(
      deviceId,
      characteristicHandle,
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
    int characteristicHandle,
    int descriptorHandle,
  ) async {
    _ensureInitialized();
    return await _connectionManager.readDescriptor(
      deviceId,
      characteristicHandle,
      descriptorHandle,
    );
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _connectionManager.writeDescriptor(
      deviceId,
      characteristicHandle,
      descriptorHandle,
      value,
    );
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
  Future<PlatformLocalService> addService(PlatformLocalService service) async {
    _ensureInitialized();
    return await _server.addService(service);
  }

  @override
  Future<void> removeService(String serviceUuid) async {
    _ensureInitialized();
    await _server.removeService(serviceUuid);
  }

  @override
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
    _ensureInitialized();
    await _server.startAdvertising(config);
  }

  @override
  Future<void> stopAdvertising() async {
    _ensureInitialized();
    await _server.stopAdvertising();
  }

  @override
  Future<void> notifyCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _server.notifyCharacteristic(characteristicHandle, value);
  }

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _server.notifyCharacteristicTo(
      centralId,
      characteristicHandle,
      value,
    );
  }

  @override
  Future<void> indicateCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _server.indicateCharacteristic(characteristicHandle, value);
  }

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    _ensureInitialized();
    await _server.indicateCharacteristicTo(
      centralId,
      characteristicHandle,
      value,
    );
  }

  @override
  Stream<String> get serviceChanges {
    _ensureInitialized();
    return _serviceChangesController.stream;
  }

  @override
  Stream<PlatformCentral> get centralConnections {
    _ensureInitialized();
    return _server.centralConnections;
  }

  @override
  Stream<String> get centralDisconnections {
    _ensureInitialized();
    return _server.centralDisconnections;
  }

  @override
  Stream<PlatformReadRequest> get readRequests {
    _ensureInitialized();
    return _server.readRequests;
  }

  @override
  Stream<PlatformWriteRequest> get writeRequests {
    _ensureInitialized();
    return _server.writeRequests;
  }

  @override
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    _ensureInitialized();
    await _server.respondToReadRequest(requestId, status, value);
  }

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    PlatformGattStatus status,
  ) async {
    _ensureInitialized();
    await _server.respondToWriteRequest(requestId, status);
  }

  @override
  Future<void> closeServer() async {
    _ensureInitialized();
    await _server.closeServer();
  }

  // === Structured logging (I307) ===

  @override
  Stream<PlatformLogEvent> get logEvents {
    _ensureInitialized();
    return _logEventsController.stream;
  }

  @override
  Future<void> setLogLevel(PlatformLogLevel level) async {
    _ensureInitialized();
    await _hostApi.setLogLevel(_mapLogLevelToDto(level));
  }

  PlatformLogEvent _mapLogEventDto(LogEventDto dto) {
    return PlatformLogEvent(
      timestamp:
          DateTime.fromMicrosecondsSinceEpoch(
            dto.timestampMicros,
            isUtc: true,
          ).toLocal(),
      level: _mapLogLevelFromDto(dto.level),
      context: dto.context,
      message: dto.message,
      data: _mapLogData(dto.data),
      errorCode: dto.errorCode,
    );
  }

  Map<String, Object?> _mapLogData(Map<String?, Object?> data) {
    final result = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key;
      if (key == null) continue;
      result[key] = entry.value;
    }
    return result;
  }

  PlatformLogLevel _mapLogLevelFromDto(LogLevelDto dto) {
    switch (dto) {
      case LogLevelDto.trace:
        return PlatformLogLevel.trace;
      case LogLevelDto.debug:
        return PlatformLogLevel.debug;
      case LogLevelDto.info:
        return PlatformLogLevel.info;
      case LogLevelDto.warn:
        return PlatformLogLevel.warn;
      case LogLevelDto.error:
        return PlatformLogLevel.error;
    }
  }

  LogLevelDto _mapLogLevelToDto(PlatformLogLevel level) {
    switch (level) {
      case PlatformLogLevel.trace:
        return LogLevelDto.trace;
      case PlatformLogLevel.debug:
        return LogLevelDto.debug;
      case PlatformLogLevel.info:
        return LogLevelDto.info;
      case PlatformLogLevel.warn:
        return LogLevelDto.warn;
      case PlatformLogLevel.error:
        return LogLevelDto.error;
    }
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
  void Function(String)? onServicesChangedCallback;
  void Function(LogEventDto)? onLogCallback;

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

  @override
  void onServicesChanged(String deviceId) {
    onServicesChangedCallback?.call(deviceId);
  }

  @override
  void onLog(LogEventDto event) {
    onLogCallback?.call(event);
  }
}
