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
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  group('Real World Scenarios', () {
    group('Heart Rate Monitor', () {
      const heartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
      const heartRateMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';
      const bodySensorLocationUuid = '00002a38-0000-1000-8000-00805f9b34fb';

      test('discovers and connects to heart rate monitor', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'HR Monitor',
          serviceUuids: [heartRateServiceUuid],
          services: [
            const platform.PlatformService(
              uuid: heartRateServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: heartRateMeasurementUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [],
                ),
                platform.PlatformCharacteristic(
                  uuid: bodySensorLocationUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
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
            bodySensorLocationUuid: Uint8List.fromList([0x01]), // Chest
          },
        );

        final bluey = Bluey();

        // Scan for heart rate monitors only
        final devices = <Device>[];
        final subscription = bluey
            .scan(services: [UUID(heartRateServiceUuid)])
            .listen(devices.add);

        await Future.delayed(Duration.zero);
        await subscription.cancel();

        expect(devices, hasLength(1));
        expect(devices.first.name, equals('HR Monitor'));

        // Connect
        final connection = await bluey.connect(devices.first);
        expect(connection, isNotNull);

        // Discover services
        final services = await connection.services();
        expect(services, hasLength(1));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('reads body sensor location', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'HR Monitor',
          services: [
            const platform.PlatformService(
              uuid: heartRateServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: bodySensorLocationUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
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
            bodySensorLocationUuid: Uint8List.fromList([0x01]), // Chest
          },
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        await bluey.connect(device);

        final location = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          bodySensorLocationUuid,
        );

        // 0x01 = Chest
        expect(location, equals(Uint8List.fromList([0x01])));

        await bluey.dispose();
      });

      test('subscribes to heart rate notifications', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'HR Monitor',
          services: [
            const platform.PlatformService(
              uuid: heartRateServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: heartRateMeasurementUuid,
                  properties: platform.PlatformCharacteristicProperties(
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
          ],
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        await bluey.connect(device);

        // Enable notifications
        await fakePlatform.setNotification(
          'AA:BB:CC:DD:EE:01',
          heartRateMeasurementUuid,
          true,
        );

        final heartRates = <int>[];
        final subscription = fakePlatform
            .notificationStream('AA:BB:CC:DD:EE:01')
            .listen((notification) {
              // Heart rate format: flags (1 byte) + heart rate value
              if (notification.value.isNotEmpty) {
                heartRates.add(notification.value[1]);
              }
            });

        // Simulate heart rate readings
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: heartRateMeasurementUuid,
          value: Uint8List.fromList([0x00, 72]), // 72 bpm
        );
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: heartRateMeasurementUuid,
          value: Uint8List.fromList([0x00, 75]), // 75 bpm
        );
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: heartRateMeasurementUuid,
          value: Uint8List.fromList([0x00, 78]), // 78 bpm
        );

        await Future.delayed(Duration.zero);

        expect(heartRates, equals([72, 75, 78]));

        await subscription.cancel();
        await bluey.dispose();
      });
    });

    group('Firmware Update', () {
      const dfuServiceUuid = '0000fe59-0000-1000-8000-00805f9b34fb';
      const dfuControlPointUuid = '8ec90001-f315-4f60-9fb8-838830daea50';
      const dfuPacketUuid = '8ec90002-f315-4f60-9fb8-838830daea50';

      test('simulates firmware update flow', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'DFU Device',
          serviceUuids: [dfuServiceUuid],
          services: [
            const platform.PlatformService(
              uuid: dfuServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: dfuControlPointUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: true,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [],
                ),
                platform.PlatformCharacteristic(
                  uuid: dfuPacketUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: true,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Request larger MTU for faster transfer
        final mtu = await connection.requestMtu(256);
        expect(mtu, equals(256));

        // Enable notifications on control point
        await fakePlatform.setNotification(
          'AA:BB:CC:DD:EE:01',
          dfuControlPointUuid,
          true,
        );

        // Simulate sending firmware packets
        final firmwareChunks = [
          Uint8List.fromList(List.generate(200, (i) => i % 256)),
          Uint8List.fromList(List.generate(200, (i) => (i + 50) % 256)),
          Uint8List.fromList(List.generate(100, (i) => (i + 100) % 256)),
        ];

        for (final chunk in firmwareChunks) {
          await fakePlatform.writeCharacteristic(
            'AA:BB:CC:DD:EE:01',
            dfuPacketUuid,
            chunk,
            false, // Write without response for speed
          );
        }

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Sensor Polling', () {
      const environmentalServiceUuid = '0000181a-0000-1000-8000-00805f9b34fb';
      const temperatureUuid = '00002a6e-0000-1000-8000-00805f9b34fb';
      const humidityUuid = '00002a6f-0000-1000-8000-00805f9b34fb';

      test('polls multiple sensors periodically', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Env Sensor',
          services: [
            const platform.PlatformService(
              uuid: environmentalServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: temperatureUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [],
                ),
                platform.PlatformCharacteristic(
                  uuid: humidityUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
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
            temperatureUuid: Uint8List.fromList([
              0x00,
              0xC8,
            ]), // 25.0°C (0x00C8 = 200 = 20.0°C in 0.1 units)
            humidityUuid: Uint8List.fromList([
              0x01,
              0xF4,
            ]), // 50.0% (0x01F4 = 500 = 50.0% in 0.1 units)
          },
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        await bluey.connect(device);

        // Poll 3 times
        final readings = <Map<String, Uint8List>>[];

        for (var i = 0; i < 3; i++) {
          final temp = await fakePlatform.readCharacteristic(
            'AA:BB:CC:DD:EE:01',
            temperatureUuid,
          );
          final humidity = await fakePlatform.readCharacteristic(
            'AA:BB:CC:DD:EE:01',
            humidityUuid,
          );
          readings.add({'temp': temp, 'humidity': humidity});
        }

        expect(readings, hasLength(3));
        for (final reading in readings) {
          expect(reading['temp'], isNotNull);
          expect(reading['humidity'], isNotNull);
        }

        await bluey.dispose();
      });
    });

    group('Smart Lock', () {
      const lockServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
      const lockStateUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
      const lockCommandUuid = '0000fff2-0000-1000-8000-00805f9b34fb';

      test('reads lock state and sends unlock command', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Smart Lock',
          services: [
            const platform.PlatformService(
              uuid: lockServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: lockStateUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [],
                ),
                platform.PlatformCharacteristic(
                  uuid: lockCommandUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: false,
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
            lockStateUuid: Uint8List.fromList([0x01]), // 0x01 = Locked
          },
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        await bluey.connect(device);

        // Read current lock state
        var lockState = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          lockStateUuid,
        );
        expect(lockState[0], equals(0x01)); // Locked

        // Send unlock command (0x02 = Unlock)
        await fakePlatform.writeCharacteristic(
          'AA:BB:CC:DD:EE:01',
          lockCommandUuid,
          Uint8List.fromList([0x02]),
          true,
        );

        await bluey.dispose();
      });

      test('subscribes to lock state changes', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Smart Lock',
          services: [
            const platform.PlatformService(
              uuid: lockServiceUuid,
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: lockStateUuid,
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
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
          ],
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        await bluey.connect(device);

        await fakePlatform.setNotification(
          'AA:BB:CC:DD:EE:01',
          lockStateUuid,
          true,
        );

        final stateChanges = <int>[];
        final subscription = fakePlatform
            .notificationStream('AA:BB:CC:DD:EE:01')
            .listen((notification) {
              stateChanges.add(notification.value[0]);
            });

        // Simulate lock state changes
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: lockStateUuid,
          value: Uint8List.fromList([0x00]), // Unlocked
        );
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: lockStateUuid,
          value: Uint8List.fromList([0x01]), // Locked
        );

        await Future.delayed(Duration.zero);

        expect(stateChanges, equals([0x00, 0x01]));

        await subscription.cancel();
        await bluey.dispose();
      });
    });

    group('Peripheral Server', () {
      test('acts as a custom BLE peripheral', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        // Create a custom service
        await server.addService(
          HostedService(
            uuid: UUID('12345678-1234-1234-1234-123456789abc'),
            characteristics: [
              HostedCharacteristic(
                uuid: UUID('12345678-1234-1234-1234-123456789abd'),
                properties: const CharacteristicProperties(
                  canRead: true,
                  canWrite: true,
                ),
                permissions: const [GattPermission.read, GattPermission.write],
              ),
              HostedCharacteristic.notifiable(
                uuid: UUID('12345678-1234-1234-1234-123456789abe'),
              ),
            ],
          ),
        );

        // Start advertising
        await server.startAdvertising(
          name: 'My Custom Device',
          services: [UUID('12345678-1234-1234-1234-123456789abc')],
        );

        expect(fakePlatform.isAdvertising, isTrue);
        // 2 services: the control service (lifecycle) + the consumer's service
        expect(fakePlatform.localServices, hasLength(2));

        // Handle incoming connection
        final centrals = <String>[];
        final centralSubscription = fakePlatform.centralConnections.listen(
          (central) => centrals.add(central.id),
        );

        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        await Future.delayed(Duration.zero);

        expect(centrals, contains('phone-1'));

        await centralSubscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('handles read requests from central', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        const charUuid = '12345678-1234-1234-1234-123456789abd';

        await server.addService(
          HostedService(
            uuid: UUID('12345678-1234-1234-1234-123456789abc'),
            characteristics: [
              HostedCharacteristic.readable(uuid: UUID(charUuid)),
            ],
          ),
        );

        await server.startAdvertising(name: 'Test Server');
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');

        // Handle read requests
        final subscription = fakePlatform.readRequests.listen((request) {
          fakePlatform.respondToReadRequest(
            request.requestId,
            platform.PlatformGattStatus.success,
            Uint8List.fromList([0x42, 0x43, 0x44]), // "BCD"
          );
        });

        // Central reads
        final value = await fakePlatform.simulateReadRequest(
          centralId: 'phone-1',
          characteristicUuid: charUuid,
        );

        expect(value, equals(Uint8List.fromList([0x42, 0x43, 0x44])));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('sends notifications to connected centrals', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        const charUuid = '12345678-1234-1234-1234-123456789abe';

        await server.addService(
          HostedService(
            uuid: UUID('12345678-1234-1234-1234-123456789abc'),
            characteristics: [
              HostedCharacteristic.notifiable(uuid: UUID(charUuid)),
            ],
          ),
        );

        await server.startAdvertising(name: 'Notification Server');

        // Two centrals connect
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');

        // Send notification to all
        await fakePlatform.notifyCharacteristic(
          charUuid,
          Uint8List.fromList([0x01, 0x02, 0x03]),
        );

        // Send notification to specific central
        await fakePlatform.notifyCharacteristicTo(
          'phone-1',
          charUuid,
          Uint8List.fromList([0x04, 0x05]),
        );

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Multi-Device Management', () {
      test('manages connections to multiple devices', () async {
        // Set up 3 different device types
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Heart Rate Monitor',
          serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Thermometer',
          serviceUuids: ['00001809-0000-1000-8000-00805f9b34fb'],
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:03',
          name: 'Blood Pressure',
          serviceUuids: ['00001810-0000-1000-8000-00805f9b34fb'],
        );

        final bluey = Bluey();

        // Discover all devices
        final devices = <Device>[];
        final subscription = bluey.scan().listen(devices.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();

        expect(devices, hasLength(3));

        // Connect to all devices
        final connections = <Connection>[];
        for (final device in devices) {
          final connection = await bluey.connect(device);
          connections.add(connection);
        }

        expect(connections, hasLength(3));

        // All should be connected
        for (final connection in connections) {
          expect(connection.state, equals(ConnectionState.connected));
        }

        // Disconnect one, others should remain connected
        await connections[1].disconnect();
        expect(connections[0].state, equals(ConnectionState.connected));
        expect(connections[1].state, equals(ConnectionState.disconnected));
        expect(connections[2].state, equals(ConnectionState.connected));

        // Disconnect remaining
        await connections[0].disconnect();
        await connections[2].disconnect();

        await bluey.dispose();
      });
    });
  });
}
