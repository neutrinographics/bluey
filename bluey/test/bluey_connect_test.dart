import 'dart:async';
import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bluey.connect', () {
    late MockBlueyPlatform mockPlatform;
    late Bluey bluey;

    setUp(() {
      mockPlatform = MockBlueyPlatform();
      platform.BlueyPlatform.instance = mockPlatform;
      bluey = Bluey();
    });

    tearDown(() async {
      await bluey.dispose();
      mockPlatform.dispose();
    });

    test('returns a Connection object', () async {
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
        rssi: -60,
        advertisement: Advertisement.empty(),
      );

      final connection = await bluey.connect(device);

      expect(connection, isA<Connection>());
      expect(connection.deviceId, equals(device.id));
    });

    test('connection is connected after connect completes', () async {
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
        rssi: -60,
        advertisement: Advertisement.empty(),
      );

      final connection = await bluey.connect(device);

      // Connection is established after connect() completes
      expect(connection.state, equals(ConnectionState.connected));
    });

    test('connection state changes are emitted', () async {
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
        rssi: -60,
        advertisement: Advertisement.empty(),
      );

      final connection = await bluey.connect(device);
      final states = <ConnectionState>[];
      final subscription = connection.stateChanges.listen(states.add);

      mockPlatform.emitConnectionState(
        device.id.toString(),
        platform.PlatformConnectionState.connected,
      );

      await Future.delayed(Duration(milliseconds: 10));
      await subscription.cancel();

      expect(states, contains(ConnectionState.connected));
    });

    test('disconnect closes the connection', () async {
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
        rssi: -60,
        advertisement: Advertisement.empty(),
      );

      final connection = await bluey.connect(device);
      await connection.disconnect();

      expect(connection.state, equals(ConnectionState.disconnected));
    });
  });
}

/// Mock platform for testing
final class MockBlueyPlatform extends platform.BlueyPlatform {
  MockBlueyPlatform() : super.impl();
  platform.BluetoothState mockState = platform.BluetoothState.on;
  final Map<String, StreamController<platform.PlatformConnectionState>>
  _connectionControllers = {};
  final _stateController =
      StreamController<platform.BluetoothState>.broadcast();

  @override
  platform.Capabilities get capabilities => platform.Capabilities.android;

  @override
  Future<void> configure(platform.BlueyConfig config) async {}

  @override
  Stream<platform.BluetoothState> get stateStream => _stateController.stream;

  @override
  Future<platform.BluetoothState> getState() async => mockState;

  @override
  Future<bool> requestEnable() async => true;

  @override
  Future<bool> authorize() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Stream<platform.PlatformDevice> scan(platform.PlatformScanConfig config) =>
      Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Future<String> connect(
    String deviceId,
    platform.PlatformConnectConfig config,
  ) async {
    _connectionControllers[deviceId] =
        StreamController<platform.PlatformConnectionState>.broadcast();
    // Emit connecting state immediately
    _connectionControllers[deviceId]?.add(
      platform.PlatformConnectionState.connecting,
    );
    return deviceId;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _connectionControllers[deviceId]?.add(
      platform.PlatformConnectionState.disconnecting,
    );
    _connectionControllers[deviceId]?.add(
      platform.PlatformConnectionState.disconnected,
    );
    await _connectionControllers[deviceId]?.close();
    _connectionControllers.remove(deviceId);
  }

  @override
  Stream<platform.PlatformConnectionState> connectionStateStream(
    String deviceId,
  ) {
    return _connectionControllers[deviceId]?.stream ??
        Stream.error(StateError('Not connected'));
  }

  void emitConnectionState(
    String deviceId,
    platform.PlatformConnectionState state,
  ) {
    _connectionControllers[deviceId]?.add(state);
  }

  // GATT operations - stub implementations for tests that don't use them
  @override
  Future<List<platform.PlatformService>> discoverServices(
    String deviceId,
  ) async => [];

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async => Uint8List(0);

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {}

  @override
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {}

  @override
  Stream<platform.PlatformNotification> notificationStream(String deviceId) =>
      Stream.empty();

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async => Uint8List(0);

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {}

  @override
  Future<int> requestMtu(String deviceId, int mtu) async => mtu;

  @override
  Future<int> readRssi(String deviceId) async => -60;

  // Bonding operations - stub implementations
  @override
  Future<platform.PlatformBondState> getBondState(String deviceId) async =>
      platform.PlatformBondState.none;

  @override
  Stream<platform.PlatformBondState> bondStateStream(String deviceId) =>
      Stream.empty();

  @override
  Future<void> bond(String deviceId) async {}

  @override
  Future<void> removeBond(String deviceId) async {}

  @override
  Future<List<platform.PlatformDevice>> getBondedDevices() async => [];

  // PHY operations - stub implementations
  @override
  Future<({platform.PlatformPhy tx, platform.PlatformPhy rx})> getPhy(
    String deviceId,
  ) async => (tx: platform.PlatformPhy.le1m, rx: platform.PlatformPhy.le1m);

  @override
  Stream<({platform.PlatformPhy tx, platform.PlatformPhy rx})> phyStream(
    String deviceId,
  ) => Stream.empty();

  @override
  Future<void> requestPhy(
    String deviceId,
    platform.PlatformPhy? txPhy,
    platform.PlatformPhy? rxPhy,
  ) async {}

  // Connection parameters - stub implementations
  @override
  Future<platform.PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async => const platform.PlatformConnectionParameters(
    intervalMs: 30.0,
    latency: 0,
    timeoutMs: 4000,
  );

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    platform.PlatformConnectionParameters params,
  ) async {}

  // Server (Peripheral) operations - stub implementations
  @override
  Future<void> addService(platform.PlatformLocalService service) async {}

  @override
  Future<void> removeService(String serviceUuid) async {}

  @override
  Future<void> startAdvertising(
    platform.PlatformAdvertiseConfig config,
  ) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> notifyCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {}

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {}

  @override
  Future<void> indicateCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {}

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {}

  @override
  Stream<platform.PlatformCentral> get centralConnections => Stream.empty();

  @override
  Stream<String> get centralDisconnections => Stream.empty();

  @override
  Stream<platform.PlatformReadRequest> get readRequests => Stream.empty();

  @override
  Stream<platform.PlatformWriteRequest> get writeRequests => Stream.empty();

  @override
  Future<void> respondToReadRequest(
    int requestId,
    platform.PlatformGattStatus status,
    Uint8List? value,
  ) async {}

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    platform.PlatformGattStatus status,
  ) async {}

  @override
  Future<void> disconnectCentral(String centralId) async {}

  @override
  Future<void> closeServer() async {}

  void dispose() {
    _stateController.close();
    for (final controller in _connectionControllers.values) {
      controller.close();
    }
  }
}
