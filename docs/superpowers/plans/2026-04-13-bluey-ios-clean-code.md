# bluey_ios Clean Code Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `BlueyIos` class (812 lines) into focused delegate classes, add Dart-side unit tests, and add Swift-side timeout handling for stalled CoreBluetooth operations.

**Architecture:** Extract scanning, connection management, and server operations into separate delegate classes (mirroring bluey_android). Add `DispatchQueue.main.asyncAfter` timeouts in `CentralManagerImpl.swift` for operations that could hang indefinitely. Tests mock `BlueyHostApi` with `mocktail`.

**Tech Stack:** Dart, Flutter, Swift, CoreBluetooth, Pigeon (generated), mocktail (testing)

**Spec:** `docs/superpowers/specs/2026-04-13-bluey-ios-clean-code-design.md`

---

## Task 1: Add `mocktail`, Create Mock, and Extract `expandUuid`

**Files:**
- Modify: `bluey_ios/pubspec.yaml`
- Create: `bluey_ios/test/mocks.dart`
- Create: `bluey_ios/lib/src/uuid_utils.dart`
- Modify: `bluey_ios/lib/src/bluey_ios.dart`

- [ ] **Step 1: Add `mocktail` dependency**

In `bluey_ios/pubspec.yaml`, add `mocktail` under `dev_dependencies`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^1.0.4
  pigeon: ^26.0.4
```

Run: `cd bluey_ios && flutter pub get`
Expected: Resolves successfully.

- [ ] **Step 2: Create shared mock file**

Create `bluey_ios/test/mocks.dart`:

```dart
import 'package:mocktail/mocktail.dart';
import 'package:bluey_ios/src/messages.g.dart';

class MockBlueyHostApi extends Mock implements BlueyHostApi {}
```

- [ ] **Step 3: Extract `expandUuid` to its own file**

Create `bluey_ios/lib/src/uuid_utils.dart`:

```dart
/// Bluetooth SIG base UUID suffix for short UUID expansion.
const bluetoothBaseUuidSuffix = '-0000-1000-8000-00805f9b34fb';

