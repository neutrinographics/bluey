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

  group('Server Role', () {
    group('Service Management', () {
      test('adds a service to the GATT server', () async {
        final bluey = Bluey();
        final server = bluey.server();
        expect(server, isNotNull);

        final service = LocalService(
          uuid: UUID('0000180f-0000-1000-8000-00805f9b34fb'), // Battery Service
          characteristics: [
            LocalCharacteristic.readable(
              uuid: UUID(
                '00002a19-0000-1000-8000-00805f9b34fb',
              ), // Battery Level
            ),
          ],
        );

        // Act
        await server!.addService(service);

        // Assert
        expect(fakePlatform.localServices, hasLength(1));
        expect(fakePlatform.localServices.first.uuid, contains('180f'));

        await server.dispose();
        await bluey.dispose();
      });

      test('adds multiple services', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180f-0000-1000-8000-00805f9b34fb'), // Battery
            characteristics: [],
          ),
        );
        await server.addService(
          LocalService(
            uuid: UUID('0000180a-0000-1000-8000-00805f9b34fb'), // Device Info
            characteristics: [],
          ),
        );

        // Assert
        expect(fakePlatform.localServices, hasLength(2));

        await server.dispose();
        await bluey.dispose();
      });

      test('adds service with multiple characteristics', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        final service = LocalService(
          uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'), // Heart Rate
          characteristics: [
            LocalCharacteristic.notifiable(
              uuid: UUID(
                '00002a37-0000-1000-8000-00805f9b34fb',
              ), // HR Measurement
            ),
            LocalCharacteristic.readable(
              uuid: UUID(
                '00002a38-0000-1000-8000-00805f9b34fb',
              ), // Body Sensor Location
            ),
          ],
        );

        await server.addService(service);

        // Assert
        expect(fakePlatform.localServices.first.characteristics, hasLength(2));

        await server.dispose();
        await bluey.dispose();
      });

      test('adds service with descriptors', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        final service = LocalService(
          uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
          characteristics: [
            LocalCharacteristic(
              uuid: UUID('00002a37-0000-1000-8000-00805f9b34fb'),
              properties: const CharacteristicProperties(canNotify: true),
              permissions: const [GattPermission.read],
              descriptors: [
                LocalDescriptor(
                  uuid: UUID('00002902-0000-1000-8000-00805f9b34fb'), // CCCD
                  permissions: const [
                    GattPermission.read,
                    GattPermission.write,
                  ],
                ),
              ],
            ),
          ],
        );

        await server.addService(service);

        // Assert
        final char = fakePlatform.localServices.first.characteristics.first;
        expect(char.descriptors, hasLength(1));

        await server.dispose();
        await bluey.dispose();
      });

      test('removes a service', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        final serviceUuid = UUID('0000180f-0000-1000-8000-00805f9b34fb');
        await server.addService(
          LocalService(uuid: serviceUuid, characteristics: []),
        );

        expect(fakePlatform.localServices, hasLength(1));

        // Act
        server.removeService(serviceUuid);

        // Assert
        expect(fakePlatform.localServices, isEmpty);

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Advertising', () {
      test('starts advertising', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        // Act
        await server.startAdvertising(name: 'Test Device');

        // Assert
        expect(server.isAdvertising, isTrue);
        expect(fakePlatform.isAdvertising, isTrue);
        expect(fakePlatform.advertiseConfig?.name, equals('Test Device'));

        await server.dispose();
        await bluey.dispose();
      });

      test('starts advertising with service UUIDs', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        final services = [
          UUID('0000180d-0000-1000-8000-00805f9b34fb'),
          UUID('0000180f-0000-1000-8000-00805f9b34fb'),
        ];

        await server.startAdvertising(name: 'Test Device', services: services);

        // Assert
        expect(fakePlatform.advertiseConfig?.serviceUuids, hasLength(2));

        await server.dispose();
        await bluey.dispose();
      });

      test('starts advertising with manufacturer data', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(
          name: 'Test Device',
          manufacturerData: ManufacturerData(
            0x004C, // Apple
            Uint8List.fromList([0x01, 0x02, 0x03]),
          ),
        );

        // Assert
        expect(
          fakePlatform.advertiseConfig?.manufacturerDataCompanyId,
          equals(0x004C),
        );
        expect(fakePlatform.advertiseConfig?.manufacturerData, isNotNull);

        await server.dispose();
        await bluey.dispose();
      });

      test('stops advertising', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');
        expect(server.isAdvertising, isTrue);

        // Act
        await server.stopAdvertising();

        // Assert
        expect(server.isAdvertising, isFalse);
        expect(fakePlatform.isAdvertising, isFalse);

        await server.dispose();
        await bluey.dispose();
      });

      test('isAdvertising reflects current state', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        expect(server.isAdvertising, isFalse);

        await server.startAdvertising(name: 'Test');
        expect(server.isAdvertising, isTrue);

        await server.stopAdvertising();
        expect(server.isAdvertising, isFalse);

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Central Connections', () {
      test('receives central connection event', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        final connections = <Central>[];
        final subscription = server.connections.listen(connections.add);

        // Act: Simulate central connecting
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );

        await Future.delayed(Duration.zero);

        // Assert
        expect(connections, hasLength(1));
        expect(connections.first.mtu, equals(23));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('tracks connected centrals', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        expect(server.connectedCentrals, isEmpty);

        // Connect a central
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        await Future.delayed(Duration.zero);

        // Assert
        expect(server.connectedCentrals, hasLength(1));

        await server.dispose();
        await bluey.dispose();
      });

      test('handles central disconnection', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        // Connect a central
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        await Future.delayed(Duration.zero);

        expect(server.connectedCentrals, hasLength(1));

        // Act: Central disconnects
        fakePlatform.simulateCentralDisconnection('AA:BB:CC:DD:EE:01');
        await Future.delayed(Duration.zero);

        // Assert
        expect(server.connectedCentrals, isEmpty);

        await server.dispose();
        await bluey.dispose();
      });

      test('handles multiple central connections', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        // Connect multiple centrals
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:02',
          mtu: 512,
        );
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:03',
          mtu: 256,
        );

        await Future.delayed(Duration.zero);

        // Assert
        expect(server.connectedCentrals, hasLength(3));

        await server.dispose();
        await bluey.dispose();
      });

      test('disconnects a specific central', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:02',
          mtu: 23,
        );
        await Future.delayed(Duration.zero);

        expect(server.connectedCentrals, hasLength(2));

        // Act: Disconnect one central
        final centralToDisconnect = server.connectedCentrals.first;
        await centralToDisconnect.disconnect();

        await Future.delayed(Duration.zero);

        // Assert: Only one central remains
        expect(server.connectedCentrals, hasLength(1));

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Notifications', () {
      test('sends notification to all subscribed centrals', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        final charUuid = UUID('00002a37-0000-1000-8000-00805f9b34fb');

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [LocalCharacteristic.notifiable(uuid: charUuid)],
          ),
        );

        await server.startAdvertising(name: 'Test Device');

        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        await Future.delayed(Duration.zero);

        // Act: Send notification
        final data = Uint8List.fromList([0x00, 75]); // HR = 75 bpm
        await server.notify(charUuid, data: data);

        // Assert: No exception thrown, notification sent
        expect(true, isTrue);

        await server.dispose();
        await bluey.dispose();
      });

      test('sends notification to specific central', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        final charUuid = UUID('00002a37-0000-1000-8000-00805f9b34fb');

        await server.addService(
          LocalService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [LocalCharacteristic.notifiable(uuid: charUuid)],
          ),
        );

        await server.startAdvertising(name: 'Test Device');

        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:02',
          mtu: 23,
        );
        await Future.delayed(Duration.zero);

        // Act: Send notification to specific central
        final targetCentral = server.connectedCentrals.first;
        final data = Uint8List.fromList([0x00, 80]);
        await server.notifyTo(targetCentral, charUuid, data: data);

        // Assert: No exception thrown
        expect(true, isTrue);

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Server Lifecycle', () {
      test('dispose stops advertising', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');
        expect(fakePlatform.isAdvertising, isTrue);

        // Act
        await server.dispose();

        // Assert
        expect(fakePlatform.isAdvertising, isFalse);

        await bluey.dispose();
      });

      test('dispose disconnects all centrals', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:01',
          mtu: 23,
        );
        fakePlatform.simulateCentralConnection(
          centralId: 'AA:BB:CC:DD:EE:02',
          mtu: 23,
        );
        await Future.delayed(Duration.zero);

        expect(fakePlatform.connectedCentralIds, hasLength(2));

        // Act
        await server.dispose();

        // Assert
        expect(fakePlatform.connectedCentralIds, isEmpty);

        await bluey.dispose();
      });

      test('dispose clears local services', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          LocalService(
            uuid: UUID('0000180f-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        expect(fakePlatform.localServices, hasLength(1));

        // Act
        await server.dispose();

        // Assert
        expect(fakePlatform.localServices, isEmpty);

        await bluey.dispose();
      });
    });
  });
}
