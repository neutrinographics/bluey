import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  group('State Machine', () {
    group('Bluetooth State Transitions', () {
      test('transitions through all Bluetooth states', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final states = <BluetoothState>[];
        final subscription = bluey.stateStream.listen(states.add);

        // Start unknown
        fakePlatform.setBluetoothState(platform.BluetoothState.unknown);
        await Future.delayed(Duration.zero);

        // Transition to off
        fakePlatform.setBluetoothState(platform.BluetoothState.off);
        await Future.delayed(Duration.zero);

        // Transition to on
        fakePlatform.setBluetoothState(platform.BluetoothState.on);
        await Future.delayed(Duration.zero);

        // Transition to unauthorized
        fakePlatform.setBluetoothState(platform.BluetoothState.unauthorized);
        await Future.delayed(Duration.zero);

        expect(states, hasLength(4));
        expect(states[0], equals(BluetoothState.unknown));
        expect(states[1], equals(BluetoothState.off));
        expect(states[2], equals(BluetoothState.on));
        expect(states[3], equals(BluetoothState.unauthorized));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('handles rapid state changes', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final states = <BluetoothState>[];
        final subscription = bluey.stateStream.listen(states.add);

        // Rapid toggling
        for (var i = 0; i < 10; i++) {
          fakePlatform.setBluetoothState(
            i.isEven ? platform.BluetoothState.on : platform.BluetoothState.off,
          );
        }

        await Future.delayed(Duration.zero);

        expect(states, hasLength(10));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('state getter reflects current state', () async {
        final bluey = Bluey(platformOverride: fakePlatform);

        fakePlatform.setBluetoothState(platform.BluetoothState.on);
        expect(await bluey.state, equals(BluetoothState.on));

        fakePlatform.setBluetoothState(platform.BluetoothState.off);
        expect(await bluey.state, equals(BluetoothState.off));

        await bluey.dispose();
      });
    });

    group('Connection State Transitions', () {
      test('transitions connected -> disconnected', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey(platformOverride: fakePlatform);
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        final states = <ConnectionState>[];
        final subscription = connection.stateChanges.listen(states.add);

        expect(connection.state, equals(ConnectionState.connected));

        await connection.disconnect();

        await Future.delayed(Duration.zero);

        expect(states, contains(ConnectionState.disconnected));
        expect(connection.state, equals(ConnectionState.disconnected));

        await subscription.cancel();
        await bluey.dispose();
      });

      test(
        'transitions to disconnected on server-initiated disconnect',
        () async {
          fakePlatform.simulatePeripheral(
            id: 'AA:BB:CC:DD:EE:01',
            name: 'Test Device',
          );

          final bluey = Bluey(platformOverride: fakePlatform);
          final device = await bluey.scan().first;
          final connection = await bluey.connect(device);

          final states = <ConnectionState>[];
          final subscription = connection.stateChanges.listen(states.add);

          // Server disconnects
          fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');

          await Future.delayed(Duration.zero);

          expect(states, contains(ConnectionState.disconnected));

          await subscription.cancel();
          await bluey.dispose();
        },
      );

      test('maintains connected state during operations', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: true,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                ),
              ],
              includedServices: [],
            ),
          ],
          characteristicValues: {
            '00002a37-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x00]),
          },
        );

        final bluey = Bluey(platformOverride: fakePlatform);
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Perform operations
        await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
        );
        await fakePlatform.writeCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
          Uint8List.fromList([0x01]),
          true,
        );

        // State should still be connected
        expect(connection.state, equals(ConnectionState.connected));

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Server State Transitions', () {
      test('transitions idle -> advertising -> connected', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        // Initially not advertising
        expect(fakePlatform.isAdvertising, isFalse);

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        // Start advertising
        await server.startAdvertising(name: 'Test Server');
        expect(fakePlatform.isAdvertising, isTrue);

        // Central connects
        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        expect(fakePlatform.connectedCentralIds, contains('central-1'));

        await server.dispose();
        await bluey.dispose();
      });

      test('transitions advertising -> stopped', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');
        expect(fakePlatform.isAdvertising, isTrue);

        await server.stopAdvertising();
        expect(fakePlatform.isAdvertising, isFalse);

        await server.dispose();
        await bluey.dispose();
      });

      test('handles central disconnect -> reconnect', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        // Central connects
        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        expect(fakePlatform.connectedCentralIds, hasLength(1));

        // Central disconnects
        fakePlatform.simulateCentralDisconnection('central-1');
        expect(fakePlatform.connectedCentralIds, isEmpty);

        // Central reconnects
        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        expect(fakePlatform.connectedCentralIds, hasLength(1));

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Double Call Scenarios', () {
      test('double disconnect is safe (idempotent)', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey(platformOverride: fakePlatform);
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // First disconnect succeeds
        await connection.disconnect();
        expect(connection.state, equals(ConnectionState.disconnected));

        // Second disconnect is safe - no exception
        await connection.disconnect();
        expect(connection.state, equals(ConnectionState.disconnected));

        await bluey.dispose();
      });

      test('can restart advertising after stopping', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        // Start advertising
        await server.startAdvertising(name: 'Test Server');
        expect(fakePlatform.isAdvertising, isTrue);

        // Stop
        await server.stopAdvertising();
        expect(fakePlatform.isAdvertising, isFalse);

        // Restart
        await server.startAdvertising(name: 'Test Server 2');
        expect(fakePlatform.isAdvertising, isTrue);

        await server.dispose();
        await bluey.dispose();
      });

      test('stop advertising when not advertising is safe', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        // Not advertising yet - stop should be safe
        expect(fakePlatform.isAdvertising, isFalse);
        await server.stopAdvertising();
        expect(fakePlatform.isAdvertising, isFalse);

        await server.dispose();
        await bluey.dispose();
      });

      test('double dispose is safe', () async {
        final bluey = Bluey(platformOverride: fakePlatform);

        // Double dispose should not throw
        await bluey.dispose();
        await bluey.dispose();
      });

      test('server dispose cleans up advertising', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');
        expect(fakePlatform.isAdvertising, isTrue);

        // Dispose should stop advertising
        await server.dispose();
        expect(fakePlatform.isAdvertising, isFalse);

        await bluey.dispose();
      });
    });

    group('State Consistency', () {
      test('scanning state is consistent across operations', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey(platformOverride: fakePlatform);

        // Start scan
        final devices = <Device>[];
        final subscription = bluey.scan().listen(devices.add);

        await Future.delayed(Duration.zero);

        // Cancel scan
        await subscription.cancel();

        // Device should still be in the found list
        expect(devices, hasLength(1));

        // Can start another scan
        final devices2 = <Device>[];
        final subscription2 = bluey.scan().listen(devices2.add);
        await Future.delayed(Duration.zero);
        await subscription2.cancel();

        expect(devices2, hasLength(1));

        await bluey.dispose();
      });

      test('connection state survives service discovery', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
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

        final bluey = Bluey(platformOverride: fakePlatform);
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Trigger service discovery
        final services = await connection.services;

        // Connection should still be valid
        expect(connection.state, equals(ConnectionState.connected));
        expect(services, hasLength(1));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('MTU change maintains connection state', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey(platformOverride: fakePlatform);
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Request MTU change
        final newMtu = await connection.requestMtu(512);

        // Connection should still be valid
        expect(connection.state, equals(ConnectionState.connected));
        expect(newMtu, equals(512));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('server state survives service changes', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        // Add service
        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');
        expect(fakePlatform.isAdvertising, isTrue);

        // Add another service
        await server.addService(
          LocalService(
            uuid: UUID('0000180f-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        // Still advertising
        expect(fakePlatform.isAdvertising, isTrue);
        expect(fakePlatform.localServices, hasLength(2));

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Recovery Scenarios', () {
      test('recovers from Bluetooth turning off and on', () async {
        final bluey = Bluey(platformOverride: fakePlatform);

        // Start with Bluetooth on
        fakePlatform.setBluetoothState(platform.BluetoothState.on);
        expect(await bluey.state, equals(BluetoothState.on));

        // Turn off
        fakePlatform.setBluetoothState(platform.BluetoothState.off);
        expect(await bluey.state, equals(BluetoothState.off));

        // Turn back on
        fakePlatform.setBluetoothState(platform.BluetoothState.on);
        expect(await bluey.state, equals(BluetoothState.on));

        // Should be able to scan again
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final device = await bluey.scan().first;
        expect(device.name, equals('Test Device'));

        await bluey.dispose();
      });

      test('reconnects after unexpected disconnection', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey(platformOverride: fakePlatform);
        final device = await bluey.scan().first;

        // Connect
        final connection1 = await bluey.connect(device);
        expect(connection1.state, equals(ConnectionState.connected));

        // Unexpected disconnection
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');
        await Future.delayed(Duration.zero);
        expect(connection1.state, equals(ConnectionState.disconnected));

        // Reconnect
        final connection2 = await bluey.connect(device);
        expect(connection2.state, equals(ConnectionState.connected));

        await connection2.disconnect();
        await bluey.dispose();
      });

      test('server recovers after all centrals disconnect', () async {
        final bluey = Bluey(platformOverride: fakePlatform);
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        // Connect some centrals
        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        fakePlatform.simulateCentralConnection(centralId: 'central-2');
        expect(fakePlatform.connectedCentralIds, hasLength(2));

        // All centrals disconnect
        fakePlatform.simulateCentralDisconnection('central-1');
        fakePlatform.simulateCentralDisconnection('central-2');
        expect(fakePlatform.connectedCentralIds, isEmpty);

        // Should still be advertising
        expect(fakePlatform.isAdvertising, isTrue);

        // New central can connect
        fakePlatform.simulateCentralConnection(centralId: 'central-3');
        expect(fakePlatform.connectedCentralIds, contains('central-3'));

        await server.dispose();
        await bluey.dispose();
      });
    });
  });
}
