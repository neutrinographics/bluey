# bluey_android Clean Code Refactor — Design Spec

## Goal

Split the monolithic `BlueyAndroid` class (777 lines) into focused delegate classes mirroring the Kotlin-side architecture, and add Dart-side unit tests for each delegate.

## Approach

Bottom-up: extract delegates one at a time (scanner, connection manager, server), wiring each into the coordinator. Write tests for each delegate using a mocked `BlueyHostApi`. The Kotlin native code and Pigeon definitions are untouched.

---

## Step 1: Extract `AndroidScanner`

### Problem

Scanning logic (scan, stopScan, device DTO mapping, scan stream) is embedded in `BlueyAndroid` alongside 20+ other concerns.

### Changes

**Create `bluey_android/lib/src/android_scanner.dart`:**

```dart
class AndroidScanner {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();

  AndroidScanner(this._hostApi);

  Stream<PlatformDevice> get scanStream => _scanController.stream;

  Stream<PlatformDevice> scan(PlatformScanConfig config) { ... }
  Future<void> stopScan() async { ... }

  // Callback handlers (called by coordinator)
  void onDeviceDiscovered(DeviceDto device) { ... }
  void onScanComplete() { ... }

  // DTO mapping
  PlatformDevice _mapDevice(DeviceDto dto) { ... }
}
```

**Update `BlueyAndroid`:** Replace inline scanning code with delegation to `AndroidScanner`. Wire `_flutterApi.onDeviceDiscoveredCallback` to `_scanner.onDeviceDiscovered`.

**Create `bluey_android/test/android_scanner_test.dart`:** Test scan stream emission, device mapping, host API calls.

### Impact

`BlueyAndroid` shrinks by ~80 lines. Scanning is independently testable.

---

## Step 2: Extract `AndroidConnectionManager`

### Problem

Connection management, GATT client operations, bonding stubs, PHY stubs, and connection parameter stubs are all in `BlueyAndroid`. This is the largest chunk (~250 lines).

### Changes

**Create `bluey_android/lib/src/android_connection_manager.dart`:**

```dart
class AndroidConnectionManager {
  final BlueyHostApi _hostApi;
  final Map<String, StreamController<PlatformConnectionState>>
      _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
      _notificationControllers = {};

  AndroidConnectionManager(this._hostApi);

  Future<String> connect(String deviceId, PlatformConnectConfig config) async { ... }
  Future<void> disconnect(String deviceId) async { ... }
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) { ... }
  Stream<PlatformNotification> notificationStream(String deviceId) { ... }

  // GATT client operations
  Future<List<PlatformService>> discoverServices(String deviceId) async { ... }
  Future<Uint8List> readCharacteristic(String deviceId, String uuid) async { ... }
  Future<void> writeCharacteristic(String deviceId, String uuid, Uint8List value, bool withResponse) async { ... }
  Future<void> setNotification(String deviceId, String uuid, bool enable) async { ... }
  Future<Uint8List> readDescriptor(String deviceId, String uuid) async { ... }
  Future<void> writeDescriptor(String deviceId, String uuid, Uint8List value) async { ... }
  Future<int> requestMtu(String deviceId, int mtu) async { ... }
  Future<int> readRssi(String deviceId) async { ... }

  // Bonding (stubs)
  Future<PlatformBondState> getBondState(String deviceId) async { ... }
  Stream<PlatformBondState> bondStateStream(String deviceId) { ... }
  Future<void> bond(String deviceId) async { ... }
  Future<void> removeBond(String deviceId) async { ... }
  Future<List<PlatformDevice>> getBondedDevices() async { ... }

  // PHY (stubs)
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async { ... }
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) { ... }
  Future<void> requestPhy(String deviceId, PlatformPhy? txPhy, PlatformPhy? rxPhy) async { ... }

  // Connection Parameters (stubs)
  Future<PlatformConnectionParameters> getConnectionParameters(String deviceId) async { ... }
  Future<void> requestConnectionParameters(String deviceId, PlatformConnectionParameters params) async { ... }

  // Callback handlers
  void onConnectionStateChanged(ConnectionStateEventDto event) { ... }
  void onNotification(NotificationEventDto event) { ... }
  void onMtuChanged(MtuChangedEventDto event) { ... }

  // DTO mapping
  PlatformConnectionState _mapConnectionState(ConnectionStateDto dto) { ... }
  PlatformService _mapService(ServiceDto dto) { ... }
  PlatformCharacteristic _mapCharacteristic(CharacteristicDto dto) { ... }
  PlatformDescriptor _mapDescriptor(DescriptorDto dto) { ... }
}
```

