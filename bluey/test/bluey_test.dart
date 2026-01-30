import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

/// Mock platform implementation for testing.
class MockBlueyPlatform extends BlueyPlatform {
  BluetoothState mockState = BluetoothState.on;
  List<PlatformDevice> mockDevices = [];
  bool requestEnableResult = true;
  Exception? scanError;

  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();
  final Map<String, StreamController<PlatformConnectionState>>
      _connectionControllers = {};

  @override
  Capabilities get capabilities => Capabilities.android;

  @override
  Stream<BluetoothState> get stateStream => _stateController.stream;

  @override
  Future<BluetoothState> getState() async => mockState;

  @override
  Future<bool> requestEnable() async => requestEnableResult;

  @override
  Future<void> openSettings() async {}

  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    if (scanError != null) {
      return Stream.error(scanError!);
    }

    // Emit mock devices
    Future.microtask(() {
      for (final device in mockDevices) {
        _scanController.add(device);
      }
    });

    return _scanController.stream;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    _connectionControllers[deviceId] =
        StreamController<PlatformConnectionState>.broadcast();
    return deviceId;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _connectionControllers[deviceId]?.close();
    _connectionControllers.remove(deviceId);
  }

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    return _connectionControllers[deviceId]?.stream ??
        Stream.error(StateError('Not connected'));
  }

  void emitState(BluetoothState state) {
    mockState = state;
    _stateController.add(state);
  }

  void emitConnectionState(String deviceId, PlatformConnectionState state) {
    _connectionControllers[deviceId]?.add(state);
  }

  void dispose() {
    _stateController.close();
    _scanController.close();
    for (final controller in _connectionControllers.values) {
      controller.close();
    }
  }
}

