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

  group('Data Exchange', () {
    group('Reading characteristics', () {
      test('reads characteristic value', () async {
        // Arrange
        final expectedValue = Uint8List.fromList([0x01, 0x02, 0x03]);
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180a-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a29-0000-1000-8000-00805f9b34fb',
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
            '00002a29-0000-1000-8000-00805f9b34fb': expectedValue,
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Act
        final value = await characteristic.read();

        // Assert
        expect(value, equals(expectedValue));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('reads string value from characteristic', () async {
        // Arrange: Manufacturer name as UTF-8 string
        final manufacturerName = 'Acme Corp';
        final expectedValue = Uint8List.fromList(manufacturerName.codeUnits);

        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180a-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a29-0000-1000-8000-00805f9b34fb',
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
            '00002a29-0000-1000-8000-00805f9b34fb': expectedValue,
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Act
        final value = await characteristic.read();
        final stringValue = String.fromCharCodes(value);

        // Assert
        expect(stringValue, equals(manufacturerName));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('throws when reading non-readable characteristic', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid:
                      '00002a37-0000-1000-8000-00805f9b34fb', // Heart Rate - notify only
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

        // Act & Assert
        expect(
          () => characteristic.read(),
          throwsA(isA<OperationNotSupportedException>()),
        );

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Writing characteristics', () {
      test('writes characteristic value with response', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '00001801-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '0000abcd-0000-1000-8000-00805f9b34fb',
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
            '0000abcd-0000-1000-8000-00805f9b34fb': Uint8List(0),
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Act
        final dataToWrite = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
        await characteristic.write(dataToWrite);

        // Assert: Read back to verify write
        final readValue = await characteristic.read();
        expect(readValue, equals(dataToWrite));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('writes characteristic value without response', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '00001801-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '0000abcd-0000-1000-8000-00805f9b34fb',
                  properties: platform.PlatformCharacteristicProperties(
                    canRead: true,
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
          characteristicValues: {
            '0000abcd-0000-1000-8000-00805f9b34fb': Uint8List(0),
          },
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Act
        final dataToWrite = Uint8List.fromList([0x01, 0x02]);
        await characteristic.write(dataToWrite, withResponse: false);

        // Assert: Write completed without error
        expect(true, isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('throws when writing to non-writable characteristic', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180a-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid:
                      '00002a29-0000-1000-8000-00805f9b34fb', // Manufacturer Name - read only
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
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Act & Assert
        expect(
          () => characteristic.write(Uint8List.fromList([0x01])),
          throwsA(isA<OperationNotSupportedException>()),
        );

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Notifications', () {
      test('subscribes to characteristic notifications', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Heart Rate Monitor',
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

        // Act
        final notifications = <Uint8List>[];
        final subscription = characteristic.notifications.listen(
          notifications.add,
        );

        // Simulate notifications from peripheral
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x00, 72]), // HR = 72 bpm
        );
        fakePlatform.simulateNotification(
          deviceId: 'AA:BB:CC:DD:EE:01',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x00, 75]), // HR = 75 bpm
        );

        await Future.delayed(Duration.zero);

        // Assert
        expect(notifications, hasLength(2));
        expect(notifications[0][1], equals(72));
        expect(notifications[1][1], equals(75));

        await subscription.cancel();
        await connection.disconnect();
        await bluey.dispose();
      });

      test('throws when subscribing to non-notifiable characteristic', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180a-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid:
                      '00002a29-0000-1000-8000-00805f9b34fb', // Read-only characteristic
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
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Act & Assert
        expect(
          () => characteristic.notifications,
          throwsA(isA<OperationNotSupportedException>()),
        );

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('MTU negotiation', () {
      test('requests larger MTU', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Act
        final mtu = await connection.requestMtu(
          Mtu(512, capabilities: platform.Capabilities.android),
        );

        // Assert
        expect(mtu, equals(Mtu.fromPlatform(512)));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('MTU property reflects negotiated value', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Initially default MTU
        expect(connection.mtu, equals(Mtu.fromPlatform(23)));

        // Request larger MTU
        await connection.requestMtu(
          Mtu(256, capabilities: platform.Capabilities.android),
        );

        // Assert MTU property updated
        expect(connection.mtu, equals(Mtu.fromPlatform(256)));

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('RSSI', () {
      test('reads RSSI from connected device', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          rssi: -55,
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);

        // Act
        final rssi = await connection.readRssi();

        // Assert
        expect(rssi, equals(-55));

        await connection.disconnect();
        await bluey.dispose();
      });
    });
  });
}