/// Expands a short UUID (4 or 8 hex chars) to full 128-bit UUID string.
///
/// CoreBluetooth may return UUIDs in short form. This function normalizes
/// them to the full 128-bit format expected by the domain layer.
///
/// Examples:
/// - "180F" -> "0000180f-0000-1000-8000-00805f9b34fb"
/// - "12345678" -> "12345678-0000-1000-8000-00805f9b34fb"
/// - Full UUID -> returned as-is (lowercased with hyphens)
String expandUuid(String uuid) {
  // Remove any existing hyphens and lowercase
  final clean = uuid.replaceAll('-', '').toLowerCase();

  // 16-bit short UUID (4 hex chars)
  if (clean.length == 4) {
    return '0000$clean$bluetoothBaseUuidSuffix';
  }

  // 32-bit short UUID (8 hex chars)
  if (clean.length == 8) {
    return '$clean$bluetoothBaseUuidSuffix';
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
```

- [ ] **Step 4: Update `bluey_ios.dart` to import `uuid_utils.dart`**

In `bluey_ios/lib/src/bluey_ios.dart`:

Remove the `_bluetoothBaseUuidSuffix` constant and the `_expandUuid` function (lines 7-43).

Add import at top:
```dart
import 'uuid_utils.dart';
```

Replace all calls to `_expandUuid(` with `expandUuid(` throughout the file.

- [ ] **Step 5: Run existing tests**

Run: `cd bluey_ios && flutter test`
Expected: All 12 existing tests pass.

- [ ] **Step 6: Commit**

```bash
cd bluey_ios && git add pubspec.yaml test/mocks.dart lib/src/uuid_utils.dart lib/src/bluey_ios.dart
git commit -m "chore: add mocktail, extract expandUuid to uuid_utils.dart

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Extract `IosScanner`

**Files:**
- Create: `bluey_ios/test/ios_scanner_test.dart`
- Create: `bluey_ios/lib/src/ios_scanner.dart`
- Modify: `bluey_ios/lib/src/bluey_ios.dart`

- [ ] **Step 1: Write failing tests for `IosScanner`**

Create `bluey_ios/test/ios_scanner_test.dart`:

```dart
import 'dart:async';

import 'package:bluey_ios/src/ios_scanner.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_ios/src/uuid_utils.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  late MockBlueyHostApi mockHostApi;
  late IosScanner scanner;

  setUpAll(() {
    registerFallbackValue(ScanConfigDto(serviceUuids: [], timeoutMs: null));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    scanner = IosScanner(mockHostApi);
  });

  group('IosScanner', () {
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

    test('onDeviceDiscovered emits device with expanded UUIDs', () async {
      when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

      final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);
      final devices = <PlatformDevice>[];
      final sub = scanner.scan(config).listen(devices.add);

      scanner.onDeviceDiscovered(DeviceDto(
        id: 'abc-123',
        name: 'Test Device',
        rssi: -65,
        serviceUuids: ['180D', '180F'],
        manufacturerDataCompanyId: null,
        manufacturerData: null,
      ));

      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(devices, hasLength(1));
      expect(devices.first.id, 'abc-123');
      expect(devices.first.name, 'Test Device');
      expect(devices.first.rssi, -65);
      // Short UUIDs should be expanded
      expect(devices.first.serviceUuids, [
        '0000180d-0000-1000-8000-00805f9b34fb',
        '0000180f-0000-1000-8000-00805f9b34fb',
      ]);
    });

    test('onDeviceDiscovered maps manufacturer data', () async {
      when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

      final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);
      final devices = <PlatformDevice>[];
      final sub = scanner.scan(config).listen(devices.add);

      scanner.onDeviceDiscovered(DeviceDto(
        id: 'abc-123',
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

  group('expandUuid', () {
    test('expands 16-bit short UUID', () {
      expect(expandUuid('180F'),
          '0000180f-0000-1000-8000-00805f9b34fb');
    });

    test('expands 32-bit short UUID', () {
      expect(expandUuid('12345678'),
          '12345678-0000-1000-8000-00805f9b34fb');
    });

    test('passes through full 128-bit UUID', () {
      expect(expandUuid('0000180d-0000-1000-8000-00805f9b34fb'),
          '0000180d-0000-1000-8000-00805f9b34fb');
    });

    test('normalizes case', () {
      expect(expandUuid('180f'),
          '0000180f-0000-1000-8000-00805f9b34fb');
      expect(expandUuid('180F'),
          '0000180f-0000-1000-8000-00805f9b34fb');
    });

    test('handles full UUID without hyphens', () {
      expect(expandUuid('0000180d00001000800000805f9b34fb'),
          '0000180d-0000-1000-8000-00805f9b34fb');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd bluey_ios && flutter test test/ios_scanner_test.dart`
Expected: FAIL — `IosScanner` not found.

- [ ] **Step 3: Implement `IosScanner`**

Create `bluey_ios/lib/src/ios_scanner.dart`:

```dart
import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'messages.g.dart';
import 'uuid_utils.dart';

/// Handles BLE scanning operations for the iOS platform.
///
/// Delegates to [BlueyHostApi] for platform calls and manages the
/// scan result stream. Expands short CoreBluetooth UUIDs to full
/// 128-bit format.
class IosScanner {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();

  IosScanner(this._hostApi);

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
      serviceUuids: dto.serviceUuids.map(expandUuid).toList(),
      manufacturerDataCompanyId: dto.manufacturerDataCompanyId,
      manufacturerData: dto.manufacturerData,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_ios && flutter test test/ios_scanner_test.dart`
Expected: All 10 tests PASS.

- [ ] **Step 5: Update `BlueyIos` to delegate scanning to `IosScanner`**

In `bluey_ios/lib/src/bluey_ios.dart`:

Add import:
```dart
import 'ios_scanner.dart';
```

Add field:
```dart
late final IosScanner _scanner = IosScanner(_hostApi);
```

In `_ensureInitialized()`, replace the scan callback wiring:
```dart
_flutterApi.onDeviceDiscoveredCallback = (device) {
  _scanner.onDeviceDiscovered(device);
};

_flutterApi.onScanCompleteCallback = () {
  _scanner.onScanComplete();
};
```

Replace the `scan()` and `stopScan()` methods:
```dart
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
```

Remove `_scanController` field and `_mapDevice()` method from `BlueyIos`.

- [ ] **Step 6: Run all tests**

Run: `cd bluey_ios && flutter test`
Expected: All tests pass (12 existing + 10 new).

- [ ] **Step 7: Commit**

```bash
cd bluey_ios && git add lib/src/ios_scanner.dart lib/src/bluey_ios.dart test/ios_scanner_test.dart
git commit -m "refactor: extract IosScanner from BlueyIos

Move scanning logic into dedicated IosScanner class with UUID expansion
and device DTO mapping. Add 10 unit tests including expandUuid coverage.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Extract `IosConnectionManager`

**Files:**
- Create: `bluey_ios/test/ios_connection_manager_test.dart`
- Create: `bluey_ios/lib/src/ios_connection_manager.dart`
- Modify: `bluey_ios/lib/src/bluey_ios.dart`

- [ ] **Step 1: Write failing tests for `IosConnectionManager`**

Create `bluey_ios/test/ios_connection_manager_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_ios/src/ios_connection_manager.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  late MockBlueyHostApi mockHostApi;
  late IosConnectionManager connectionManager;

  setUpAll(() {
    registerFallbackValue(ConnectConfigDto(timeoutMs: null, mtu: null));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    connectionManager = IosConnectionManager(mockHostApi);
  });

  group('IosConnectionManager', () {
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
      test('routes notification with expanded UUID', () async {
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
          characteristicUuid: '2A37',
          value: Uint8List.fromList([0x00, 72]),
        ));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(notifications, hasLength(1));
        // Short UUID should be expanded
        expect(notifications.first.characteristicUuid,
            '00002a37-0000-1000-8000-00805f9b34fb');
        expect(notifications.first.value, Uint8List.fromList([0x00, 72]));
      });
    });

    group('GATT operations', () {
      test('discoverServices maps DTOs with expanded UUIDs', () async {
        when(() => mockHostApi.discoverServices('device1'))
            .thenAnswer((_) async => [
                  ServiceDto(
                    uuid: '180D',
                    isPrimary: true,
                    characteristics: [
                      CharacteristicDto(
                        uuid: '2A37',
                        properties: CharacteristicPropertiesDto(
                          canRead: false,
                          canWrite: false,
                          canWriteWithoutResponse: false,
                          canNotify: true,
                          canIndicate: false,
                        ),
                        descriptors: [
                          DescriptorDto(uuid: '2902'),
                        ],
                      ),
                    ],
                    includedServices: [],
                  ),
                ]);

        final services =
            await connectionManager.discoverServices('device1');

        expect(services, hasLength(1));
        expect(services.first.uuid,
            '0000180d-0000-1000-8000-00805f9b34fb');
        expect(services.first.characteristics.first.uuid,
            '00002a37-0000-1000-8000-00805f9b34fb');
        expect(services.first.characteristics.first.descriptors.first.uuid,
            '00002902-0000-1000-8000-00805f9b34fb');
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
    });

    group('unsupported operations', () {
      test('requestMtu throws UnsupportedError', () {
        expect(
          () => connectionManager.requestMtu('device1', 512),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('removeBond throws UnsupportedError', () {
        expect(
          () => connectionManager.removeBond('device1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('getPhy throws UnsupportedError', () {
        expect(
          () => connectionManager.getPhy('device1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('requestPhy throws UnsupportedError', () {
        expect(
          () => connectionManager.requestPhy(
              'device1', PlatformPhy.le2m, null),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('getConnectionParameters throws UnsupportedError', () {
        expect(
          () => connectionManager.getConnectionParameters('device1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('requestConnectionParameters throws UnsupportedError', () {
        expect(
          () => connectionManager.requestConnectionParameters(
            'device1',
            const PlatformConnectionParameters(
              intervalMs: 15,
              latency: 0,
              timeoutMs: 5000,
            ),
          ),
          throwsA(isA<UnsupportedError>()),
        );
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

      test('bond completes without error', () async {
        await connectionManager.bond('device1');
      });

      test('getBondedDevices returns empty list', () async {
        final devices = await connectionManager.getBondedDevices();
        expect(devices, isEmpty);
      });
    });

    group('PHY stubs', () {
      test('phyStream returns empty stream', () {
        final stream = connectionManager.phyStream('device1');
        expect(stream, emitsDone);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd bluey_ios && flutter test test/ios_connection_manager_test.dart`
Expected: FAIL — `IosConnectionManager` not found.

- [ ] **Step 3: Implement `IosConnectionManager`**

Create `bluey_ios/lib/src/ios_connection_manager.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'messages.g.dart';
import 'uuid_utils.dart';

/// Handles BLE connection and GATT client operations for the iOS platform.
///
/// Manages per-device stream controllers for connection state and notifications.
/// Expands short CoreBluetooth UUIDs to full 128-bit format.
/// Cleans up streams on disconnect.
class IosConnectionManager {
  final BlueyHostApi _hostApi;
  final Map<String, StreamController<PlatformConnectionState>>
      _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
      _notificationControllers = {};

  IosConnectionManager(this._hostApi);

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
    throw UnsupportedError(
      'iOS does not support requesting a specific MTU. '
      'MTU is automatically negotiated by the system.',
    );
  }

  Future<int> readRssi(String deviceId) async {
    return await _hostApi.readRssi(deviceId);
  }

  // === Bonding (iOS handles automatically) ===

  Future<PlatformBondState> getBondState(String deviceId) async {
    return PlatformBondState.none;
  }

  Stream<PlatformBondState> bondStateStream(String deviceId) {
    return const Stream.empty();
  }

  Future<void> bond(String deviceId) async {
    // iOS handles bonding automatically when accessing encrypted characteristics
  }

  Future<void> removeBond(String deviceId) async {
    throw UnsupportedError(
      'iOS does not support removing bonds programmatically. '
      'Users must remove the device from Settings > Bluetooth.',
    );
  }

  Future<List<PlatformDevice>> getBondedDevices() async {
    return [];
  }

  // === PHY (not available on iOS) ===

  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    throw UnsupportedError('iOS does not support reading PHY information.');
  }

  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    return const Stream.empty();
  }

  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    throw UnsupportedError('iOS does not support requesting PHY settings.');
  }

  // === Connection Parameters (not available on iOS) ===

  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    throw UnsupportedError(
      'iOS does not support reading connection parameters.',
    );
  }

  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    throw UnsupportedError(
      'iOS does not support requesting connection parameters.',
    );
  }

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
        characteristicUuid: expandUuid(event.characteristicUuid),
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
      uuid: expandUuid(dto.uuid),
      isPrimary: dto.isPrimary,
      characteristics: dto.characteristics.map(_mapCharacteristic).toList(),
      includedServices: dto.includedServices.map(_mapService).toList(),
    );
  }

  PlatformCharacteristic _mapCharacteristic(CharacteristicDto dto) {
    return PlatformCharacteristic(
      uuid: expandUuid(dto.uuid),
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
    return PlatformDescriptor(uuid: expandUuid(dto.uuid));
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_ios && flutter test test/ios_connection_manager_test.dart`
Expected: All 18 tests PASS.

- [ ] **Step 5: Update `BlueyIos` to delegate connection operations**

In `bluey_ios/lib/src/bluey_ios.dart`:

Add import:
```dart
import 'ios_connection_manager.dart';
```

Add field:
```dart
late final IosConnectionManager _connectionManager =
    IosConnectionManager(_hostApi);
```

In `_ensureInitialized()`, wire callbacks:
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

Replace ALL connection/GATT/bonding/PHY/params methods with delegation (keep `_ensureInitialized()` in each). This includes: `connect`, `disconnect`, `connectionStateStream`, `discoverServices`, `readCharacteristic`, `writeCharacteristic`, `setNotification`, `notificationStream`, `readDescriptor`, `writeDescriptor`, `requestMtu`, `readRssi`, `getBondState`, `bondStateStream`, `bond`, `removeBond`, `getBondedDevices`, `getPhy`, `phyStream`, `requestPhy`, `getConnectionParameters`, `requestConnectionParameters`.

Note: For methods that throw `UnsupportedError` (requestMtu, removeBond, getPhy, etc.), the delegate handles the throw — the coordinator just delegates without `_ensureInitialized()` since it won't reach the platform anyway.

Remove from `BlueyIos`: `_connectionStateControllers`, `_notificationControllers`, `_mapConnectionState()`, `_mapService()`, `_mapCharacteristic()`, `_mapDescriptor()`.

- [ ] **Step 6: Run all tests**

Run: `cd bluey_ios && flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
cd bluey_ios && git add lib/src/ios_connection_manager.dart lib/src/bluey_ios.dart test/ios_connection_manager_test.dart
git commit -m "refactor: extract IosConnectionManager from BlueyIos

Move connection, GATT client, bonding, PHY, and connection parameter
operations into dedicated class. UUID expansion on all GATT mappings.
Per-device stream cleanup on disconnect. Add 18 unit tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Extract `IosServer`

**Files:**
- Create: `bluey_ios/test/ios_server_test.dart`
- Create: `bluey_ios/lib/src/ios_server.dart`
- Modify: `bluey_ios/lib/src/bluey_ios.dart`

- [ ] **Step 1: Write failing tests for `IosServer`**

Create `bluey_ios/test/ios_server_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_ios/src/ios_server.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  late MockBlueyHostApi mockHostApi;
  late IosServer server;

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
    server = IosServer(mockHostApi);
  });

  group('IosServer', () {
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
      test('maps config to DTO without mode (iOS)', () async {
        when(() => mockHostApi.startAdvertising(any()))
            .thenAnswer((_) async {});

        final config = PlatformAdvertiseConfig(
          name: 'Test Device',
          serviceUuids: ['0000180f-0000-1000-8000-00805f9b34fb'],
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: Uint8List.fromList([1, 2, 3]),
          timeoutMs: 30000,
        );
        await server.startAdvertising(config);

        final captured =
            verify(() => mockHostApi.startAdvertising(captureAny()))
                .captured
                .single as AdvertiseConfigDto;
        expect(captured.name, 'Test Device');
        expect(captured.serviceUuids, hasLength(1));
        expect(captured.manufacturerDataCompanyId, 0x004C);
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

        server.onCentralConnected(CentralDto(id: 'central-1', mtu: 185));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(centrals, hasLength(1));
        expect(centrals.first.id, 'central-1');
        expect(centrals.first.mtu, 185);
      });

      test('onCentralDisconnected emits to disconnections stream', () async {
        final disconnections = <String>[];
        final sub = server.centralDisconnections.listen(disconnections.add);

        server.onCentralDisconnected('central-1');

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(disconnections, ['central-1']);
      });

      test('onReadRequest emits with expanded UUID', () async {
        final requests = <PlatformReadRequest>[];
        final sub = server.readRequests.listen(requests.add);

        server.onReadRequest(ReadRequestDto(
          requestId: 42,
          centralId: 'central-1',
          characteristicUuid: '2A19',
          offset: 0,
        ));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(requests, hasLength(1));
        expect(requests.first.requestId, 42);
        expect(requests.first.characteristicUuid,
            '00002a19-0000-1000-8000-00805f9b34fb');
      });

      test('onWriteRequest emits with expanded UUID', () async {
        final requests = <PlatformWriteRequest>[];
        final sub = server.writeRequests.listen(requests.add);

        server.onWriteRequest(WriteRequestDto(
          requestId: 43,
          centralId: 'central-1',
          characteristicUuid: '2A19',
          value: Uint8List.fromList([10, 20]),
          offset: 0,
          responseNeeded: true,
        ));

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(requests, hasLength(1));
        expect(requests.first.characteristicUuid,
            '00002a19-0000-1000-8000-00805f9b34fb');
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

Run: `cd bluey_ios && flutter test test/ios_server_test.dart`
Expected: FAIL — `IosServer` not found.

- [ ] **Step 3: Implement `IosServer`**

Create `bluey_ios/lib/src/ios_server.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'messages.g.dart';
import 'uuid_utils.dart';

/// Handles BLE GATT server (peripheral) operations for the iOS platform.
///
/// Manages server streams for central connections, disconnections,
/// and read/write requests. Expands short CoreBluetooth UUIDs in
/// request characteristic fields.
class IosServer {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformCentral> _centralConnectionsController =
      StreamController<PlatformCentral>.broadcast();
  final StreamController<String> _centralDisconnectionsController =
      StreamController<String>.broadcast();
  final StreamController<PlatformReadRequest> _readRequestsController =
      StreamController<PlatformReadRequest>.broadcast();
  final StreamController<PlatformWriteRequest> _writeRequestsController =
      StreamController<PlatformWriteRequest>.broadcast();

  IosServer(this._hostApi);

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
    // iOS uses the same updateValue method for both notifications and indications.
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
      characteristicUuid: expandUuid(request.characteristicUuid),
      offset: request.offset,
    ));
  }

  void onWriteRequest(WriteRequestDto request) {
    _writeRequestsController.add(PlatformWriteRequest(
      requestId: request.requestId,
      centralId: request.centralId,
      characteristicUuid: expandUuid(request.characteristicUuid),
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_ios && flutter test test/ios_server_test.dart`
Expected: All 9 tests PASS.

- [ ] **Step 5: Update `BlueyIos` to delegate server operations**

In `bluey_ios/lib/src/bluey_ios.dart`:

Add import:
```dart
import 'ios_server.dart';
```

Add field:
```dart
late final IosServer _server = IosServer(_hostApi);
```

In `_ensureInitialized()`, wire server callbacks:
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
```

Replace all server methods with delegation. Remove: `_centralConnectionsController`, `_centralDisconnectionsController`, `_readRequestsController`, `_writeRequestsController`, all `_map*ToDto()` server methods.

- [ ] **Step 6: Run all tests**

Run: `cd bluey_ios && flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
cd bluey_ios && git add lib/src/ios_server.dart lib/src/bluey_ios.dart test/ios_server_test.dart
git commit -m "refactor: extract IosServer from BlueyIos

Move GATT server, advertising, and request handling into dedicated
class. UUID expansion on request characteristic UUIDs. Add 9 unit tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Add Swift-Side Timeout Handling

**Files:**
- Modify: `bluey_ios/ios/Classes/BlueyError.swift`
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift`

- [ ] **Step 1: Add `timeout` case to `BlueyError`**

In `bluey_ios/ios/Classes/BlueyError.swift`, add the timeout case:

```swift
enum BlueyError: Error {
    case unknown
    case illegalArgument
    case unsupported
    case notConnected
    case notFound
    case timeout
}

extension BlueyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred"
        case .illegalArgument:
            return "Invalid argument"
        case .unsupported:
            return "Operation not supported"
        case .notConnected:
            return "Device not connected"
        case .notFound:
            return "Resource not found"
        case .timeout:
            return "Operation timed out"
        }
    }
}
```

- [ ] **Step 2: Add timeout constants to `CentralManagerImpl.swift`**

At the top of `CentralManagerImpl.swift`, after the imports, add:

```swift
/// Default timeout values for BLE operations (in seconds).
private enum BleTimeout {
    static let connect: TimeInterval = 30.0
    static let discoverServices: TimeInterval = 15.0
    static let readCharacteristic: TimeInterval = 10.0
    static let writeCharacteristic: TimeInterval = 10.0
    static let readDescriptor: TimeInterval = 10.0
    static let writeDescriptor: TimeInterval = 10.0
    static let readRssi: TimeInterval = 5.0
}
```

- [ ] **Step 3: Add timeout to `connect()`**

In `CentralManagerImpl.swift`, modify the `connect` method. After storing the completion and calling `centralManager.connect()`, schedule a timeout:

```swift
func connect(deviceId: String, config: ConnectConfigDto, completion: @escaping (Result<String, Error>) -> Void) {
    guard let peripheral = peripherals[deviceId] else {
        completion(.failure(BlueyError.notFound))
        return
    }

    connectCompletions[deviceId] = { result in
        switch result {
        case .success:
            completion(.success(deviceId))
        case .failure(let error):
            completion(.failure(error))
        }
    }

    centralManager.connect(peripheral, options: nil)

    // Schedule timeout
    let timeoutSeconds = config.timeoutMs != nil
        ? TimeInterval(config.timeoutMs!) / 1000.0
        : BleTimeout.connect
    DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
        guard let self = self else { return }
        if let pendingCompletion = self.connectCompletions.removeValue(forKey: deviceId) {
            self.centralManager.cancelPeripheralConnection(peripheral)
            pendingCompletion(.failure(BlueyError.timeout))
        }
    }
}
```

- [ ] **Step 4: Add timeout to `discoverServices()`**

In `CentralManagerImpl.swift`, modify `discoverServices`. After storing the completion and calling `peripheral.discoverServices()`, schedule a timeout:

```swift
func discoverServices(deviceId: String, completion: @escaping (Result<[ServiceDto], Error>) -> Void) {
    guard let peripheral = peripherals[deviceId] else {
        completion(.failure(BlueyError.notFound))
        return
    }

    guard peripheral.state == .connected else {
        completion(.failure(BlueyError.notConnected))
        return
    }

    discoverServicesCompletions[deviceId] = completion
    peripheral.discoverServices(nil)

    // Schedule timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + BleTimeout.discoverServices) { [weak self] in
        guard let self = self else { return }
        if let pendingCompletion = self.discoverServicesCompletions.removeValue(forKey: deviceId) {
            self.pendingServiceDiscovery.removeValue(forKey: deviceId)
            self.pendingCharacteristicDiscovery.removeValue(forKey: deviceId)
            pendingCompletion(.failure(BlueyError.timeout))
        }
    }
}
```

- [ ] **Step 5: Add timeout to `readCharacteristic()`**

In `CentralManagerImpl.swift`, add after `peripheral.readValue(for: characteristic)`:

```swift
    // Schedule timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + BleTimeout.readCharacteristic) { [weak self] in
        guard let self = self else { return }
        if let pendingCompletion = self.readCharacteristicCompletions[deviceId]?.removeValue(forKey: cacheKey) {
            pendingCompletion(.failure(BlueyError.timeout))
        }
    }
```

- [ ] **Step 6: Add timeout to `writeCharacteristic()` (with-response only)**

In `CentralManagerImpl.swift`, add inside the `if withResponse` block, after storing the completion:

```swift
    if withResponse {
        let cacheKey = characteristic.uuid.uuidString.lowercased()
        writeCharacteristicCompletions[deviceId, default: [:]][cacheKey] = completion

        // Schedule timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + BleTimeout.writeCharacteristic) { [weak self] in
            guard let self = self else { return }
            if let pendingCompletion = self.writeCharacteristicCompletions[deviceId]?.removeValue(forKey: cacheKey) {
                pendingCompletion(.failure(BlueyError.timeout))
            }
        }
    }
```

- [ ] **Step 7: Add timeout to `readDescriptor()`**

In `CentralManagerImpl.swift`, add after `peripheral.readValue(for: descriptor)`:

```swift
    // Schedule timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + BleTimeout.readDescriptor) { [weak self] in
        guard let self = self else { return }
        if let pendingCompletion = self.readDescriptorCompletions[deviceId]?.removeValue(forKey: cacheKey) {
            pendingCompletion(.failure(BlueyError.timeout))
        }
    }
```

- [ ] **Step 8: Add timeout to `writeDescriptor()`**

In `CentralManagerImpl.swift`, add after `peripheral.writeValue(value.data, for: descriptor)`:

```swift
    // Schedule timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + BleTimeout.writeDescriptor) { [weak self] in
        guard let self = self else { return }
        if let pendingCompletion = self.writeDescriptorCompletions[deviceId]?.removeValue(forKey: cacheKey) {
            pendingCompletion(.failure(BlueyError.timeout))
        }
    }
```

- [ ] **Step 9: Add timeout to `readRssi()`**

In `CentralManagerImpl.swift`, add after `peripheral.readRSSI()`:

```swift
    // Schedule timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + BleTimeout.readRssi) { [weak self] in
        guard let self = self else { return }
        if let pendingCompletion = self.readRssiCompletions.removeValue(forKey: deviceId) {
            pendingCompletion(.failure(BlueyError.timeout))
        }
    }
```

- [ ] **Step 10: Run Dart tests to verify nothing broke**

Run: `cd bluey_ios && flutter test`
Expected: All Dart tests pass (Swift changes don't affect Dart tests).

- [ ] **Step 11: Commit**

```bash
cd bluey_ios && git add ios/Classes/BlueyError.swift ios/Classes/CentralManagerImpl.swift
git commit -m "feat: add timeout handling for stalled CoreBluetooth operations

Add DispatchQueue.main.asyncAfter timeouts to connect (30s/configurable),
discoverServices (15s), read/write characteristic (10s), read/write
descriptor (10s), and readRssi (5s). Prevents Futures from hanging
indefinitely when peripherals are unresponsive. Connect timeout cancels
the pending CBCentralManager connection.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Final Verification

**Files:** None modified.

- [ ] **Step 1: Run full iOS test suite**

Run: `cd bluey_ios && flutter test`
Expected: All tests pass (~49 total: 12 existing + ~37 new).

- [ ] **Step 2: Verify `BlueyIos` is now a thin coordinator**

Run: `wc -l bluey_ios/lib/src/bluey_ios.dart`
Expected: Significantly reduced from 812 lines.

- [ ] **Step 3: Verify file structure**

Run: `ls bluey_ios/lib/src/*.dart`

Expected:
```
bluey_ios/lib/src/bluey_ios.dart
bluey_ios/lib/src/ios_connection_manager.dart
bluey_ios/lib/src/ios_scanner.dart
bluey_ios/lib/src/ios_server.dart
bluey_ios/lib/src/messages.g.dart
bluey_ios/lib/src/uuid_utils.dart
```

- [ ] **Step 4: Verify Swift timeout constants exist**

Run: `grep -n "BleTimeout" bluey_ios/ios/Classes/CentralManagerImpl.swift | head -10`
Expected: Shows the enum declaration and usage across 7 operations.

- [ ] **Step 5: Verify BlueyError.timeout exists**

Run: `grep "timeout" bluey_ios/ios/Classes/BlueyError.swift`
Expected: Shows `case timeout` and "Operation timed out".

- [ ] **Step 6: Run bluey core tests for regression check**

Run: `cd bluey && flutter test`
Expected: All 450 tests pass.