**Update `BlueyAndroid`:** Replace inline connection/GATT code with delegation. Wire connection and notification callbacks.

**Create `bluey_android/test/android_connection_manager_test.dart`:** Test connect/disconnect stream lifecycle, GATT mapping, per-device stream routing, cleanup on disconnect.

### Impact

`BlueyAndroid` shrinks by ~250 lines. Connection management is independently testable. Per-device stream cleanup is verified by tests.

---

## Step 3: Extract `AndroidServer`

### Problem

Server operations (advertising, services, notifications, indications, request handling) and their DTO mapping are in `BlueyAndroid` alongside client code.

### Changes

**Create `bluey_android/lib/src/android_server.dart`:**

```dart
class AndroidServer {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformCentral> _centralConnectionsController =
      StreamController<PlatformCentral>.broadcast();
  final StreamController<String> _centralDisconnectionsController =
      StreamController<String>.broadcast();
  final StreamController<PlatformReadRequest> _readRequestsController =
      StreamController<PlatformReadRequest>.broadcast();
  final StreamController<PlatformWriteRequest> _writeRequestsController =
      StreamController<PlatformWriteRequest>.broadcast();

  AndroidServer(this._hostApi);

  Stream<PlatformCentral> get centralConnections => _centralConnectionsController.stream;
  Stream<String> get centralDisconnections => _centralDisconnectionsController.stream;
  Stream<PlatformReadRequest> get readRequests => _readRequestsController.stream;
  Stream<PlatformWriteRequest> get writeRequests => _writeRequestsController.stream;

  Future<void> addService(PlatformLocalService service) async { ... }
  Future<void> removeService(String serviceUuid) async { ... }
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async { ... }
  Future<void> stopAdvertising() async { ... }
  Future<void> notifyCharacteristic(String uuid, Uint8List value) async { ... }
  Future<void> notifyCharacteristicTo(String centralId, String uuid, Uint8List value) async { ... }
  Future<void> indicateCharacteristic(String uuid, Uint8List value) async { ... }
  Future<void> indicateCharacteristicTo(String centralId, String uuid, Uint8List value) async { ... }
  Future<void> respondToReadRequest(int requestId, PlatformGattStatus status, Uint8List? value) async { ... }
  Future<void> respondToWriteRequest(int requestId, PlatformGattStatus status) async { ... }
  Future<void> disconnectCentral(String centralId) async { ... }
  Future<void> closeServer() async { ... }

  // Callback handlers
  void onCentralConnected(CentralDto central) { ... }
  void onCentralDisconnected(String centralId) { ... }
  void onReadRequest(ReadRequestDto request) { ... }
  void onWriteRequest(WriteRequestDto request) { ... }

  // DTO mapping
  LocalServiceDto _mapLocalServiceToDto(PlatformLocalService service) { ... }
  LocalCharacteristicDto _mapLocalCharacteristicToDto(PlatformLocalCharacteristic char) { ... }
  LocalDescriptorDto _mapLocalDescriptorToDto(PlatformLocalDescriptor desc) { ... }
  GattPermissionDto _mapGattPermissionToDto(PlatformGattPermission permission) { ... }
  GattStatusDto _mapGattStatusToDto(PlatformGattStatus status) { ... }
  AdvertiseModeDto? _mapAdvertiseModeToDto(PlatformAdvertiseMode? mode) { ... }
}
```

