# bluey_android Clean Code Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `BlueyAndroid` class (777 lines) into focused delegate classes and add Dart-side unit tests.

**Architecture:** Extract scanning, connection management, and server operations into separate delegate classes that receive the Pigeon `BlueyHostApi`. The coordinator `BlueyAndroid` wires callbacks to delegates and implements `BlueyPlatform` by delegation. Tests mock `BlueyHostApi` with `mocktail`.

**Tech Stack:** Dart, Flutter, Pigeon (generated), mocktail (testing)

**Spec:** `docs/superpowers/specs/2026-04-13-bluey-android-clean-code-design.md`

---

## Task 1: Add `mocktail` and Create Mock

**Files:**
- Modify: `bluey_android/pubspec.yaml`
- Create: `bluey_android/test/mocks.dart`

- [ ] **Step 1: Add `mocktail` dependency**

In `bluey_android/pubspec.yaml`, add `mocktail` under `dev_dependencies`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^1.0.4
  pigeon: ^26.0.4
```

Run: `cd bluey_android && flutter pub get`
Expected: Resolves successfully.

- [ ] **Step 2: Create shared mock file**

Create `bluey_android/test/mocks.dart`:

```dart
import 'package:mocktail/mocktail.dart';
import 'package:bluey_android/src/messages.g.dart';

class MockBlueyHostApi extends Mock implements BlueyHostApi {}
```

- [ ] **Step 3: Commit**

```bash
cd bluey_android && git add pubspec.yaml test/mocks.dart
git commit -m "chore: add mocktail and shared mock for BlueyHostApi

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Extract `AndroidScanner`

**Files:**
- Create: `bluey_android/test/android_scanner_test.dart`
- Create: `bluey_android/lib/src/android_scanner.dart`
- Modify: `bluey_android/lib/src/bluey_android.dart`

- [ ] **Step 1: Write failing tests for `AndroidScanner`**

Create `bluey_android/test/android_scanner_test.dart`:

```dart
import 'dart:async';

import 'package:bluey_android/src/android_scanner.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  late MockBlueyHostApi mockHostApi;
  late AndroidScanner scanner;

  setUpAll(() {
    registerFallbackValue(ScanConfigDto(serviceUuids: [], timeoutMs: null));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    scanner = AndroidScanner(mockHostApi);
  });

  group('AndroidScanner', () {
    test('scan calls hostApi.startScan with correct config', () async {
      when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

      final config = PlatformScanConfig(
        serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
        timeoutMs: 10000,
      );
      scanner.scan(config);

      final captured = verify(() => mockHostApi.startScan(captureAny()))
          .captured
          .single as ScanConfigDto;
      expect(captured.serviceUuids, ['0000180d-0000-1000-8000-00805f9b34fb']);
      expect(captured.timeoutMs, 10000);
    });

    test('scan returns scan stream', () {
      when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

      final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);
      final stream = scanner.scan(config);

      expect(stream, isA<Stream<PlatformDevice>>());
    });

    test('onDeviceDiscovered emits device to scan stream', () async {
      when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

      final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);
      final devices = <PlatformDevice>[];
      final sub = scanner.scan(config).listen(devices.add);

      scanner.onDeviceDiscovered(DeviceDto(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Test Device',
        rssi: -65,
        serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
        manufacturerDataCompanyId: null,
        manufacturerData: null,
      ));

      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(devices, hasLength(1));
      expect(devices.first.id, 'AA:BB:CC:DD:EE:01');
      expect(devices.first.name, 'Test Device');
      expect(devices.first.rssi, -65);
      expect(devices.first.serviceUuids, ['0000180d-0000-1000-8000-00805f9b34fb']);
    });

    test('onDeviceDiscovered maps manufacturer data', () async {
      when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

      final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);
      final devices = <PlatformDevice>[];
      final sub = scanner.scan(config).listen(devices.add);

      scanner.onDeviceDiscovered(DeviceDto(
        id: 'AA:BB:CC:DD:EE:01',
        name: null,
        rssi: -80,
        serviceUuids: [],
        manufacturerDataCompanyId: 0x004C,
        manufacturerData: [10, 20, 30],
      ));

      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(devices.first.manufacturerDataCompanyId, 0x004C);
      expect(devices.first.manufacturerData, [10, 20, 30]);
    });

    test('stopScan calls hostApi.stopScan', () async {
      when(() => mockHostApi.stopScan()).thenAnswer((_) async {});

      await scanner.stopScan();

      verify(() => mockHostApi.stopScan()).called(1);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd bluey_android && flutter test test/android_scanner_test.dart`
