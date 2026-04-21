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

  group('Concurrent Operations', () {
    group('Parallel Scans', () {
      test('multiple scan listeners receive same devices', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device 1',
        );

        final bluey = Bluey();

        // Start two concurrent scans via separate scanners
        final scanner1 = bluey.scanner();
        final scanner2 = bluey.scanner();
        final results1 = <ScanResult>[];
        final results2 = <ScanResult>[];

        final subscription1 = scanner1.scan().listen(results1.add);
        final subscription2 = scanner2.scan().listen(results2.add);

        await Future.delayed(Duration.zero);

        await subscription1.cancel();
        await subscription2.cancel();
        scanner1.dispose();
        scanner2.dispose();

        // Both should have found the device
        expect(results1, hasLength(1));
        expect(results2, hasLength(1));

        await bluey.dispose();
      });

      test('scan continues after one listener cancels', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device 1',
        );

        final bluey = Bluey();

        final scanner1 = bluey.scanner();
        final scanner2 = bluey.scanner();
        final results1 = <ScanResult>[];
        final results2 = <ScanResult>[];

        final subscription1 = scanner1.scan().listen(results1.add);
        final subscription2 = scanner2.scan().listen(results2.add);

        await Future.delayed(Duration.zero);

        // Cancel first listener
        await subscription1.cancel();
        scanner1.dispose();

        // Add another device
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Device 2',
        );

        // Need to trigger another scan for the new device
        final scanner3 = bluey.scanner();
        final results3 = <ScanResult>[];
        final subscription3 = scanner3.scan().listen(results3.add);
        await Future.delayed(Duration.zero);

        await subscription2.cancel();
        await subscription3.cancel();
        scanner2.dispose();
        scanner3.dispose();

        // Third listener should find both devices
        expect(results3, hasLength(2));

        await bluey.dispose();
      });
    });

    group('Parallel Connections', () {
      test('connects to multiple devices in parallel', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device 1',
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Device 2',
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:03',
          name: 'Device 3',
        );

        final bluey = Bluey();

        // Discover devices
        final scanner = bluey.scanner();
        final results = <ScanResult>[];
        final subscription = scanner.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        expect(results, hasLength(3));

        // Connect to all three in parallel
        final connectionFutures = results.map((r) => bluey.connect(r.device)).toList();
        final connections = await Future.wait(connectionFutures);

        expect(connections, hasLength(3));
        for (final connection in connections) {
          expect(connection, isNotNull);
        }

        // Disconnect all
        await Future.wait(connections.map((c) => c.disconnect()));

        await bluey.dispose();
      });

      test('handles one connection failing while others succeed', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device 1',
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Device 2',
        );

        final bluey = Bluey();

        // Discover devices
        final scanner = bluey.scanner();
        final scanResults = <ScanResult>[];
        final subscription = scanner.scan().listen(scanResults.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        // Remove one device before connecting (simulate connection failure)
        fakePlatform.removePeripheral('AA:BB:CC:DD:EE:02');

        // Try to connect to both
        final results = await Future.wait(
          scanResults.map((r) async {
            try {
              return await bluey.connect(r.device);
            } catch (e) {
              return null;
            }
          }),
        );

        // One should succeed, one should fail
        final successfulConnections = results.whereType<Connection>().toList();
        expect(successfulConnections, hasLength(1));

        // Disconnect successful connections
        for (final connection in successfulConnections) {
          await connection.disconnect();
        }

        await bluey.dispose();
      });
    });

    group('Parallel Read/Write Operations', () {
      test('reads from multiple characteristics in parallel', () async {
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
                ),
                platform.PlatformCharacteristic(
                  uuid: '00002a38-0000-1000-8000-00805f9b34fb',
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
            '00002a37-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x01]),
            '00002a38-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x02]),
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Read both characteristics in parallel
        final results = await Future.wait([
          fakePlatform.readCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a37-0000-1000-8000-00805f9b34fb',
          ),
          fakePlatform.readCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a38-0000-1000-8000-00805f9b34fb',
          ),
        ]);

        expect(results[0], equals(Uint8List.fromList([0x01])));
        expect(results[1], equals(Uint8List.fromList([0x02])));

        await bluey.dispose();
      });

      test('writes to multiple characteristics in parallel', () async {
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
                platform.PlatformCharacteristic(
                  uuid: '00002a38-0000-1000-8000-00805f9b34fb',
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
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Write to both characteristics in parallel
        await Future.wait([
          fakePlatform.writeCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a37-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0xAA]),
            true,
          ),
          fakePlatform.writeCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a38-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0xBB]),
            true,
          ),
        ]);

        // Verify both writes succeeded
        final value1 = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
        );
        final value2 = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a38-0000-1000-8000-00805f9b34fb',
        );

        expect(value1, equals(Uint8List.fromList([0xAA])));
        expect(value2, equals(Uint8List.fromList([0xBB])));

        await bluey.dispose();
      });

      test('interleaves reads and writes', () async {
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

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Interleave multiple read/write operations
        await Future.wait([
          fakePlatform.readCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a37-0000-1000-8000-00805f9b34fb',
          ),
          fakePlatform.writeCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a37-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0x01]),
            true,
          ),
          fakePlatform.readCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a37-0000-1000-8000-00805f9b34fb',
          ),
          fakePlatform.writeCharacteristic(
            'AA:BB:CC:DD:EE:01',
            '00002a37-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0x02]),
            true,
          ),
        ]);

        // Final value should be the last write
        final finalValue = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
        );
        expect(finalValue, equals(Uint8List.fromList([0x02])));

        await bluey.dispose();
      });
    });

    group('Concurrent Notifications', () {
      test('receives notifications from multiple characteristics', () async {
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
                ),
                platform.PlatformCharacteristic(
                  uuid: '00002a38-0000-1000-8000-00805f9b34fb',
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
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        // Subscribe to notifications
        await fakePlatform.setNotification(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
          true,
        );
        await fakePlatform.setNotification(
          'AA:BB:CC:DD:EE:01',
          '00002a38-0000-1000-8000-00805f9b34fb',
          true,
        );

        final notifications = <platform.PlatformNotification>[];
        final subscription = fakePlatform
            .notificationStream('AA:BB:CC:DD:EE:01')
            .listen(notifications.add);

        // Simulate notifications from both characteristics
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x01]),
        );
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a38-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x02]),
        );

        await Future.delayed(Duration.zero);

        expect(notifications, hasLength(2));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('high-frequency notifications are all received', () async {
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
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        await bluey.connect(device);

        final notifications = <platform.PlatformNotification>[];
        final subscription = fakePlatform
            .notificationStream('AA:BB:CC:DD:EE:01')
            .listen(notifications.add);

        // Simulate 100 rapid notifications
        for (var i = 0; i < 100; i++) {
          fakePlatform.simulateNotification(
            deviceId: 'AA:BB:CC:DD:EE:01',
            characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            value: Uint8List.fromList([i]),
          );
        }

        await Future.delayed(Duration.zero);

        expect(notifications, hasLength(100));

        await subscription.cancel();
        await bluey.dispose();
      });
    });

    group('Server Concurrent Operations', () {
      test('handles multiple centrals connecting simultaneously', () async {
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

        // Multiple centrals connect
        final centrals = <String>[];
        final subscription = fakePlatform.centralConnections.listen((central) {
          centrals.add(central.id);
        });

        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        fakePlatform.simulateCentralConnection(centralId: 'central-2');
        fakePlatform.simulateCentralConnection(centralId: 'central-3');

        await Future.delayed(Duration.zero);

        expect(centrals, hasLength(3));
        expect(fakePlatform.connectedCentralIds, hasLength(3));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test(
        'handles concurrent read requests from different centrals',
        () async {
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
          fakePlatform.simulateCentralConnection(centralId: 'central-2');

          // Set up handler
          final requestsCentralIds = <String>[];
          final subscription = fakePlatform.readRequests.listen((request) {
            requestsCentralIds.add(request.centralId);
            fakePlatform.respondToReadRequest(
              request.requestId,
              platform.PlatformGattStatus.success,
              Uint8List.fromList([0x42]),
            );
          });

          // Both centrals read simultaneously
          final results = await Future.wait([
            fakePlatform.simulateReadRequest(
              centralId: 'central-1',
              characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            ),
            fakePlatform.simulateReadRequest(
              centralId: 'central-2',
              characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            ),
          ]);

          expect(results, hasLength(2));
          expect(results[0], equals(Uint8List.fromList([0x42])));
          expect(results[1], equals(Uint8List.fromList([0x42])));
          expect(requestsCentralIds, containsAll(['central-1', 'central-2']));

          await subscription.cancel();
          await server.dispose();
          await bluey.dispose();
        },
      );

      test('notifies all connected centrals simultaneously', () async {
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

        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        fakePlatform.simulateCentralConnection(centralId: 'central-2');

        // Broadcast notification to all
        await fakePlatform.notifyCharacteristic(
          '00002a37-0000-1000-8000-00805f9b34fb',
          Uint8List.fromList([0x01]),
        );

        // Individual notifications to each
        await Future.wait([
          fakePlatform.notifyCharacteristicTo(
            'central-1',
            '00002a37-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0x02]),
          ),
          fakePlatform.notifyCharacteristicTo(
            'central-2',
            '00002a37-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0x03]),
          ),
        ]);

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Mixed Client/Server Operations', () {
      test('operates as client and server simultaneously', () async {
        // Set up a peripheral to connect to
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Remote Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180f-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a19-0000-1000-8000-00805f9b34fb',
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
            '00002a19-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x64]),
          },
        );

        final bluey = Bluey();

        // Start server
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
        await server.startAdvertising(name: 'My Server');

        // Connect as client to remote device
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Read from remote device (as client)
        final remoteValue = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a19-0000-1000-8000-00805f9b34fb',
        );
        expect(remoteValue, equals(Uint8List.fromList([0x64])));

        // Accept connection as server
        fakePlatform.simulateCentralConnection(centralId: 'central-1');
        expect(fakePlatform.connectedCentralIds, contains('central-1'));

        // Both roles active simultaneously
        expect(connection, isNotNull);
        expect(fakePlatform.isAdvertising, isTrue);

        await connection.disconnect();
        await server.dispose();
        await bluey.dispose();
      });
    });
  });
}