**Update `BlueyAndroid`:** Replace inline server code with delegation. Wire server callbacks.

**Create `bluey_android/test/android_server_test.dart`:** Test service DTO mapping, advertising config mapping, stream emission for requests.

### Impact

`BlueyAndroid` shrinks by ~200 lines. Server operations are independently testable.

---

## Step 4: Update Coordinator and Add `mocktail`

### Changes

- Add `mocktail: ^1.0.4` to `bluey_android/pubspec.yaml` under `dev_dependencies`
- Update `bluey_android/test/bluey_android_test.dart` to verify the coordinator creates delegates and routes correctly
- The `_BlueyFlutterApiImpl` class stays in `bluey_android.dart` — it implements the Pigeon callback interface and routes each event to the appropriate delegate's handler method

### Final `BlueyAndroid` structure (~150 lines)

```dart
class BlueyAndroid extends BlueyPlatform {
  final BlueyHostApi _hostApi;
  final _BlueyFlutterApiImpl _flutterApi;
  late final AndroidScanner _scanner;
  late final AndroidConnectionManager _connectionManager;
  late final AndroidServer _server;
  bool _isInitialized = false;

  BlueyAndroid() : _hostApi = BlueyHostApi(),
                   _flutterApi = _BlueyFlutterApiImpl(),
                   super.impl() {
    _scanner = AndroidScanner(_hostApi);
    _connectionManager = AndroidConnectionManager(_hostApi);
    _server = AndroidServer(_hostApi);
  }

  void _ensureInitialized() {
    if (_isInitialized) return;
    _isInitialized = true;
    BlueyFlutterApi.setUp(_flutterApi);
    // Wire callbacks to delegates
    _flutterApi.onDeviceDiscoveredCallback = _scanner.onDeviceDiscovered;
    _flutterApi.onScanCompleteCallback = _scanner.onScanComplete;
    _flutterApi.onConnectionStateChangedCallback = _connectionManager.onConnectionStateChanged;
    _flutterApi.onNotificationCallback = _connectionManager.onNotification;
    _flutterApi.onMtuChangedCallback = _connectionManager.onMtuChanged;
    _flutterApi.onCentralConnectedCallback = _server.onCentralConnected;
    _flutterApi.onCentralDisconnectedCallback = _server.onCentralDisconnected;
    _flutterApi.onReadRequestCallback = _server.onReadRequest;
    _flutterApi.onWriteRequestCallback = _server.onWriteRequest;
    // ...
  }

  // Platform-level methods (state, config)
  @override Capabilities get capabilities => Capabilities.android;
  @override Future<void> configure(BlueyConfig config) async { ... }
  @override Stream<BluetoothState> get stateStream { ... }
  @override Future<BluetoothState> getState() async { ... }
  @override Future<bool> requestEnable() async { ... }
  @override Future<bool> authorize() async { ... }
  @override Future<void> openSettings() async { ... }

  // Delegate to scanner
  @override Stream<PlatformDevice> scan(PlatformScanConfig config) => ...
  @override Future<void> stopScan() => ...

  // Delegate to connection manager
  @override Future<String> connect(...) => ...
  // ... etc

  // Delegate to server
  @override Future<void> addService(...) => ...
  // ... etc
}
```

---

## Testing Strategy

All tests use `mocktail` to mock `BlueyHostApi`.

- **`android_scanner_test.dart`**: ~8 tests — scan stream, device mapping, host API calls, stopScan
- **`android_connection_manager_test.dart`**: ~12 tests — connect/disconnect lifecycle, per-device streams, GATT mapping, cleanup, notification routing
- **`android_server_test.dart`**: ~10 tests — service DTO mapping, advertising config, stream emission, request/response host API calls
- **`bluey_android_test.dart`**: Update existing registration test, add coordinator delegation verification

Total: ~30 new tests.

---

## Out of Scope

- Kotlin native code changes
- Pigeon definition changes
- iOS package changes
- New BLE features (bonding, PHY, connection parameters remain as stubs)
- Resource pruning of stale per-device streams (noted as future improvement)
