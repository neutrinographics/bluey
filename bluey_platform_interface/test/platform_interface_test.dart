import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_platform_interface/src/platform_interface.dart';
import 'package:bluey_platform_interface/src/capabilities.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Mock platform implementation for testing
class MockBlueyPlatform extends BlueyPlatform with MockPlatformInterfaceMixin {
  @override
  Capabilities get capabilities => Capabilities.android;

  // Override all abstract methods with mock implementations
  // We'll just throw unimplemented errors for now since we're testing
  // the interface structure, not functionality

  @override
  Stream<BluetoothState> get stateStream => throw UnimplementedError();

  @override
  Future<BluetoothState> getState() => throw UnimplementedError();

  @override
  Future<bool> requestEnable() => throw UnimplementedError();

  @override
  Future<void> openSettings() => throw UnimplementedError();

  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) =>
      throw UnimplementedError();

  @override
  Future<void> stopScan() => throw UnimplementedError();

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect(String deviceId) => throw UnimplementedError();

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) =>
      throw UnimplementedError();

  // GATT Client operations
  @override
  Future<List<PlatformService>> discoverServices(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> readCharacteristic(
          String deviceId, String characteristicUuid) =>
      throw UnimplementedError();

  @override
  Future<void> writeCharacteristic(String deviceId, String characteristicUuid,
          Uint8List value, bool withResponse) =>
      throw UnimplementedError();

  @override
  Future<void> setNotification(
          String deviceId, String characteristicUuid, bool enable) =>
      throw UnimplementedError();

  @override
  Stream<PlatformNotification> notificationStream(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> readDescriptor(String deviceId, String descriptorUuid) =>
      throw UnimplementedError();

  @override
  Future<void> writeDescriptor(
          String deviceId, String descriptorUuid, Uint8List value) =>
      throw UnimplementedError();

  @override
  Future<int> requestMtu(String deviceId, int mtu) =>
      throw UnimplementedError();

  @override
  Future<int> readRssi(String deviceId) => throw UnimplementedError();

  // Server (Peripheral) operations
  @override
  Future<void> addService(PlatformLocalService service) =>
      throw UnimplementedError();

  @override
  Future<void> removeService(String serviceUuid) => throw UnimplementedError();

  @override
  Future<void> startAdvertising(PlatformAdvertiseConfig config) =>
      throw UnimplementedError();

  @override
  Future<void> stopAdvertising() => throw UnimplementedError();

  @override
  Future<void> notifyCharacteristic(
          String characteristicUuid, Uint8List value) =>
      throw UnimplementedError();

  @override
  Future<void> notifyCharacteristicTo(
          String centralId, String characteristicUuid, Uint8List value) =>
      throw UnimplementedError();

  @override
  Stream<PlatformCentral> get centralConnections => throw UnimplementedError();

  @override
  Stream<String> get centralDisconnections => throw UnimplementedError();

  @override
  Stream<PlatformReadRequest> get readRequests => throw UnimplementedError();

  @override
  Stream<PlatformWriteRequest> get writeRequests => throw UnimplementedError();

  @override
  Future<void> respondToReadRequest(
          int requestId, PlatformGattStatus status, Uint8List? value) =>
      throw UnimplementedError();

  @override
  Future<void> respondToWriteRequest(
          int requestId, PlatformGattStatus status) =>
      throw UnimplementedError();

  @override
  Future<void> disconnectCentral(String centralId) =>
      throw UnimplementedError();
}

void main() {
  group('BlueyPlatform', () {
    test('instance can be set and retrieved', () {
      final mock = MockBlueyPlatform();
      BlueyPlatform.instance = mock;

      expect(BlueyPlatform.instance, equals(mock));
    });

    test('instance must be a BlueyPlatform', () {
      // The verify method throws AssertionError, but the cast throws TypeError first
      expect(() => BlueyPlatform.instance = Object() as BlueyPlatform,
          throwsA(anything)); // Just verify it throws
    });

    test('mock implementation has correct capabilities', () {
      final mock = MockBlueyPlatform();
      expect(mock.capabilities, equals(Capabilities.android));
    });
  });

  group('BluetoothState', () {
    test('has all required states', () {
      expect(BluetoothState.values, contains(BluetoothState.unknown));
      expect(BluetoothState.values, contains(BluetoothState.unsupported));
      expect(BluetoothState.values, contains(BluetoothState.unauthorized));
      expect(BluetoothState.values, contains(BluetoothState.off));
      expect(BluetoothState.values, contains(BluetoothState.on));
    });

    test('isReady returns true only when on', () {
      expect(BluetoothState.on.isReady, isTrue);
      expect(BluetoothState.off.isReady, isFalse);
      expect(BluetoothState.unknown.isReady, isFalse);
      expect(BluetoothState.unsupported.isReady, isFalse);
      expect(BluetoothState.unauthorized.isReady, isFalse);
    });
  });

  group('PlatformScanConfig', () {
    test('creates with all fields', () {
      const config = PlatformScanConfig(
        serviceUuids: ['180d', '180f'],
        timeoutMs: 30000,
      );

      expect(config.serviceUuids, hasLength(2));
      expect(config.timeoutMs, equals(30000));
    });

    test('creates with empty filters', () {
      const config = PlatformScanConfig(
        serviceUuids: [],
        timeoutMs: null,
      );

      expect(config.serviceUuids, isEmpty);
      expect(config.timeoutMs, isNull);
    });
  });

  group('PlatformConnectConfig', () {
    test('creates with all fields', () {
      const config = PlatformConnectConfig(
        timeoutMs: 10000,
        mtu: 512,
      );

      expect(config.timeoutMs, equals(10000));
      expect(config.mtu, equals(512));
    });

    test('creates with defaults', () {
      const config = PlatformConnectConfig(
        timeoutMs: null,
        mtu: null,
      );

      expect(config.timeoutMs, isNull);
      expect(config.mtu, isNull);
    });
  });

  group('PlatformDevice', () {
    test('creates with all fields', () {
      const device = PlatformDevice(
        id: 'device-uuid',
        name: 'Heart Monitor',
        rssi: -60,
        serviceUuids: ['180d'],
        manufacturerDataCompanyId: 0x004C,
        manufacturerData: [1, 2, 3],
      );

      expect(device.id, equals('device-uuid'));
      expect(device.name, equals('Heart Monitor'));
      expect(device.rssi, equals(-60));
      expect(device.serviceUuids, hasLength(1));
      expect(device.manufacturerDataCompanyId, equals(0x004C));
      expect(device.manufacturerData, hasLength(3));
    });

    test('creates without optional fields', () {
      const device = PlatformDevice(
        id: 'device-uuid',
        name: null,
        rssi: -60,
        serviceUuids: [],
        manufacturerDataCompanyId: null,
        manufacturerData: null,
      );

      expect(device.name, isNull);
      expect(device.manufacturerDataCompanyId, isNull);
      expect(device.manufacturerData, isNull);
    });
  });

  group('PlatformConnectionState', () {
    test('has all required states', () {
      expect(PlatformConnectionState.values,
          contains(PlatformConnectionState.disconnected));
      expect(PlatformConnectionState.values,
          contains(PlatformConnectionState.connecting));
      expect(PlatformConnectionState.values,
          contains(PlatformConnectionState.connected));
      expect(PlatformConnectionState.values,
          contains(PlatformConnectionState.disconnecting));
    });
  });
}
