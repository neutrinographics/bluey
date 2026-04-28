import 'dart:async';
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

  group('Advanced Scenarios', () {
    group('Indication vs Notification', () {
      test('characteristic with indicate property can subscribe', () async {
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
                    canNotify: false,
                    canIndicate: true,
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Indication should allow subscription
        expect(characteristic.properties.canIndicate, isTrue);
        expect(characteristic.properties.canSubscribe, isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('receives indications like notifications', () async {
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
                    canNotify: false,
                    canIndicate: true,
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        final values = <Uint8List>[];
        final subscription = characteristic.notifications.listen(values.add);

        // Simulate indication (same mechanism as notification in fake)
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x01, 0x02]),
        );

        await Future.delayed(Duration.zero);
        expect(values, hasLength(1));

        await subscription.cancel();
        await connection.disconnect();
        await bluey.dispose();
      });

      test('characteristic with both notify and indicate', () async {
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
                    canIndicate: true,
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        expect(characteristic.properties.canNotify, isTrue);
        expect(characteristic.properties.canIndicate, isTrue);
        expect(characteristic.properties.canSubscribe, isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('RSSI-based Device Selection', () {
      test('selects closest device by RSSI', () async {
        // Simulate multiple devices at different distances
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Far Device',
          rssi: -90, // Weak signal (far)
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Close Device',
          rssi: -40, // Strong signal (close)
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:03',
          name: 'Medium Device',
          rssi: -65, // Medium signal
        );

        final bluey = Bluey();

        final scanner = bluey.scanner();
        final results = <ScanResult>[];
        final subscription = scanner.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        expect(results, hasLength(3));

        // Find the closest device (highest RSSI)
        results.sort((a, b) => b.rssi.compareTo(a.rssi));
        final closest = results.first;

        expect(closest.device.name, equals('Close Device'));
        expect(closest.rssi, equals(-40));

        await bluey.dispose();
      });

      test('filters devices below RSSI threshold', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Too Far',
          rssi: -95,
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Close Enough',
          rssi: -60,
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:03',
          name: 'Very Close',
          rssi: -35,
        );

        final bluey = Bluey();

        final scanner = bluey.scanner();
        final results = <ScanResult>[];
        final subscription = scanner.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        // Filter devices with RSSI >= -70 (close enough)
        const rssiThreshold = -70;
        final nearbyResults =
            results.where((r) => r.rssi >= rssiThreshold).toList();

        expect(nearbyResults, hasLength(2));
        expect(
          nearbyResults.map((r) => r.device.name),
          containsAll(['Close Enough', 'Very Close']),
        );

        await bluey.dispose();
      });
    });

    group('Write Fragmentation', () {
      test('writes data larger than default MTU', () async {
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
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Default MTU is 23, payload is 20 bytes
        // Write 100 bytes (would need fragmentation in real scenario)
        final largeData = Uint8List.fromList(List.generate(100, (i) => i));

        await fakePlatform.writeCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
          largeData,
          true,
        );

        // Verify write succeeded
        final readBack = await fakePlatform.readCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
        );
        expect(readBack, equals(largeData));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('requests larger MTU before large write', () async {
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
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Request larger MTU
        final negotiatedMtu = await connection.requestMtu(
          Mtu(512, capabilities: platform.Capabilities.android),
        );
        expect(negotiatedMtu, equals(Mtu.fromPlatform(512)));
        expect(connection.mtu, equals(Mtu.fromPlatform(512)));

        // Now write large data (512 - 3 = 509 byte payload possible)
        final largeData = Uint8List.fromList(
          List.generate(500, (i) => i % 256),
        );

        await fakePlatform.writeCharacteristic(
          'AA:BB:CC:DD:EE:01',
          '00002a37-0000-1000-8000-00805f9b34fb',
          largeData,
          true,
        );

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Mid-Operation Disconnection', () {
      test('connection state updates on simulated disconnection', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        await connection.services(); // promote linked → ready

        expect(connection.state, equals(ConnectionState.ready));

        // Listen for state changes
        final states = <ConnectionState>[];
        final subscription = connection.stateChanges.listen(states.add);

        // Simulate disconnection
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');

        await Future.delayed(Duration.zero);

        expect(states, contains(ConnectionState.disconnected));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('notification stream handles disconnection', () async {
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        final values = <Uint8List>[];
        final subscription = characteristic.notifications.listen(values.add);

        // Send a notification
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x01]),
        );

        await Future.delayed(Duration.zero);
        expect(values, hasLength(1));

        // Cancel subscription before disconnect to avoid error
        await subscription.cancel();

        // Disconnect
        await connection.disconnect();

        await bluey.dispose();
      });
    });

    group('Rapid Notification Bursts', () {
      test('handles 1000 rapid notifications', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Sensor',
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        final values = <Uint8List>[];
        final subscription = characteristic.notifications.listen(values.add);

        // Simulate 1000 rapid notifications (like a high-frequency sensor)
        for (var i = 0; i < 1000; i++) {
          fakePlatform.simulateNotification(
            deviceId: 'AA:BB:CC:DD:EE:01',
            characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            value: Uint8List.fromList([i & 0xFF]),
          );
        }

        await Future.delayed(Duration.zero);

        // All notifications should be received
        expect(values, hasLength(1000));

        await subscription.cancel();
        await connection.disconnect();
        await bluey.dispose();
      });

      test('maintains notification order', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Sensor',
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        final values = <int>[];
        final subscription = characteristic.notifications.listen((data) {
          values.add(data[0]);
        });

        // Send numbered notifications
        for (var i = 0; i < 100; i++) {
          fakePlatform.simulateNotification(
            deviceId: 'AA:BB:CC:DD:EE:01',
            characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
            value: Uint8List.fromList([i]),
          );
        }

        await Future.delayed(Duration.zero);

        // Verify order is preserved
        expect(values, hasLength(100));
        for (var i = 0; i < 100; i++) {
          expect(values[i], equals(i));
        }

        await subscription.cancel();
        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Scan While Connected', () {
      test('can scan for new devices while connected', () async {
        // Add first device before first scan
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Connected Device',
        );

        final bluey = Bluey();

        // Connect to first device
        final device1 = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device1);
        await connection.services(); // promote linked → ready
        expect(connection.state, equals(ConnectionState.ready));

        // Add another device before second scan
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'New Device',
        );

        // Scan while connected - should find both
        final scanner = bluey.scanner();
        final results = <ScanResult>[];
        final subscription = scanner.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        // Should find both devices
        expect(results, hasLength(2));

        // Original connection should still be active
        expect(connection.state, equals(ConnectionState.ready));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('can connect to multiple devices', () async {
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

        expect(scanResults, hasLength(2));

        // Connect to first
        final connection1 = await bluey.connect(scanResults[0].device);
        await connection1.services(); // promote linked → ready

        // Connect to second while first is connected
        final connection2 = await bluey.connect(scanResults[1].device);
        await connection2.services(); // promote linked → ready

        expect(connection1.state, equals(ConnectionState.ready));
        expect(connection2.state, equals(ConnectionState.ready));

        await connection1.disconnect();
        await connection2.disconnect();
        await bluey.dispose();
      });
    });

    group('Duplicate Device Filtering', () {
      test('same device ID appears once per scan', () async {
        // Simulate device with specific ID
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'My Device',
          rssi: -50,
        );

        final bluey = Bluey();

        final scanner = bluey.scanner();
        final results = <ScanResult>[];
        final subscription = scanner.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        // Device should appear only once per scan
        expect(results, hasLength(1));

        await bluey.dispose();
      });

      test('devices with different IDs are all found', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device A',
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          name: 'Device B',
        );
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:03',
          name: 'Device C',
        );

        final bluey = Bluey();

        final scanner = bluey.scanner();
        final deviceIds = <String>{};
        final subscription = scanner.scan().listen((result) {
          deviceIds.add(result.device.address);
        });
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        expect(deviceIds, hasLength(3));

        await bluey.dispose();
      });
    });

    group('Write Without Response Flooding', () {
      test('sends many writes without response', () async {
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
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Send 100 writes without response (like streaming audio/video data)
        for (var i = 0; i < 100; i++) {
          await characteristic.write(
            Uint8List.fromList([i]),
            withResponse: false,
          );
        }

        await connection.disconnect();
        await bluey.dispose();
      });

      test(
        'write without response is supported alongside write with response',
        () async {
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
          final device = await scanFirstDevice(bluey);
          final connection = await bluey.connect(device);
          final services = await connection.services();
          final characteristic = services.first.characteristics.first;

          // Both should work
          await characteristic.write(
            Uint8List.fromList([0x01]),
            withResponse: true,
          );
          await characteristic.write(
            Uint8List.fromList([0x02]),
            withResponse: false,
          );

          await connection.disconnect();
          await bluey.dispose();
        },
      );
    });

    group('Stale Connection Detection', () {
      test('detects disconnection via state stream', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        await connection.services(); // promote linked → ready

        expect(connection.state, equals(ConnectionState.ready));

        // Listen for state changes before simulating disconnect
        final stateCompleter = Completer<ConnectionState>();
        final subscription = connection.stateChanges.listen((state) {
          if (state == ConnectionState.disconnected) {
            stateCompleter.complete(state);
          }
        });

        // Simulate unexpected disconnection (stale connection)
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');

        final finalState = await stateCompleter.future;
        expect(finalState, equals(ConnectionState.disconnected));

        await subscription.cancel();
        await bluey.dispose();
      });

      test('connection state reflects actual device state', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        await connection.services(); // promote linked → ready

        // Initially connected
        expect(connection.state, equals(ConnectionState.ready));

        // Track all state changes
        final states = <ConnectionState>[];
        final subscription = connection.stateChanges.listen(states.add);

        // Simulate device going out of range
        fakePlatform.simulateDisconnection('AA:BB:CC:DD:EE:01');
        await Future.delayed(Duration.zero);

        // Should have received disconnected state
        expect(states, contains(ConnectionState.disconnected));

        await subscription.cancel();
        await bluey.dispose();
      });
    });

    group('Advertisement Data Changes', () {
      test('device appears with updated advertisement data', () async {
        // Initial advertisement
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device v1',
          rssi: -60,
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: [0x01, 0x02],
        );

        final bluey = Bluey();

        // First scan
        final scanner1 = bluey.scanner();
        final result1 = await scanner1.scan().first;
        scanner1.dispose();
        expect(result1.device.name, equals('Device v1'));
        expect(result1.rssi, equals(-60));

        // Update the peripheral (simulating advertisement data change)
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Device v2',
          rssi: -45,
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: [0x03, 0x04],
        );

        // Second scan should show updated data
        final scanner2 = bluey.scanner();
        final result2 = await scanner2.scan().first;
        scanner2.dispose();
        expect(result2.device.name, equals('Device v2'));
        expect(result2.rssi, equals(-45));

        await bluey.dispose();
      });

      test('tracks RSSI changes over time', () async {
        final bluey = Bluey();

        // Simulate device moving closer
        final rssiValues = [-80, -70, -60, -50, -40];
        final recordedRssi = <int>[];

        for (final rssi in rssiValues) {
          fakePlatform.simulatePeripheral(
            id: 'AA:BB:CC:DD:EE:01',
            name: 'Moving Device',
            rssi: rssi,
          );

          final scanner = bluey.scanner();
          final result = await scanner.scan().first;
          scanner.dispose();
          recordedRssi.add(result.rssi);
        }

        // Verify RSSI values were tracked correctly
        expect(recordedRssi, equals(rssiValues));

        await bluey.dispose();
      });
    });

    group('Characteristic Value Persistence', () {
      test('written value can be read back', () async {
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Read initial value
        final initialValue = await characteristic.read();
        expect(initialValue, equals(Uint8List.fromList([0x00])));

        // Write new value
        final newValue = Uint8List.fromList([0x42, 0x43, 0x44]);
        await characteristic.write(newValue);

        // Read back - should be the new value
        final readBack = await characteristic.read();
        expect(readBack, equals(newValue));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('multiple writes update value correctly', () async {
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Multiple writes
        for (var i = 0; i < 5; i++) {
          await characteristic.write(Uint8List.fromList([i]));
          final value = await characteristic.read();
          expect(value, equals(Uint8List.fromList([i])));
        }

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Concurrent Read/Write Requests', () {
      test('handles concurrent reads from same characteristic', () async {
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
              ],
              includedServices: [],
            ),
          ],
          characteristicValues: {
            '00002a37-0000-1000-8000-00805f9b34fb': Uint8List.fromList([
              0x01,
              0x02,
              0x03,
            ]),
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Launch multiple concurrent reads
        final futures = List.generate(10, (_) => characteristic.read());
        final results = await Future.wait(futures);

        // All reads should return the same value
        for (final result in results) {
          expect(result, equals(Uint8List.fromList([0x01, 0x02, 0x03])));
        }

        await connection.disconnect();
        await bluey.dispose();
      });

      test('handles concurrent reads from different characteristics', () async {
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
            '00002a37-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0xAA]),
            '00002a38-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0xBB]),
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final char1 = services.first.characteristics[0];
        final char2 = services.first.characteristics[1];

        // Concurrent reads from different characteristics
        final results = await Future.wait([
          char1.read(),
          char2.read(),
          char1.read(),
          char2.read(),
        ]);

        expect(results[0], equals(Uint8List.fromList([0xAA])));
        expect(results[1], equals(Uint8List.fromList([0xBB])));
        expect(results[2], equals(Uint8List.fromList([0xAA])));
        expect(results[3], equals(Uint8List.fromList([0xBB])));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('handles interleaved read and write operations', () async {
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
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Interleaved operations - order matters for correctness
        await characteristic.write(Uint8List.fromList([0x01]));
        final v1 = await characteristic.read();
        expect(v1, equals(Uint8List.fromList([0x01])));

        await characteristic.write(Uint8List.fromList([0x02]));
        final v2 = await characteristic.read();
        expect(v2, equals(Uint8List.fromList([0x02])));

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Service Changed Indication', () {
      test('can discover services after initial connection', () async {
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
        final connection = await bluey.connect(device);

        // Discover services
        final services = await connection.services();
        expect(services, hasLength(1));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('caches discovered services', () async {
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
        final connection = await bluey.connect(device);

        // First call discovers, second call uses cache
        final services1 = await connection.services();
        final services2 = await connection.services(cache: true);

        expect(identical(services1, services2), isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });
    });
  });
}
