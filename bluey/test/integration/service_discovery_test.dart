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

  group('Service Discovery', () {
    group('Basic service discovery', () {
      test('discovers services on connected device', () async {
        // Arrange: Device with Heart Rate service
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final discoveredServices = await connection.services;

        // Assert
        expect(discoveredServices, hasLength(1));
        expect(
          discoveredServices.first.uuid.toString().toLowerCase(),
          contains('180d'),
        );

        await connection.disconnect();
        await bluey.dispose();
      });

      test('discovers multiple services', () async {
        // Arrange: Device with multiple services
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Multi-Service Device',
          services: [
            const platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb', // Heart Rate
              isPrimary: true,
              characteristics: [],
              includedServices: [],
            ),
            const platform.PlatformService(
              uuid: '0000180f-0000-1000-8000-00805f9b34fb', // Battery
              isPrimary: true,
              characteristics: [],
              includedServices: [],
            ),
            const platform.PlatformService(
              uuid: '0000180a-0000-1000-8000-00805f9b34fb', // Device Info
              isPrimary: true,
              characteristics: [],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final discoveredServices = await connection.services;

        // Assert
        expect(discoveredServices, hasLength(3));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('discovers characteristics within service', () async {
        // Arrange
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
                      '00002a37-0000-1000-8000-00805f9b34fb', // Heart Rate Measurement
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
                  uuid:
                      '00002a38-0000-1000-8000-00805f9b34fb', // Body Sensor Location
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final discoveredServices = await connection.services;
        final characteristics = discoveredServices.first.characteristics;

        // Assert
        expect(characteristics, hasLength(2));

        await connection.disconnect();
        await bluey.dispose();
      });

      test('discovers descriptors within characteristic', () async {
        // Arrange: Characteristic with CCCD descriptor
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
                  descriptors: [
                    platform.PlatformDescriptor(
                      uuid: '00002902-0000-1000-8000-00805f9b34fb', // CCCD
                    ),
                  ],
                ),
              ],
              includedServices: [],
            ),
          ],
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final discoveredServices = await connection.services;
        final descriptors =
            discoveredServices.first.characteristics.first.descriptors;

        // Assert
        expect(descriptors, hasLength(1));
        expect(
          descriptors.first.uuid.toString().toLowerCase(),
          contains('2902'),
        );

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Characteristic properties', () {
      test('correctly reports readable characteristic', () async {
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
                      '00002a29-0000-1000-8000-00805f9b34fb', // Manufacturer Name
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);
        final discoveredServices = await connection.services;
        final char = discoveredServices.first.characteristics.first;

        // Assert
        expect(char.properties.canRead, isTrue);
        expect(char.properties.canWrite, isFalse);
        expect(char.properties.canNotify, isFalse);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('correctly reports writable characteristic', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);
        final discoveredServices = await connection.services;
        final char = discoveredServices.first.characteristics.first;

        // Assert
        expect(char.properties.canRead, isFalse);
        expect(char.properties.canWrite, isTrue);
        expect(char.properties.canWriteWithoutResponse, isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('correctly reports notifiable characteristic', () async {
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
                      '00002a37-0000-1000-8000-00805f9b34fb', // Heart Rate Measurement
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
        final connection = await bluey.connect(device);
        final discoveredServices = await connection.services;
        final char = discoveredServices.first.characteristics.first;

        // Assert
        expect(char.properties.canNotify, isTrue);
        expect(char.properties.canIndicate, isFalse);

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Service access', () {
      test('can access service by UUID', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Trigger service discovery
        await connection.services;

        // Act: Access service by UUID
        final heartRateService = connection.service(
          UUID('0000180d-0000-1000-8000-00805f9b34fb'),
        );

        // Assert
        expect(heartRateService, isNotNull);
        expect(heartRateService.isPrimary, isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('throws when accessing non-existent service', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Trigger service discovery
        await connection.services;

        // Act & Assert
        expect(
          () => connection.service(
            UUID('0000180f-0000-1000-8000-00805f9b34fb'),
          ), // Battery service - not present
          throwsA(isA<ServiceNotFoundException>()),
        );

        await connection.disconnect();
        await bluey.dispose();
      });

      test('hasService returns true for existing service', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final hasHeartRate = await connection.hasService(
          UUID('0000180d-0000-1000-8000-00805f9b34fb'),
        );

        // Assert
        expect(hasHeartRate, isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('hasService returns false for missing service', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final hasBattery = await connection.hasService(
          UUID('0000180f-0000-1000-8000-00805f9b34fb'),
        );

        // Assert
        expect(hasBattery, isFalse);

        await connection.disconnect();
        await bluey.dispose();
      });
    });

    group('Edge cases', () {
      test('handles device with no services', () async {
        fakePlatform.simulatePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Empty Device',
          services: [],
        );

        final bluey = Bluey();
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act
        final discoveredServices = await connection.services;

        // Assert
        expect(discoveredServices, isEmpty);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('handles service with no characteristics', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);
        final discoveredServices = await connection.services;

        // Assert
        expect(discoveredServices, hasLength(1));
        expect(discoveredServices.first.characteristics, isEmpty);

        await connection.disconnect();
        await bluey.dispose();
      });

      test('services are cached after first discovery', () async {
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
        final device = await bluey.scan().first;
        final connection = await bluey.connect(device);

        // Act: Access services twice
        final services1 = await connection.services;
        final services2 = await connection.services;

        // Assert: Same instance returned
        expect(identical(services1, services2), isTrue);

        await connection.disconnect();
        await bluey.dispose();
      });
    });
  });
}
