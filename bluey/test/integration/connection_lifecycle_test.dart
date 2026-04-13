import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  group('Connection Lifecycle', () {
    group('Client connects to server', () {
      test('discovers device via scan', () async {
        // Arrange: Simulate a peripheral advertising
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'Test Device',
          rssi: -45,
          serviceUuids: [
            '0000180d-0000-1000-8000-00805f9b34fb',
          ], // Heart Rate Service
        );

        final bluey = Bluey();

        // Act: Scan for devices
        final results = <ScanResult>[];
        final subscription = bluey.scan().listen(results.add);

        // Wait for scan to emit
        await Future.delayed(Duration.zero);
        await subscription.cancel();

        // Assert
        expect(results, hasLength(1));
        expect(results.first.device.name, equals('Test Device'));
        expect(results.first.rssi, equals(-45));

        await bluey.dispose();
      });

      test('filters by service UUID during scan', () async {
        // Arrange: Two peripherals, one with matching service
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Heart Rate Monitor',
          serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'], // Heart Rate
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Other Device',
          serviceUuids: ['0000180f-0000-1000-8000-00805f9b34fb'], // Battery
        );

        final bluey = Bluey();

        // Act: Scan filtering for heart rate service
        final results = <ScanResult>[];
        final subscription = bluey
            .scan(services: [UUID('0000180d-0000-1000-8000-00805f9b34fb')])
            .listen(results.add);

        await Future.delayed(Duration.zero);
        await subscription.cancel();

        // Assert: Only heart rate device found
        expect(results, hasLength(1));
        expect(results.first.device.name, equals('Heart Rate Monitor'));

        await bluey.dispose();
      });

      test('connects to discovered device', () async {
        // Arrange
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();

        // Discover device first
        final device = await scanFirstDevice(bluey);

        // Act: Connect
        final connection = await bluey.connect(device);

        // Assert
        expect(connection, isNotNull);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('throws when connecting to non-existent device', () async {
        final bluey = Bluey();

        final fakeDevice = Device(
          id: UUID('00000000-0000-0000-0000-000000000000'),
          address: 'FF:FF:FF:FF:FF:FF',
          name: 'Ghost Device',
        );

        // Act & Assert
        expect(() => bluey.connect(fakeDevice), throwsA(isA<BlueyException>()));

        await bluey.dispose();
      });
    });

    group('Disconnection scenarios', () {
      test('client disconnects gracefully', () async {
        // Arrange
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Act
        await connection.disconnect();

        // Assert: Connection should be disconnected
        expect(connection.state, equals(ConnectionState.disconnected));

        await bluey.dispose();
      });

      test('handles server-initiated disconnection', () async {
        // Arrange
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Act: Server disconnects us
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');

        // Give time for state to propagate
        await Future.delayed(Duration.zero);

        // Assert: We should detect the disconnection
        expect(connection.state, equals(ConnectionState.disconnected));

        await bluey.dispose();
      });
    });

    group('Multiple connections', () {
      test('can connect to multiple devices sequentially', () async {
        // Arrange
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device 1',
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Device 2',
        );

        final bluey = Bluey();

        // Collect all scan results
        final results = <ScanResult>[];
        final subscription = bluey.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();

        // Act: Connect to both
        final connection1 = await bluey.connect(
          results.firstWhere((r) => r.device.name == 'Device 1').device,
        );
        final connection2 = await bluey.connect(
          results.firstWhere((r) => r.device.name == 'Device 2').device,
        );

        // Assert
        expect(connection1, isNotNull);
        expect(connection2, isNotNull);

        await connection1.disconnect();
        await connection2.disconnect();
        await bluey.dispose();
      });
    });

    group('Reconnection', () {
      test('can reconnect after disconnection', () async {
        // Arrange
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);

        // First connection
        final connection1 = await bluey.connect(device);
        await connection1.disconnect();

        // Act: Reconnect
        final connection2 = await bluey.connect(device);

        // Assert
        expect(connection2, isNotNull);

        await connection2.disconnect();
        await bluey.dispose();
      });

      test('can reconnect after server-initiated disconnection', () async {
        // Arrange
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);

        // First connection
        await bluey.connect(device);

        // Server disconnects us
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');
        await Future.delayed(Duration.zero);

        // Act: Reconnect
        final connection2 = await bluey.connect(device);

        // Assert
        expect(connection2, isNotNull);

        await connection2.disconnect();
        await bluey.dispose();
      });
    });

    group('Bluetooth state changes', () {
      test('reports initial Bluetooth state', () async {
        fakePlatform.setBluetoothState(platform.BluetoothState.on);

        final bluey = Bluey();
        final state = await bluey.state;

        expect(state, equals(BluetoothState.on));

        await bluey.dispose();
      });

      test('notifies when Bluetooth turns off', () async {
        fakePlatform.setBluetoothState(platform.BluetoothState.on);

        final bluey = Bluey();
        final states = <BluetoothState>[];
        final subscription = bluey.stateStream.listen(states.add);

        // Act: Turn off Bluetooth
        fakePlatform.setBluetoothState(platform.BluetoothState.off);
        await Future.delayed(Duration.zero);

        // Assert
        expect(states, contains(BluetoothState.off));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('requestEnable turns on Bluetooth when off', () async {
        fakePlatform.setBluetoothState(platform.BluetoothState.off);

        final bluey = Bluey();

        // Act
        final enabled = await bluey.requestEnable();

        // Assert
        expect(enabled, isTrue);
        expect(await bluey.state, equals(BluetoothState.on));

        await bluey.dispose();
      });
    });
  });
}