Expected: FAIL — `AndroidScanner` not found.

- [ ] **Step 3: Implement `AndroidScanner`**

Create `bluey_android/lib/src/android_scanner.dart`:

```dart
import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'messages.g.dart';

/// Handles BLE scanning operations for the Android platform.
///
/// Delegates to [BlueyHostApi] for platform calls and manages the
/// scan result stream.
class AndroidScanner {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();

  AndroidScanner(this._hostApi);

  /// Returns the scan stream. Calls hostApi.startScan to begin scanning.
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );
    _hostApi.startScan(dto);
    return _scanController.stream;
  }

  /// Stop scanning.
  Future<void> stopScan() async {
    await _hostApi.stopScan();
  }

  /// Called by the coordinator when platform reports a discovered device.
  void onDeviceDiscovered(DeviceDto device) {
    _scanController.add(_mapDevice(device));
  }

  /// Called by the coordinator when platform reports scan complete.
  void onScanComplete() {
    // Scan completed — no action needed for now.
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_android && flutter test test/android_scanner_test.dart`
Expected: All 5 tests PASS.

- [ ] **Step 5: Update `BlueyAndroid` to delegate scanning to `AndroidScanner`**

In `bluey_android/lib/src/bluey_android.dart`:

Add import:
```dart
import 'android_scanner.dart';
```

Add field and initialization in the constructor area:
```dart
late final AndroidScanner _scanner;
```

In the constructor body (or lazy init), create the scanner:
```dart
BlueyAndroid() : super.impl() {
  _hostApi = BlueyHostApi();
  _flutterApi = _BlueyFlutterApiImpl();
  _scanner = AndroidScanner(_hostApi);
}
```

Note: `_hostApi` and `_flutterApi` need to become non-final fields assigned in the constructor body, or keep as final with an initializer list. The simplest approach is to keep the current pattern and add `_scanner = AndroidScanner(_hostApi)` after the fields are initialized. Since the current code uses `final _hostApi = BlueyHostApi()` as field initializers, you can add `late final AndroidScanner _scanner = AndroidScanner(_hostApi);` as a late field.

In `_ensureInitialized()`, replace the scan callback wiring:
```dart
_flutterApi.onDeviceDiscoveredCallback = (device) {
  _scanner.onDeviceDiscovered(device);
};

_flutterApi.onScanCompleteCallback = () {
  _scanner.onScanComplete();
};
```

Replace the `scan()` method:
```dart
@override
Stream<PlatformDevice> scan(PlatformScanConfig config) {
  _ensureInitialized();
  return _scanner.scan(config);
}
```

Replace the `stopScan()` method:
```dart
@override
Future<void> stopScan() async {
  _ensureInitialized();
  await _scanner.stopScan();
}
```