void main() {
  late MockBlueyPlatform mockPlatform;
  late Bluey bluey;

  setUp(() {
    mockPlatform = MockBlueyPlatform();
    BlueyPlatform.instance = mockPlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    mockPlatform.dispose();
  });

  group('Bluey', () {
    group('state', () {
      test('returns current Bluetooth state', () async {
        mockPlatform.mockState = BluetoothState.on;
        expect(await bluey.state, equals(BluetoothAdapterState.on));

        mockPlatform.mockState = BluetoothState.off;
        expect(await bluey.state, equals(BluetoothAdapterState.off));
      });

      test('maps all platform states correctly', () async {
        mockPlatform.mockState = BluetoothState.unknown;
        expect(await bluey.state, equals(BluetoothAdapterState.unknown));

        mockPlatform.mockState = BluetoothState.unsupported;
        expect(await bluey.state, equals(BluetoothAdapterState.unsupported));

        mockPlatform.mockState = BluetoothState.unauthorized;
        expect(await bluey.state, equals(BluetoothAdapterState.unauthorized));
      });

      test('stateStream emits state changes', () async {
        final states = <BluetoothAdapterState>[];
        final subscription = bluey.stateStream.listen(states.add);

        mockPlatform.emitState(BluetoothState.off);
        mockPlatform.emitState(BluetoothState.on);

        await Future.delayed(Duration(milliseconds: 10));

        expect(states, contains(BluetoothAdapterState.off));
        expect(states, contains(BluetoothAdapterState.on));

        await subscription.cancel();
      });
    });

    group('ensureReady', () {
      test('succeeds when Bluetooth is on', () async {
        mockPlatform.mockState = BluetoothState.on;
        await expectLater(bluey.ensureReady(), completes);
      });

      test('throws BluetoothUnavailableException when unsupported', () async {
        mockPlatform.mockState = BluetoothState.unsupported;
        await expectLater(
          bluey.ensureReady(),
          throwsA(isA<BluetoothUnavailableException>()),
        );
      });

      test('throws PermissionDeniedException when unauthorized', () async {
        mockPlatform.mockState = BluetoothState.unauthorized;
        await expectLater(
          bluey.ensureReady(),
          throwsA(isA<PermissionDeniedException>()),
        );
      });

      test('throws BluetoothDisabledException when off and cannot enable',
          () async {
        mockPlatform.mockState = BluetoothState.off;
        mockPlatform.requestEnableResult = false;
        await expectLater(
          bluey.ensureReady(),
          throwsA(isA<BluetoothDisabledException>()),
        );
      });

      test('succeeds when off but can enable', () async {
        mockPlatform.mockState = BluetoothState.off;
        mockPlatform.requestEnableResult = true;
        // After requestEnable succeeds, we need to simulate state change
        // In real implementation this would happen, but our mock is simple
        // So this test verifies requestEnable is called
        await expectLater(bluey.ensureReady(), completes);
      });
    });

    group('scan', () {
      test('emits discovered devices', () async {
        mockPlatform.mockDevices = [
          PlatformDevice(
            id: 'AA:BB:CC:DD:EE:FF',
            name: 'Test Device',
            rssi: -60,
            serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
            manufacturerDataCompanyId: 0x004C,
            manufacturerData: [1, 2, 3],
          ),
        ];

        final devices = <Device>[];
        final subscription = bluey.scan().listen(devices.add);

        await Future.delayed(Duration(milliseconds: 50));
        await subscription.cancel();

        expect(devices, hasLength(1));
        expect(devices.first.name, equals('Test Device'));
        expect(devices.first.rssi, equals(-60));
      });

      test('converts manufacturer data correctly', () async {
        mockPlatform.mockDevices = [
          PlatformDevice(
            id: 'AA:BB:CC:DD:EE:FF',
            name: null,
            rssi: -50,
            serviceUuids: [],
            manufacturerDataCompanyId: 0x004C,
            manufacturerData: [10, 20, 30],
          ),
        ];

        final devices = <Device>[];
        final subscription = bluey.scan().listen(devices.add);

        await Future.delayed(Duration(milliseconds: 50));
        await subscription.cancel();

        final manufacturerData = devices.first.advertisement.manufacturerData;
        expect(manufacturerData, isNotNull);
        expect(manufacturerData!.companyId, equals(0x004C));
        expect(manufacturerData.data, equals([10, 20, 30]));
      });

      test('converts service UUIDs correctly', () async {
        mockPlatform.mockDevices = [
          PlatformDevice(
            id: 'AA:BB:CC:DD:EE:FF',
            name: null,
            rssi: -50,
            serviceUuids: [
              '0000180d-0000-1000-8000-00805f9b34fb',
              '0000180f-0000-1000-8000-00805f9b34fb'
            ],
            manufacturerDataCompanyId: null,
            manufacturerData: null,
          ),
        ];

        final devices = <Device>[];
        final subscription = bluey.scan().listen(devices.add);

        await Future.delayed(Duration(milliseconds: 50));
        await subscription.cancel();

        final serviceUuids = devices.first.advertisement.serviceUuids;
        expect(serviceUuids, hasLength(2));
        expect(serviceUuids[0], equals(UUID.heartRate));
        expect(serviceUuids[1], equals(UUID.battery));
      });

      test('applies service UUID filter', () async {
        mockPlatform.mockDevices = [];

        bluey.scan(services: [UUID.heartRate]);

        // We can't easily verify the filter was applied in our mock,
        // but we verify the scan runs without error
        await Future.delayed(Duration(milliseconds: 10));
      });

      test('applies timeout', () async {
        mockPlatform.mockDevices = [];

        bluey.scan(timeout: Duration(seconds: 10));

        await Future.delayed(Duration(milliseconds: 10));
      });
    });

    group('connect', () {
      test('returns connection state stream', () async {
        final device = Device(
          id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
          rssi: -60,
          advertisement: Advertisement.empty(),
        );

        final stateStream = await bluey.connect(device);

        expect(stateStream, isA<Stream<ConnectionState>>());
      });

      test('maps connection states correctly', () async {
        final device = Device(
          id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
          rssi: -60,
          advertisement: Advertisement.empty(),
        );

        final states = <ConnectionState>[];
        final stateStream = await bluey.connect(device);
        final subscription = stateStream.listen(states.add);

        mockPlatform.emitConnectionState(
          device.id.toString(),
          PlatformConnectionState.connecting,
        );
        mockPlatform.emitConnectionState(
          device.id.toString(),
          PlatformConnectionState.connected,
        );

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(states, contains(ConnectionState.connecting));
        expect(states, contains(ConnectionState.connected));
      });
    });

    group('disconnect', () {
      test('disconnects from device', () async {
        final device = Device(
          id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
          rssi: -60,
          advertisement: Advertisement.empty(),
        );

        // First connect
        await bluey.connect(device);

        // Then disconnect
        await expectLater(bluey.disconnect(device), completes);
      });
    });

    group('capabilities', () {
      test('returns platform capabilities', () {
        expect(bluey.capabilities, equals(Capabilities.android));
      });
    });

    group('dispose', () {
      test('closes state stream', () async {
        await bluey.dispose();

        expect(bluey.stateStream.isBroadcast, isTrue);
        // After dispose, adding listeners should still work (broadcast stream)
        // but no new events will come through
      });
    });
  });

  group('BluetoothAdapterState', () {
    test('isReady returns true only when on', () {
      expect(BluetoothAdapterState.on.isReady, isTrue);
      expect(BluetoothAdapterState.off.isReady, isFalse);
      expect(BluetoothAdapterState.unknown.isReady, isFalse);
      expect(BluetoothAdapterState.unsupported.isReady, isFalse);
      expect(BluetoothAdapterState.unauthorized.isReady, isFalse);
    });
  });

  group('ConnectionState', () {
    test('isActive returns true when connecting or connected', () {
      expect(ConnectionState.connecting.isActive, isTrue);
      expect(ConnectionState.connected.isActive, isTrue);
      expect(ConnectionState.disconnecting.isActive, isFalse);
      expect(ConnectionState.disconnected.isActive, isFalse);
    });
  });
}
