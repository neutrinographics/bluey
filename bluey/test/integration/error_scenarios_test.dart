import 'dart:typed_data';

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

  group('Error Scenarios', () {
    group('Connection Errors', () {
      test('throws when connecting to unknown device', () async {
        final bluey = Bluey();

        final unknownDevice = Device(
          id: UUID('00000000-0000-0000-0000-000000000001'),
          address: 'FF:FF:FF:FF:FF:FF',
          name: 'Unknown Device',
        );

        expect(
          () => bluey.connect(unknownDevice),
          throwsA(isA<BlueyException>()),
        );

        await bluey.dispose();
      });

      test('throws when reading from disconnected device', () async {
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
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
          characteristicValues: {
            '00002a37-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x01]),
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Disconnect first
        await connection.disconnect();

        // Try to read after disconnect - platform should throw
        expect(
          () => fakePlatform.readCharacteristicByUuid('AA:BB:CC:DD:EE:01', '00002a37-0000-1000-8000-00805f9b34fb', ),
          throwsA(isA<Exception>()),
        );

        await bluey.dispose();
      });

      test('throws when writing to disconnected device', () async {
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
                    canRead: false,
                    canWrite: true,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        await connection.disconnect();

        expect(
          () => fakePlatform.writeCharacteristicByUuid('AA:BB:CC:DD:EE:01', '00002a37-0000-1000-8000-00805f9b34fb', Uint8List.fromList([0x01]), true, ),
          throwsA(isA<Exception>()),
        );

        await bluey.dispose();
      });
    });

    group('Characteristic Errors', () {
      test('throws when reading non-existent characteristic', () async {
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

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Try to read a characteristic that doesn't exist
        expect(
          () => fakePlatform.readCharacteristicByUuid(
            'AA:BB:CC:DD:EE:01',
            '00002a99-0000-1000-8000-00805f9b34fb', // Non-existent
          ),
          throwsA(anyOf(isA<Exception>(), isA<StateError>())),
        );

        await bluey.dispose();
      });

      test('handles empty characteristic value', () async {
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
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
          characteristicValues: {
            '00002a37-0000-1000-8000-00805f9b34fb': Uint8List(0), // Empty
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        final value = await fakePlatform.readCharacteristicByUuid('AA:BB:CC:DD:EE:01', '00002a37-0000-1000-8000-00805f9b34fb', );

        expect(value, isEmpty);

        await bluey.dispose();
      });
    });

    group('Server Errors', () {
      test(
        'throws when simulating central connection without advertising',
        () async {
          // Server is not advertising, so central cannot connect
          expect(
            () =>
                fakePlatform.simulateCentralConnection(centralId: 'central-1'),
            throwsA(isA<StateError>()),
          );
        },
      );

      test('throws when notifying to disconnected central', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [
              HostedCharacteristic.notifiable(
                uuid: UUID('00002a37-0000-1000-8000-00805f9b34fb'),
              ),
            ],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        // Connect a central
        fakePlatform.simulateCentralConnection(centralId: 'central-1');

        // Disconnect the central
        fakePlatform.simulateCentralDisconnection('central-1');

        // Try to notify the disconnected central
        expect(
          () => fakePlatform.notifyCharacteristicToByUuid('central-1', '00002a37-0000-1000-8000-00805f9b34fb', Uint8List.fromList([0x01]), ),
          throwsA(isA<Exception>()),
        );

        await server.dispose();
        await bluey.dispose();
      });

      test(
        'throws when simulating read request from non-connected central',
        () async {
          final bluey = Bluey();
          final server = bluey.server()!;

          await server.addService(
            HostedService(
              uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
              characteristics: [],
            ),
          );

          await server.startAdvertising(name: 'Test Server');

          // Try to simulate a read request without a connected central
          expect(
            () => fakePlatform.simulateReadRequest(
              centralId: 'non-existent-central',
              characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            ),
            throwsA(isA<StateError>()),
          );

          await server.dispose();
          await bluey.dispose();
        },
      );

      test(
        'throws when simulating write request from non-connected central',
        () async {
          final bluey = Bluey();
          final server = bluey.server()!;

          await server.addService(
            HostedService(
              uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
              characteristics: [],
            ),
          );

          await server.startAdvertising(name: 'Test Server');

          expect(
            () => fakePlatform.simulateWriteRequest(
              centralId: 'non-existent-central',
              characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
              value: Uint8List.fromList([0x01]),
            ),
            throwsA(isA<StateError>()),
          );

          await server.dispose();
          await bluey.dispose();
        },
      );
    });

    group('Bluetooth State Errors', () {
      test('handles Bluetooth being unsupported', () async {
        fakePlatform.setBluetoothState(platform.BluetoothState.unsupported);

        final bluey = Bluey();
        final state = await bluey.state;

        expect(state, equals(BluetoothState.unsupported));

        await bluey.dispose();
      });

      test('handles Bluetooth unauthorized state', () async {
        fakePlatform.setBluetoothState(platform.BluetoothState.unauthorized);

        final bluey = Bluey();
        final state = await bluey.state;

        expect(state, equals(BluetoothState.unauthorized));

        await bluey.dispose();
      });

      test('detects when Bluetooth turns off during connection', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Bluetooth turns off - this should trigger disconnection
        fakePlatform.setBluetoothState(platform.BluetoothState.off);

        // The state change should be detectable
        final state = await bluey.state;
        expect(state, equals(BluetoothState.off));

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Stream Errors', () {
      test('notification stream handles disconnection gracefully', () async {
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
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [],
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Set up notification listener
        final notifications = <platform.PlatformNotification>[];
        final subscription = fakePlatform
            .notificationStream('AA:BB:CC:DD:EE:01')
            .listen(notifications.add);

        // Simulate a notification
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x01]),
        );

        await Future.delayed(Duration.zero);
        expect(notifications, hasLength(1));

        // Disconnect - stream should handle this gracefully
        await connection.disconnect();

        await subscription.cancel();
        await bluey.dispose();
      });

      test('connection state stream emits disconnected on error', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        final states = <ConnectionState>[];
        final subscription = connection.stateChanges.listen(states.add);

        // Simulate abrupt disconnection
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');

        await Future.delayed(Duration.zero);

        expect(states, contains(ConnectionState.disconnected));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('state stream continues after Bluetooth state changes', () async {
        final bluey = Bluey();
        final states = <BluetoothState>[];
        final subscription = bluey.stateStream.listen(states.add);

        // Multiple state changes
        fakePlatform.setBluetoothState(platform.BluetoothState.off);
        await Future.delayed(Duration.zero);

        fakePlatform.setBluetoothState(platform.BluetoothState.on);
        await Future.delayed(Duration.zero);

        fakePlatform.setBluetoothState(platform.BluetoothState.off);
        await Future.delayed(Duration.zero);

        expect(states, hasLength(3));
        expect(states[0], equals(BluetoothState.off));
        expect(states[1], equals(BluetoothState.on));
        expect(states[2], equals(BluetoothState.off));

        await subscription.cancel();
        await bluey.dispose();
      });
    });

    group('Request/Response Errors', () {
      test('read request fails with error status', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [
              HostedCharacteristic.readable(
                uuid: UUID('00002a37-0000-1000-8000-00805f9b34fb'),
              ),
            ],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        fakePlatform.simulateCentralConnection(centralId: 'central-1');

        // Set up a listener BEFORE simulating the request
        final subscription = fakePlatform.readRequests.listen((request) {
          // Respond with failure
          fakePlatform.respondToReadRequest(
            request.requestId,
            platform.PlatformGattStatus.readNotPermitted,
            null,
          );
        });

        // Simulate a read request - should fail
        Object? caughtError;
        try {
          await fakePlatform.simulateReadRequest(
            centralId: 'central-1',
            characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          );
        } catch (e) {
          caughtError = e;
        }

        expect(caughtError, isA<Exception>());

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('write request fails with error status', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [
              HostedCharacteristic.writable(
                uuid: UUID('00002a37-0000-1000-8000-00805f9b34fb'),
              ),
            ],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        fakePlatform.simulateCentralConnection(centralId: 'central-1');

        // Set up a listener BEFORE simulating the request
        final subscription = fakePlatform.writeRequests.listen((request) {
          // Respond with failure
          fakePlatform.respondToWriteRequest(
            request.requestId,
            platform.PlatformGattStatus.writeNotPermitted,
          );
        });

        // Simulate a write request - should fail
        Object? caughtError;
        try {
          await fakePlatform.simulateWriteRequest(
            centralId: 'central-1',
            characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            value: Uint8List.fromList([0x01]),
          );
        } catch (e) {
          caughtError = e;
        }

        expect(caughtError, isA<Exception>());

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Edge Cases', () {
      test('handles rapid connect/disconnect cycles', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);

        // Rapid connect/disconnect cycles
        for (var i = 0; i < 5; i++) {
          final connection = await bluey.connect(device);
          await connection.disconnect();
        }

        // Should still work after cycles
        final finalConnection = await bluey.connect(device);
        expect(finalConnection, isNotNull);

        await finalConnection.disconnect();
        await bluey.dispose();
      });

      test('handles multiple scans in sequence', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();

        // Multiple scans in sequence
        for (var i = 0; i < 3; i++) {
          final scanner = bluey.scanner();
          final devices = <ScanResult>[];
          final subscription = scanner.scan().listen(devices.add);
          await Future.delayed(Duration.zero);
          await subscription.cancel();
          scanner.dispose();

          expect(devices, hasLength(1));
        }

        await bluey.dispose();
      });

      test('handles device appearing and disappearing', () async {
        final bluey = Bluey();

        // First scan - no devices
        var scanner = bluey.scanner();
        var devices = <ScanResult>[];
        var subscription = scanner.scan().listen(devices.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();
        expect(devices, isEmpty);

        // Add a device
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        // Second scan - device present
        scanner = bluey.scanner();
        devices = <ScanResult>[];
        subscription = scanner.scan().listen(devices.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();
        expect(devices, hasLength(1));

        // Remove the device
        fakePlatform.removePeripheral('AA:BB:CC:DD:EE:01');

        // Third scan - no devices again
        scanner = bluey.scanner();
        devices = <ScanResult>[];
        subscription = scanner.scan().listen(devices.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();
        expect(devices, isEmpty);

        await bluey.dispose();
      });

      test('handles zero-length writes', () async {
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
                    canRead: false,
                    canWrite: true,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Write empty data
        await fakePlatform.writeCharacteristicByUuid('AA:BB:CC:DD:EE:01', '00002a37-0000-1000-8000-00805f9b34fb', Uint8List(0), true, );

        await bluey.dispose();
      });

      test('handles large data writes', () async {
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
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Write large data (512 bytes)
        final largeData = Uint8List.fromList(
          List.generate(512, (i) => i % 256),
        );
        await fakePlatform.writeCharacteristicByUuid('AA:BB:CC:DD:EE:01', '00002a37-0000-1000-8000-00805f9b34fb', largeData, true, );

        // Verify data was written
        final readBack = await fakePlatform.readCharacteristicByUuid('AA:BB:CC:DD:EE:01', '00002a37-0000-1000-8000-00805f9b34fb', );
        expect(readBack, equals(largeData));

        await bluey.dispose();
      });
    });
  });
}
