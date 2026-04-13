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

  group('Descriptor Operations', () {
    // Standard descriptor UUIDs
    const cccdUuid =
        '00002902-0000-1000-8000-00805f9b34fb'; // Client Characteristic Configuration
    const cudUuid =
        '00002901-0000-1000-8000-00805f9b34fb'; // Characteristic User Description
    const cpfUuid =
        '00002904-0000-1000-8000-00805f9b34fb'; // Characteristic Presentation Format

    group('Reading Descriptors', () {
      test('reads CCCD descriptor value', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [platform.PlatformDescriptor(uuid: cccdUuid)],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        expect(characteristic.descriptors, hasLength(1));
        expect(
          characteristic.descriptors.first.uuid.toString().toLowerCase(),
          contains('2902'),
        );

        await connection.disconnect();
        await bluey.dispose();
      });

      test('reads Characteristic User Description', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: [platform.PlatformDescriptor(uuid: cudUuid)],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;
        final descriptor = characteristic.descriptors.first;

        // Read the descriptor
        final value = await descriptor.read();
        expect(value, isA<Uint8List>());

        await connection.disconnect();
        await bluey.dispose();
      });

      test('reads multiple descriptors from same characteristic', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [
                    platform.PlatformDescriptor(uuid: cccdUuid),
                    platform.PlatformDescriptor(uuid: cudUuid),
                    platform.PlatformDescriptor(uuid: cpfUuid),
                  ],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        expect(characteristic.descriptors, hasLength(3));

        // Read all descriptors
        for (final descriptor in characteristic.descriptors) {
          final value = await descriptor.read();
          expect(value, isA<Uint8List>());
        }

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Writing Descriptors', () {
      test('writes to CCCD to enable notifications', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [platform.PlatformDescriptor(uuid: cccdUuid)],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;
        final cccd = characteristic.descriptors.first;

        // Write 0x0001 to enable notifications
        final enableNotifications = Uint8List.fromList([0x01, 0x00]);
        await cccd.write(enableNotifications);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('writes to CCCD to enable indications', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: true,
                  ),
                  descriptors: [platform.PlatformDescriptor(uuid: cccdUuid)],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;
        final cccd = characteristic.descriptors.first;

        // Write 0x0002 to enable indications
        final enableIndications = Uint8List.fromList([0x02, 0x00]);
        await cccd.write(enableIndications);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('writes to CCCD to disable notifications', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: false,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [platform.PlatformDescriptor(uuid: cccdUuid)],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;
        final cccd = characteristic.descriptors.first;

        // Enable then disable
        await cccd.write(Uint8List.fromList([0x01, 0x00]));
        await cccd.write(Uint8List.fromList([0x00, 0x00]));

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Descriptor by UUID', () {
      test('finds descriptor by UUID', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: true,
                    canIndicate: false,
                  ),
                  descriptors: [
                    platform.PlatformDescriptor(uuid: cccdUuid),
                    platform.PlatformDescriptor(uuid: cudUuid),
                  ],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        // Find CCCD by UUID
        final cccd = characteristic.descriptor(UUID(cccdUuid));
        expect(cccd, isNotNull);
        expect(cccd.uuid.toString().toLowerCase(), contains('2902'));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('throws when descriptor not found', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Test Device',
          services: [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false,
                    canWriteWithoutResponse: false,
                    canNotify: false,
                    canIndicate: false,
                  ),
                  descriptors: const [],
                ),
              ],
              includedServices: const [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final services = await connection.services();
        final characteristic = services.first.characteristics.first;

        expect(
          () => characteristic.descriptor(UUID(cccdUuid)),
          throwsA(isA<CharacteristicNotFoundException>()),
        );

        await connection.disconnect();
        await bluey.dispose();
      });
    });
  });
}