Remove the `_scanController` field from `BlueyAndroid` (it's now in `AndroidScanner`).

Remove the `_mapDevice()` method from `BlueyAndroid` (it's now in `AndroidScanner`).

- [ ] **Step 6: Run all tests**

Run: `cd bluey_android && flutter test`
Expected: All tests pass (existing + 5 new scanner tests).

- [ ] **Step 7: Commit**

```bash
cd bluey_android && git add lib/src/android_scanner.dart lib/src/bluey_android.dart test/android_scanner_test.dart
git commit -m "refactor: extract AndroidScanner from BlueyAndroid

Move scanning logic into dedicated AndroidScanner class with its own
stream controller and device DTO mapping. Add 5 unit tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Extract `AndroidConnectionManager`

**Files:**
- Create: `bluey_android/test/android_connection_manager_test.dart`
- Create: `bluey_android/lib/src/android_connection_manager.dart`
- Modify: `bluey_android/lib/src/bluey_android.dart`

- [ ] **Step 1: Write failing tests for `AndroidConnectionManager`**

Create `bluey_android/test/android_connection_manager_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_android/src/android_connection_manager.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  late MockBlueyHostApi mockHostApi;
  late AndroidConnectionManager connectionManager;

  setUpAll(() {
    registerFallbackValue(ConnectConfigDto(timeoutMs: null, mtu: null));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    connectionManager = AndroidConnectionManager(mockHostApi);
  });

  group('AndroidConnectionManager', () {
    group('connect', () {
      test('calls hostApi.connect and returns connection ID', () async {
        when(() => mockHostApi.connect('device1', any()))
            .thenAnswer((_) async => 'device1');

        final result = await connectionManager.connect(
          'device1',
          PlatformConnectConfig(timeoutMs: 5000, mtu: null),
        );

        expect(result, 'device1');
        verify(() => mockHostApi.connect('device1', any())).called(1);
      });

      test('creates per-device stream controllers', () async {
        when(() => mockHostApi.connect('device1', any()))
            .thenAnswer((_) async => 'device1');

        await connectionManager.connect(
          'device1',
          PlatformConnectConfig(timeoutMs: null, mtu: null),
        );

        // Should not throw — stream should exist
        final stream = connectionManager.connectionStateStream('device1');
        expect(stream, isA<Stream<PlatformConnectionState>>());
      });
    });

    group('disconnect', () {
      test('calls hostApi.disconnect and cleans up streams', () async {
        when(() => mockHostApi.connect('device1', any()))
            .thenAnswer((_) async => 'device1');
        when(() => mockHostApi.disconnect('device1'))
            .thenAnswer((_) async {});

        await connectionManager.connect(
          'device1',
          PlatformConnectConfig(timeoutMs: null, mtu: null),
        );
        await connectionManager.disconnect('device1');

        // After disconnect, connectionStateStream should return error stream
        final stream = connectionManager.connectionStateStream('device1');
        expect(stream, emitsError(isA<StateError>()));
      });
    });

    group('onConnectionStateChanged', () {
      test('routes event to correct device stream', () async {
        when(() => mockHostApi.connect('device1', any()))
            .thenAnswer((_) async => 'device1');

        await connectionManager.connect(
          'device1',
          PlatformConnectConfig(timeoutMs: null, mtu: null),
        );

        final states = <PlatformConnectionState>[];
        final sub = connectionManager
            .connectionStateStream('device1')
            .listen(states.add);

        connectionManager.onConnectionStateChanged(
          ConnectionStateEventDto(
            deviceId: 'device1',
            state: ConnectionStateDto.connected,
          ),
        );

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(states, [PlatformConnectionState.connected]);
      });
    });

    group('onNotification', () {
      test('routes notification to correct device stream', () async {
        when(() => mockHostApi.connect('device1', any()))
            .thenAnswer((_) async => 'device1');

        await connectionManager.connect(
          'device1',
          PlatformConnectConfig(timeoutMs: null, mtu: null),
        );

        final notifications = <PlatformNotification>[];
        final sub = connectionManager
            .notificationStream('device1')
            .listen(notifications.add);

        connectionManager.onNotification(NotificationEventDto(
          deviceId: 'device1',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x00, 72]),
        ));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(notifications, hasLength(1));
        expect(notifications.first.characteristicUuid,
            '00002a37-0000-1000-8000-00805f9b34fb');
        expect(notifications.first.value, Uint8List.fromList([0x00, 72]));
      });
    });

    group('GATT operations', () {
      test('discoverServices maps DTOs correctly', () async {
        when(() => mockHostApi.discoverServices('device1'))
            .thenAnswer((_) async => [
                  ServiceDto(
                    uuid: '0000180d-0000-1000-8000-00805f9b34fb',
                    isPrimary: true,
                    characteristics: [
                      CharacteristicDto(
                        uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                        properties: CharacteristicPropertiesDto(
                          canRead: false,
                          canWrite: false,
                          canWriteWithoutResponse: false,
                          canNotify: true,
                          canIndicate: false,
                        ),
                        descriptors: [],
                      ),
                    ],
                    includedServices: [],
                  ),
                ]);

        final services =
            await connectionManager.discoverServices('device1');

        expect(services, hasLength(1));
        expect(services.first.uuid, '0000180d-0000-1000-8000-00805f9b34fb');
        expect(services.first.isPrimary, isTrue);
        expect(services.first.characteristics, hasLength(1));
        expect(services.first.characteristics.first.properties.canNotify,
            isTrue);
      });

      test('readCharacteristic delegates to hostApi', () async {
        final data = Uint8List.fromList([1, 2, 3]);
        when(() => mockHostApi.readCharacteristic('device1', 'char-uuid'))
            .thenAnswer((_) async => data);

        final result = await connectionManager.readCharacteristic(
            'device1', 'char-uuid');

        expect(result, data);
      });

      test('writeCharacteristic delegates to hostApi', () async {
        final data = Uint8List.fromList([1, 2, 3]);
        when(() => mockHostApi.writeCharacteristic(
              'device1', 'char-uuid', data, true))
            .thenAnswer((_) async {});

        await connectionManager.writeCharacteristic(
            'device1', 'char-uuid', data, true);

        verify(() => mockHostApi.writeCharacteristic(
            'device1', 'char-uuid', data, true)).called(1);
      });

      test('requestMtu delegates to hostApi', () async {
        when(() => mockHostApi.requestMtu('device1', 512))
            .thenAnswer((_) async => 512);

        final mtu = await connectionManager.requestMtu('device1', 512);

        expect(mtu, 512);
      });
    });

    group('bonding stubs', () {
      test('getBondState returns none', () async {
        final state = await connectionManager.getBondState('device1');
        expect(state, PlatformBondState.none);
      });

      test('bondStateStream returns empty stream', () {
        final stream = connectionManager.bondStateStream('device1');
        expect(stream, emitsDone);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd bluey_android && flutter test test/android_connection_manager_test.dart`
Expected: FAIL — `AndroidConnectionManager` not found.

- [ ] **Step 3: Implement `AndroidConnectionManager`**

Create `bluey_android/lib/src/android_connection_manager.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'messages.g.dart';

/// Handles BLE connection and GATT client operations for the Android platform.
///
/// Manages per-device stream controllers for connection state and notifications.
/// Cleans up streams on disconnect.
class AndroidConnectionManager {
  final BlueyHostApi _hostApi;
  final Map<String, StreamController<PlatformConnectionState>>
      _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
      _notificationControllers = {};

  AndroidConnectionManager(this._hostApi);

  // === Connection ===

  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    final dto = ConnectConfigDto(timeoutMs: config.timeoutMs, mtu: config.mtu);
    _connectionStateControllers[deviceId] =
        StreamController<PlatformConnectionState>.broadcast();
    _notificationControllers[deviceId] =
        StreamController<PlatformNotification>.broadcast();
    return await _hostApi.connect(deviceId, dto);
  }

  Future<void> disconnect(String deviceId) async {
    await _hostApi.disconnect(deviceId);
    final stateController = _connectionStateControllers.remove(deviceId);
    await stateController?.close();
    final notificationController = _notificationControllers.remove(deviceId);
    await notificationController?.close();
  }

  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    final controller = _connectionStateControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  Stream<PlatformNotification> notificationStream(String deviceId) {
    final controller = _notificationControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  // === GATT Operations ===

  Future<List<PlatformService>> discoverServices(String deviceId) async {
    final services = await _hostApi.discoverServices(deviceId);
    return services.map(_mapService).toList();
  }

  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    return await _hostApi.readCharacteristic(deviceId, characteristicUuid);
  }

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

  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {
    await _hostApi.setNotification(deviceId, characteristicUuid, enable);
  }

  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    return await _hostApi.readDescriptor(deviceId, descriptorUuid);
  }

  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {
    await _hostApi.writeDescriptor(deviceId, descriptorUuid, value);
  }

  Future<int> requestMtu(String deviceId, int mtu) async {
    return await _hostApi.requestMtu(deviceId, mtu);
  }

  Future<int> readRssi(String deviceId) async {
    return await _hostApi.readRssi(deviceId);
  }

  // === Bonding (stubs) ===

  Future<PlatformBondState> getBondState(String deviceId) async {
    return PlatformBondState.none;
  }

  Stream<PlatformBondState> bondStateStream(String deviceId) {
    return const Stream.empty();
  }

  Future<void> bond(String deviceId) async {}

  Future<void> removeBond(String deviceId) async {}

  Future<List<PlatformDevice>> getBondedDevices() async {
    return [];
  }

  // === PHY (stubs) ===

  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    return (tx: PlatformPhy.le1m, rx: PlatformPhy.le1m);
  }

  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    return const Stream.empty();
  }

  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {}

  // === Connection Parameters (stubs) ===

  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    return const PlatformConnectionParameters(
      intervalMs: 30,
      latency: 0,
      timeoutMs: 5000,
    );
  }

  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {}

  // === Callback handlers ===

  void onConnectionStateChanged(ConnectionStateEventDto event) {
    final controller = _connectionStateControllers[event.deviceId];
    if (controller != null) {
      controller.add(_mapConnectionState(event.state));
    }
  }

  void onNotification(NotificationEventDto event) {
    final controller = _notificationControllers[event.deviceId];
    if (controller != null) {
      controller.add(PlatformNotification(
        deviceId: event.deviceId,
        characteristicUuid: event.characteristicUuid,
        value: event.value,
      ));
    }
  }

  void onMtuChanged(MtuChangedEventDto event) {
    // MTU change notification — not exposed as separate stream currently.
  }

  // === DTO mapping ===

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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_android && flutter test test/android_connection_manager_test.dart`
Expected: All 10 tests PASS.

- [ ] **Step 5: Update `BlueyAndroid` to delegate connection operations**

In `bluey_android/lib/src/bluey_android.dart`:

Add import:
```dart
import 'android_connection_manager.dart';
```

Add field:
```dart
late final AndroidConnectionManager _connectionManager =
    AndroidConnectionManager(_hostApi);
```

In `_ensureInitialized()`, replace the connection/notification callback wiring:
```dart
_flutterApi.onConnectionStateChangedCallback = (event) {
  _connectionManager.onConnectionStateChanged(event);
};

_flutterApi.onNotificationCallback = (event) {
  _connectionManager.onNotification(event);
};

_flutterApi.onMtuChangedCallback = (event) {
  _connectionManager.onMtuChanged(event);
};
```

Replace all connection, GATT, bonding, PHY, and connection parameter methods with delegation:
```dart
@override
Future<String> connect(String deviceId, PlatformConnectConfig config) async {
  _ensureInitialized();
  return _connectionManager.connect(deviceId, config);
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
```

And so on for: `discoverServices`, `readCharacteristic`, `writeCharacteristic`, `setNotification`, `notificationStream`, `readDescriptor`, `writeDescriptor`, `requestMtu`, `readRssi`, `getBondState`, `bondStateStream`, `bond`, `removeBond`, `getBondedDevices`, `getPhy`, `phyStream`, `requestPhy`, `getConnectionParameters`, `requestConnectionParameters`.

Remove from `BlueyAndroid`:
- `_connectionStateControllers` map
- `_notificationControllers` map
- `_mapConnectionState()` method
- `_mapService()` method
- `_mapCharacteristic()` method
- `_mapDescriptor()` method

- [ ] **Step 6: Run all tests**

Run: `cd bluey_android && flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
cd bluey_android && git add lib/src/android_connection_manager.dart lib/src/bluey_android.dart test/android_connection_manager_test.dart
git commit -m "refactor: extract AndroidConnectionManager from BlueyAndroid

Move connection, GATT client, bonding, PHY, and connection parameter
operations into dedicated class. Manages per-device streams with
cleanup on disconnect. Add 10 unit tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Extract `AndroidServer`

**Files:**
- Create: `bluey_android/test/android_server_test.dart`
- Create: `bluey_android/lib/src/android_server.dart`
- Modify: `bluey_android/lib/src/bluey_android.dart`

- [ ] **Step 1: Write failing tests for `AndroidServer`**

Create `bluey_android/test/android_server_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_android/src/android_server.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  late MockBlueyHostApi mockHostApi;
  late AndroidServer server;

  setUpAll(() {
    registerFallbackValue(LocalServiceDto(
      uuid: '',
      isPrimary: true,
      characteristics: [],
      includedServices: [],
    ));
    registerFallbackValue(AdvertiseConfigDto(serviceUuids: []));
    registerFallbackValue(GattStatusDto.success);
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    server = AndroidServer(mockHostApi);
  });

  group('AndroidServer', () {
    group('addService', () {
      test('maps PlatformLocalService to DTO and calls hostApi', () async {
        when(() => mockHostApi.addService(any())).thenAnswer((_) async {});

        final service = PlatformLocalService(
          uuid: '0000180f-0000-1000-8000-00805f9b34fb',
          isPrimary: true,
          characteristics: [
            PlatformLocalCharacteristic(
              uuid: '00002a19-0000-1000-8000-00805f9b34fb',
              properties: const PlatformCharacteristicProperties(
                canRead: true,
                canWrite: false,
                canWriteWithoutResponse: false,
                canNotify: false,
                canIndicate: false,
              ),
              permissions: const [PlatformGattPermission.read],
              descriptors: const [],
            ),
          ],
          includedServices: const [],
        );
        await server.addService(service);

        final captured = verify(() => mockHostApi.addService(captureAny()))
            .captured
            .single as LocalServiceDto;
        expect(captured.uuid, '0000180f-0000-1000-8000-00805f9b34fb');
        expect(captured.characteristics, hasLength(1));
        expect(captured.characteristics.first.properties.canRead, isTrue);
      });
    });

    group('startAdvertising', () {
      test('maps config to DTO and calls hostApi', () async {
        when(() => mockHostApi.startAdvertising(any()))
            .thenAnswer((_) async {});

        final config = PlatformAdvertiseConfig(
          name: 'Test Device',
          serviceUuids: ['0000180f-0000-1000-8000-00805f9b34fb'],
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: Uint8List.fromList([1, 2, 3]),
          timeoutMs: 30000,
          mode: PlatformAdvertiseMode.lowLatency,
        );
        await server.startAdvertising(config);

        final captured =
            verify(() => mockHostApi.startAdvertising(captureAny()))
                .captured
                .single as AdvertiseConfigDto;
        expect(captured.name, 'Test Device');
        expect(captured.serviceUuids, hasLength(1));
        expect(captured.manufacturerDataCompanyId, 0x004C);
        expect(captured.mode, AdvertiseModeDto.lowLatency);
      });
    });

    group('notify and indicate', () {
      test('notifyCharacteristic calls hostApi', () async {
        final data = Uint8List.fromList([1, 2, 3]);
        when(() => mockHostApi.notifyCharacteristic('char-uuid', data))
            .thenAnswer((_) async {});

        await server.notifyCharacteristic('char-uuid', data);

        verify(() => mockHostApi.notifyCharacteristic('char-uuid', data))
            .called(1);
      });

      test('indicateCharacteristic calls notifyCharacteristic on hostApi',
          () async {
        final data = Uint8List.fromList([1, 2, 3]);
        when(() => mockHostApi.notifyCharacteristic('char-uuid', data))
            .thenAnswer((_) async {});

        await server.indicateCharacteristic('char-uuid', data);

        verify(() => mockHostApi.notifyCharacteristic('char-uuid', data))
            .called(1);
      });
    });

    group('callbacks', () {
      test('onCentralConnected emits to connections stream', () async {
        final centrals = <PlatformCentral>[];
        final sub = server.centralConnections.listen(centrals.add);

        server.onCentralConnected(CentralDto(id: 'central-1', mtu: 512));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(centrals, hasLength(1));
        expect(centrals.first.id, 'central-1');
        expect(centrals.first.mtu, 512);
      });

      test('onCentralDisconnected emits to disconnections stream', () async {
        final disconnections = <String>[];
        final sub = server.centralDisconnections.listen(disconnections.add);

        server.onCentralDisconnected('central-1');

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(disconnections, ['central-1']);
      });

      test('onReadRequest emits to readRequests stream', () async {
        final requests = <PlatformReadRequest>[];
        final sub = server.readRequests.listen(requests.add);

        server.onReadRequest(ReadRequestDto(
          requestId: 42,
          centralId: 'central-1',
          characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
          offset: 0,
        ));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(requests, hasLength(1));
        expect(requests.first.requestId, 42);
        expect(requests.first.centralId, 'central-1');
      });

      test('onWriteRequest emits to writeRequests stream', () async {
        final requests = <PlatformWriteRequest>[];
        final sub = server.writeRequests.listen(requests.add);

        server.onWriteRequest(WriteRequestDto(
          requestId: 43,
          centralId: 'central-1',
          characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([10, 20]),
          offset: 0,
          responseNeeded: true,
        ));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(requests, hasLength(1));
        expect(requests.first.requestId, 43);
        expect(requests.first.responseNeeded, isTrue);
      });
    });

    group('respondToReadRequest', () {
      test('calls hostApi with correct DTO mapping', () async {
        final data = Uint8List.fromList([42]);
        when(() => mockHostApi.respondToReadRequest(1, any(), data))
            .thenAnswer((_) async {});

        await server.respondToReadRequest(
          1,
          PlatformGattStatus.success,
          data,
        );

        verify(() => mockHostApi.respondToReadRequest(
              1,
              GattStatusDto.success,
              data,
            )).called(1);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd bluey_android && flutter test test/android_server_test.dart`
Expected: FAIL — `AndroidServer` not found.

- [ ] **Step 3: Implement `AndroidServer`**

Create `bluey_android/lib/src/android_server.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'messages.g.dart';

/// Handles BLE GATT server (peripheral) operations for the Android platform.
///
/// Manages server streams for central connections, disconnections,
/// and read/write requests.
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

  // === Streams ===

  Stream<PlatformCentral> get centralConnections =>
      _centralConnectionsController.stream;

  Stream<String> get centralDisconnections =>
      _centralDisconnectionsController.stream;

  Stream<PlatformReadRequest> get readRequests =>
      _readRequestsController.stream;

  Stream<PlatformWriteRequest> get writeRequests =>
      _writeRequestsController.stream;

  // === Service management ===

  Future<void> addService(PlatformLocalService service) async {
    final dto = _mapLocalServiceToDto(service);
    await _hostApi.addService(dto);
  }

  Future<void> removeService(String serviceUuid) async {
    await _hostApi.removeService(serviceUuid);
  }

  // === Advertising ===

  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
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

  Future<void> stopAdvertising() async {
    await _hostApi.stopAdvertising();
  }

  // === Notifications and indications ===

  Future<void> notifyCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristic(characteristicUuid, value);
  }

  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristicTo(
        centralId, characteristicUuid, value);
  }

  Future<void> indicateCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {
    // Android uses the same API for notifications and indications.
    // The characteristic's properties determine which is used.
    await _hostApi.notifyCharacteristic(characteristicUuid, value);
  }

  Future<void> indicateCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristicTo(
        centralId, characteristicUuid, value);
  }

  // === Request/response ===

  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    await _hostApi.respondToReadRequest(
      requestId,
      _mapGattStatusToDto(status),
      value,
    );
  }

  Future<void> respondToWriteRequest(
    int requestId,
    PlatformGattStatus status,
  ) async {
    await _hostApi.respondToWriteRequest(
      requestId,
      _mapGattStatusToDto(status),
    );
  }

  Future<void> disconnectCentral(String centralId) async {
    await _hostApi.disconnectCentral(centralId);
  }

  Future<void> closeServer() async {
    await _hostApi.closeServer();
  }

  // === Callback handlers ===

  void onCentralConnected(CentralDto central) {
    _centralConnectionsController.add(
      PlatformCentral(id: central.id, mtu: central.mtu),
    );
  }

  void onCentralDisconnected(String centralId) {
    _centralDisconnectionsController.add(centralId);
  }

  void onReadRequest(ReadRequestDto request) {
    _readRequestsController.add(PlatformReadRequest(
      requestId: request.requestId,
      centralId: request.centralId,
      characteristicUuid: request.characteristicUuid,
      offset: request.offset,
    ));
  }

  void onWriteRequest(WriteRequestDto request) {
    _writeRequestsController.add(PlatformWriteRequest(
      requestId: request.requestId,
      centralId: request.centralId,
      characteristicUuid: request.characteristicUuid,
      value: request.value,
      offset: request.offset,
      responseNeeded: request.responseNeeded,
    ));
  }

  // === DTO mapping ===

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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_android && flutter test test/android_server_test.dart`
Expected: All 9 tests PASS.

- [ ] **Step 5: Update `BlueyAndroid` to delegate server operations**

In `bluey_android/lib/src/bluey_android.dart`:

Add import:
```dart
import 'android_server.dart';
```

Add field:
```dart
late final AndroidServer _server = AndroidServer(_hostApi);
```

In `_ensureInitialized()`, replace the server callback wiring:
```dart
_flutterApi.onCentralConnectedCallback = (central) {
  _server.onCentralConnected(central);
};

_flutterApi.onCentralDisconnectedCallback = (centralId) {
  _server.onCentralDisconnected(centralId);
};

_flutterApi.onReadRequestCallback = (request) {
  _server.onReadRequest(request);
};

_flutterApi.onWriteRequestCallback = (request) {
  _server.onWriteRequest(request);
};

_flutterApi.onCharacteristicSubscribedCallback = (centralId, characteristicUuid) {
  // Could expose this as a stream if needed
};

_flutterApi.onCharacteristicUnsubscribedCallback = (centralId, characteristicUuid) {
  // Could expose this as a stream if needed
};
```

Replace all server methods with delegation:
```dart
@override
Future<void> addService(PlatformLocalService service) async {
  _ensureInitialized();
  await _server.addService(service);
}
```

And so on for: `removeService`, `startAdvertising`, `stopAdvertising`, `notifyCharacteristic`, `notifyCharacteristicTo`, `indicateCharacteristic`, `indicateCharacteristicTo`, `centralConnections`, `centralDisconnections`, `readRequests`, `writeRequests`, `respondToReadRequest`, `respondToWriteRequest`, `disconnectCentral`, `closeServer`.

Remove from `BlueyAndroid`:
- `_centralConnectionsController`
- `_centralDisconnectionsController`
- `_readRequestsController`
- `_writeRequestsController`
- `_mapLocalServiceToDto()`
- `_mapLocalCharacteristicToDto()`
- `_mapLocalDescriptorToDto()`
- `_mapGattPermissionToDto()`
- `_mapGattStatusToDto()`
- `_mapAdvertiseModeToDto()`

- [ ] **Step 6: Run all tests**

Run: `cd bluey_android && flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
cd bluey_android && git add lib/src/android_server.dart lib/src/bluey_android.dart test/android_server_test.dart
git commit -m "refactor: extract AndroidServer from BlueyAndroid

Move GATT server, advertising, and request handling into dedicated
class. Manages server streams for centrals and requests. Add 9 unit
tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Final Verification

**Files:** None modified.

- [ ] **Step 1: Run full test suite**

Run: `cd bluey_android && flutter test`
Expected: All tests pass (~26 total: 2 existing + 5 scanner + 10 connection + 9 server).

- [ ] **Step 2: Run static analysis**

Run: `cd bluey_android && flutter analyze`
Expected: No new issues.

- [ ] **Step 3: Verify `BlueyAndroid` is now a thin coordinator**

Run: `wc -l bluey_android/lib/src/bluey_android.dart`
Expected: ~150-180 lines (down from 777).

- [ ] **Step 4: Verify file structure**

Run: `ls bluey_android/lib/src/*.dart`

Expected:
```
bluey_android/lib/src/android_connection_manager.dart
bluey_android/lib/src/android_scanner.dart
bluey_android/lib/src/android_server.dart
bluey_android/lib/src/bluey_android.dart
bluey_android/lib/src/messages.g.dart
```

- [ ] **Step 5: Run bluey core tests to verify no regressions**

Run: `cd bluey && flutter test`
Expected: All 450 tests pass.
