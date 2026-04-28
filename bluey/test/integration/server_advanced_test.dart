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

  group('Server Advanced Scenarios', () {
    group('Central Subscription Tracking', () {
      test('tracks which centrals are connected', () async {
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

        // Track connections
        final connectedCentrals = <String>[];
        final subscription = fakePlatform.centralConnections.listen((central) {
          connectedCentrals.add(central.id);
        });

        // Multiple centrals connect
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'tablet-1');
        fakePlatform.simulateCentralConnection(centralId: 'watch-1');

        await Future.delayed(Duration.zero);

        expect(connectedCentrals, hasLength(3));
        expect(fakePlatform.connectedCentralIds, hasLength(3));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('tracks central disconnections', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        final disconnectedCentrals = <String>[];
        final subscription = fakePlatform.centralDisconnections.listen(
          disconnectedCentrals.add,
        );

        // Connect and disconnect
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');

        await Future.delayed(Duration.zero);
        expect(fakePlatform.connectedCentralIds, hasLength(2));

        fakePlatform.simulateCentralDisconnection('phone-1');

        await Future.delayed(Duration.zero);

        expect(disconnectedCentrals, contains('phone-1'));
        expect(fakePlatform.connectedCentralIds, hasLength(1));
        expect(fakePlatform.connectedCentralIds, contains('phone-2'));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('can notify specific central only', () async {
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

        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');

        // Send to specific central
        await fakePlatform.notifyCharacteristicToByUuid('phone-1', '00002a37-0000-1000-8000-00805f9b34fb', Uint8List.fromList([0x01, 0x02]), );

        // Send to other central
        await fakePlatform.notifyCharacteristicToByUuid('phone-2', '00002a37-0000-1000-8000-00805f9b34fb', Uint8List.fromList([0x03, 0x04]), );

        await server.dispose();
        await bluey.dispose();
      });

      test('broadcast notifies all connected centrals', () async {
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

        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');
        fakePlatform.simulateCentralConnection(centralId: 'phone-3');

        // Broadcast to all
        await fakePlatform.notifyCharacteristicByUuid('00002a37-0000-1000-8000-00805f9b34fb', Uint8List.fromList([0xFF]), );

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Read Request Handling', () {
      test('handles read requests from different centrals', () async {
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

        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');

        // Set up handler to respond with central-specific data
        final subscription = fakePlatform.readRequests.listen((request) {
          final responseData =
              request.centralId == 'phone-1'
                  ? Uint8List.fromList([0x01])
                  : Uint8List.fromList([0x02]);

          fakePlatform.respondToReadRequest(
            request.requestId,
            platform.PlatformGattStatus.success,
            responseData,
          );
        });

        // Both centrals read
        final result1 = await fakePlatform.simulateReadRequest(
          centralId: 'phone-1',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
        );

        final result2 = await fakePlatform.simulateReadRequest(
          centralId: 'phone-2',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
        );

        expect(result1, equals(Uint8List.fromList([0x01])));
        expect(result2, equals(Uint8List.fromList([0x02])));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('can reject read requests', () async {
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
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');

        // Reject all read requests
        final subscription = fakePlatform.readRequests.listen((request) {
          fakePlatform.respondToReadRequest(
            request.requestId,
            platform.PlatformGattStatus.readNotPermitted,
            null,
          );
        });

        Object? caughtError;
        try {
          await fakePlatform.simulateReadRequest(
            centralId: 'phone-1',
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
    });

    group('Write Request Handling', () {
      test('handles write requests with response', () async {
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
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');

        final receivedWrites = <Uint8List>[];
        final subscription = fakePlatform.writeRequests.listen((request) {
          receivedWrites.add(request.value);
          fakePlatform.respondToWriteRequest(
            request.requestId,
            platform.PlatformGattStatus.success,
          );
        });

        await fakePlatform.simulateWriteRequest(
          centralId: 'phone-1',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0x01, 0x02, 0x03]),
        );

        expect(receivedWrites, hasLength(1));
        expect(
          receivedWrites.first,
          equals(Uint8List.fromList([0x01, 0x02, 0x03])),
        );

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('handles write without response', () async {
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
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');

        final receivedWrites = <Uint8List>[];
        final subscription = fakePlatform.writeRequests.listen((request) {
          receivedWrites.add(request.value);
          // No response needed for write without response
          if (request.responseNeeded) {
            fakePlatform.respondToWriteRequest(
              request.requestId,
              platform.PlatformGattStatus.success,
            );
          }
        });

        // Write without response
        await fakePlatform.simulateWriteRequest(
          centralId: 'phone-1',
          characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
          value: Uint8List.fromList([0xAA, 0xBB]),
          responseNeeded: false,
        );

        expect(receivedWrites, hasLength(1));

        await subscription.cancel();
        await server.dispose();
        await bluey.dispose();
      });

      test('can reject write requests', () async {
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
        fakePlatform.simulateCentralConnection(centralId: 'phone-1');

        // Reject all write requests
        final subscription = fakePlatform.writeRequests.listen((request) {
          fakePlatform.respondToWriteRequest(
            request.requestId,
            platform.PlatformGattStatus.writeNotPermitted,
          );
        });

        Object? caughtError;
        try {
          await fakePlatform.simulateWriteRequest(
            centralId: 'phone-1',
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

    group('Multiple Services', () {
      test('serves multiple services simultaneously', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        // Add multiple services
        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'), // Heart Rate
            characteristics: [
              HostedCharacteristic.notifiable(
                uuid: UUID('00002a37-0000-1000-8000-00805f9b34fb'),
              ),
            ],
          ),
        );

        await server.addService(
          HostedService(
            uuid: UUID('0000180f-0000-1000-8000-00805f9b34fb'), // Battery
            characteristics: [
              HostedCharacteristic.readable(
                uuid: UUID('00002a19-0000-1000-8000-00805f9b34fb'),
              ),
            ],
          ),
        );

        await server.addService(
          HostedService(
            uuid: UUID('0000180a-0000-1000-8000-00805f9b34fb'), // Device Info
            characteristics: [
              HostedCharacteristic.readable(
                uuid: UUID('00002a29-0000-1000-8000-00805f9b34fb'),
              ),
            ],
          ),
        );

        // +1 for the auto-registered lifecycle control service
        expect(fakePlatform.localServices, hasLength(4));

        await server.startAdvertising(
          name: 'Multi-Service Device',
          services: [
            UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            UUID('0000180f-0000-1000-8000-00805f9b34fb'),
            UUID('0000180a-0000-1000-8000-00805f9b34fb'),
          ],
        );

        expect(fakePlatform.isAdvertising, isTrue);

        await server.dispose();
        await bluey.dispose();
      });

      test('removes service while others remain', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.addService(
          HostedService(
            uuid: UUID('0000180f-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        // +1 for the auto-registered lifecycle control service
        expect(fakePlatform.localServices, hasLength(3));

        // Remove one service
        server.removeService(UUID('0000180d-0000-1000-8000-00805f9b34fb'));

        // +1 for the auto-registered lifecycle control service
        expect(fakePlatform.localServices, hasLength(2));
        expect(fakePlatform.localServices.last.uuid, contains('180f'));

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Advertising with Manufacturer Data', () {
      test('includes manufacturer data in advertisement', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(
          name: 'Custom Device',
          manufacturerData: ManufacturerData(
            0x004C, // Apple company ID
            Uint8List.fromList([0x01, 0x02, 0x03]),
          ),
        );

        expect(fakePlatform.isAdvertising, isTrue);
        expect(
          fakePlatform.advertiseConfig?.manufacturerDataCompanyId,
          equals(0x004C),
        );
        expect(
          fakePlatform.advertiseConfig?.manufacturerData,
          equals(Uint8List.fromList([0x01, 0x02, 0x03])),
        );

        await server.dispose();
        await bluey.dispose();
      });
    });

    group('Server Disconnect Central', () {
      test('server can disconnect a specific central', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');

        expect(fakePlatform.connectedCentralIds, hasLength(2));

        // Server disconnects one central
        await fakePlatform.disconnectCentral('phone-1');

        expect(fakePlatform.connectedCentralIds, hasLength(1));
        expect(fakePlatform.connectedCentralIds, contains('phone-2'));

        await server.dispose();
        await bluey.dispose();
      });

      test('closeServer disconnects all centrals', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        fakePlatform.simulateCentralConnection(centralId: 'phone-1');
        fakePlatform.simulateCentralConnection(centralId: 'phone-2');
        fakePlatform.simulateCentralConnection(centralId: 'phone-3');

        expect(fakePlatform.connectedCentralIds, hasLength(3));

        // Close server
        await fakePlatform.closeServer();

        expect(fakePlatform.connectedCentralIds, isEmpty);
        expect(fakePlatform.isAdvertising, isFalse);

        await bluey.dispose();
      });
    });

    group('Concurrent Central Operations', () {
      test('handles rapid connects and disconnects', () async {
        final bluey = Bluey();
        final server = bluey.server()!;

        await server.addService(
          HostedService(
            uuid: UUID('0000180d-0000-1000-8000-00805f9b34fb'),
            characteristics: [],
          ),
        );

        await server.startAdvertising(name: 'Test Server');

        // Rapid connect/disconnect cycles
        for (var i = 0; i < 10; i++) {
          fakePlatform.simulateCentralConnection(centralId: 'central-$i');
        }

        expect(fakePlatform.connectedCentralIds, hasLength(10));

        for (var i = 0; i < 5; i++) {
          fakePlatform.simulateCentralDisconnection('central-$i');
        }

        expect(fakePlatform.connectedCentralIds, hasLength(5));

        await server.dispose();
        await bluey.dispose();
      });
    });
  });
}
