import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
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

        final bluey = await Bluey.create();

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

        final bluey = await Bluey.create();

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

        final bluey = await Bluey.create();

        // Discover devices
        final scanner = bluey.scanner();
        final results = <ScanResult>[];
        final subscription = scanner.scan().listen(results.add);
        await Future.delayed(Duration.zero);
        await subscription.cancel();
        scanner.dispose();

        expect(results, hasLength(3));

        // Connect to all three in parallel
        final connectionFutures =
            results.map((r) => bluey.connect(r.device)).toList();
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

        final bluey = await Bluey.create();

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
      // Rewritten through the public Connection API (audit R3 / NT-2,
      // DA-39): the originals called the fake's readCharacteristicByUuid
      // directly, so they exercised the fake's map access rather than the
      // library. With operationLatency the parallelism is now genuine —
      // both operations are provably in flight at the same time.

      Connection bootConnected(FakeAsync async, Bluey Function() getBluey) {
        late Connection connection;
        getBluey()
            .connect(Device(address: const DeviceAddress(TestDeviceIds.device1)))
            .then((c) => connection = c);
        async.flushMicrotasks();
        return connection;
      }

      test('reads from two characteristics genuinely overlap in flight', () {
        fakeAsync((async) {
          fakePlatform.simulatePeripheral(
            id: TestDeviceIds.device1,
            name: 'Test Device',
            services: [
              TestServiceBuilder(TestUuids.heartRateService)
                  .withReadable(TestUuids.heartRateMeasurement)
                  .withReadable(TestUuids.bodySensorLocation)
                  .build(),
            ],
            characteristicValues: {
              TestUuids.heartRateMeasurement: Uint8List.fromList([0x01]),
              TestUuids.bodySensorLocation: Uint8List.fromList([0x02]),
            },
          );

          late Bluey bluey;
          Bluey.create().then((b) => bluey = b);
          async.flushMicrotasks();
          final connection = bootConnected(async, () => bluey);
          late List<RemoteCharacteristic> chars;
          connection
              .services()
              .then((s) => chars = s.first.characteristics());
          async.flushMicrotasks();

          fakePlatform.operationLatency = const Duration(milliseconds: 50);

          Uint8List? value1;
          Uint8List? value2;
          chars[0].read().then((v) => value1 = v);
          chars[1].read().then((v) => value2 = v);
          async.flushMicrotasks();

          expect(
            fakePlatform.readCharacteristicCalls,
            hasLength(2),
            reason: 'both reads reached the platform before either completed',
          );
          expect(value1, isNull);
          expect(value2, isNull);

          async.elapse(const Duration(milliseconds: 51));
          expect(value1, equals([0x01]));
          expect(value2, equals([0x02]));

          bluey.dispose();
          async.flushMicrotasks();
        });
      });

      test('writes to two characteristics genuinely overlap in flight', () {
        fakeAsync((async) {
          fakePlatform.simulatePeripheral(
            id: TestDeviceIds.device1,
            name: 'Test Device',
            services: [
              TestServiceBuilder(TestUuids.heartRateService)
                  .withReadWrite(TestUuids.heartRateMeasurement)
                  .withReadWrite(TestUuids.bodySensorLocation)
                  .build(),
            ],
          );

          late Bluey bluey;
          Bluey.create().then((b) => bluey = b);
          async.flushMicrotasks();
          final connection = bootConnected(async, () => bluey);
          late List<RemoteCharacteristic> chars;
          connection
              .services()
              .then((s) => chars = s.first.characteristics());
          async.flushMicrotasks();

          fakePlatform.operationLatency = const Duration(milliseconds: 50);

          var write1Done = false;
          var write2Done = false;
          chars[0]
              .write(Uint8List.fromList([0xAA]))
              .then((_) => write1Done = true);
          chars[1]
              .write(Uint8List.fromList([0xBB]))
              .then((_) => write2Done = true);
          async.flushMicrotasks();

          expect(fakePlatform.writeCharacteristicCalls, hasLength(2));
          expect(write1Done, isFalse);
          expect(write2Done, isFalse);

          async.elapse(const Duration(milliseconds: 51));
          expect(write1Done, isTrue);
          expect(write2Done, isTrue);

          // Read back through the API (instantly — latency off again).
          fakePlatform.operationLatency = null;
          Uint8List? value1;
          Uint8List? value2;
          chars[0].read().then((v) => value1 = v);
          chars[1].read().then((v) => value2 = v);
          async.flushMicrotasks();
          expect(value1, equals([0xAA]));
          expect(value2, equals([0xBB]));

          bluey.dispose();
          async.flushMicrotasks();
        });
      });

      test('interleaved reads and writes on one characteristic all complete; '
          'last write wins', () {
        fakeAsync((async) {
          fakePlatform.simulatePeripheral(
            id: TestDeviceIds.device1,
            name: 'Test Device',
            services: [
              TestServiceBuilder(TestUuids.heartRateService)
                  .withReadWrite(TestUuids.heartRateMeasurement)
                  .build(),
            ],
            characteristicValues: {
              TestUuids.heartRateMeasurement: Uint8List.fromList([0x00]),
            },
          );

          late Bluey bluey;
          Bluey.create().then((b) => bluey = b);
          async.flushMicrotasks();
          final connection = bootConnected(async, () => bluey);
          late RemoteCharacteristic characteristic;
          connection
              .services()
              .then((s) => characteristic = s.first.characteristics().first);
          async.flushMicrotasks();

          fakePlatform.operationLatency = const Duration(milliseconds: 50);

          var completed = 0;
          characteristic.read().then((_) => completed++);
          characteristic
              .write(Uint8List.fromList([0x01]))
              .then((_) => completed++);
          characteristic.read().then((_) => completed++);
          characteristic
              .write(Uint8List.fromList([0x02]))
              .then((_) => completed++);
          async.flushMicrotasks();

          expect(completed, 0, reason: 'all four ops are in flight at once');
          async.elapse(const Duration(milliseconds: 51));
          expect(completed, 4);

          fakePlatform.operationLatency = null;
          Uint8List? finalValue;
          characteristic.read().then((v) => finalValue = v);
          async.flushMicrotasks();
          expect(finalValue, equals([0x02]));

          bluey.dispose();
          async.flushMicrotasks();
        });
      });
    });

    group('Concurrent Notifications', () {
      // Rewritten through characteristic.notifications (audit R3 / NT-2):
      // the originals subscribed at the fake level (setNotificationByUuid +
      // platform notificationStream), bypassing the domain layer entirely.

      test('receives notifications from multiple characteristics', () async {
        fakePlatform.simulatePeripheral(
          id: TestDeviceIds.device1,
          name: 'Test Device',
          services: [
            TestServiceBuilder(TestUuids.heartRateService)
                .withNotifiable(TestUuids.heartRateMeasurement)
                .withNotifiable(TestUuids.bodySensorLocation)
                .build(),
          ],
        );

        final bluey = await Bluey.create();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final service = (await connection.services()).first;
        final char1 = service
            .characteristics(uuid: UUID(TestUuids.heartRateMeasurement))
            .first;
        final char2 = service
            .characteristics(uuid: UUID(TestUuids.bodySensorLocation))
            .first;

        final received1 = <Uint8List>[];
        final received2 = <Uint8List>[];
        final sub1 = char1.notifications.listen(received1.add);
        final sub2 = char2.notifications.listen(received2.add);
        await Future.delayed(Duration.zero);

        fakePlatform.simulateNotification(
          deviceId: TestDeviceIds.device1,
          characteristicUuid: TestUuids.heartRateMeasurement,
          value: Uint8List.fromList([0x01]),
        );
        fakePlatform.simulateNotification(
          deviceId: TestDeviceIds.device1,
          characteristicUuid: TestUuids.bodySensorLocation,
          value: Uint8List.fromList([0x02]),
        );
        await Future.delayed(Duration.zero);

        expect(received1, hasLength(1));
        expect(received1.single, equals([0x01]));
        expect(received2, hasLength(1));
        expect(received2.single, equals([0x02]));

        await sub1.cancel();
        await sub2.cancel();
        await bluey.dispose();
      });

      test('high-frequency notifications are all received in order', () async {
        fakePlatform.simulatePeripheral(
          id: TestDeviceIds.device1,
          name: 'Test Device',
          services: [
            TestServiceBuilder(TestUuids.heartRateService)
                .withNotifiable(TestUuids.heartRateMeasurement)
                .build(),
          ],
        );

        final bluey = await Bluey.create();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        final characteristic =
            (await connection.services()).first.characteristics().first;

        final received = <Uint8List>[];
        final subscription = characteristic.notifications.listen(received.add);
        await Future.delayed(Duration.zero);

        for (var i = 0; i < 100; i++) {
          fakePlatform.simulateNotification(
            deviceId: TestDeviceIds.device1,
            characteristicUuid: TestUuids.heartRateMeasurement,
            value: Uint8List.fromList([i]),
          );
        }
        await Future.delayed(Duration.zero);

        expect(received, hasLength(100));
        expect(
          received.asMap().entries.every((e) => e.value.single == e.key),
          isTrue,
          reason: 'notifications arrive in emission order',
        );

        await subscription.cancel();
        await bluey.dispose();
      });
    });

    group('Server Concurrent Operations', () {
      test('handles multiple centrals connecting simultaneously', () async {
        final bluey = await Bluey.create();
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
          final bluey = await Bluey.create();
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
        final bluey = await Bluey.create();
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
        await fakePlatform.notifyCharacteristicByUuid(
          '00002a37-0000-1000-8000-00805f9b34fb',
          Uint8List.fromList([0x01]),
        );

        // Individual notifications to each
        await Future.wait([
          fakePlatform.notifyCharacteristicToByUuid(
            'central-1',
            '00002a37-0000-1000-8000-00805f9b34fb',
            Uint8List.fromList([0x02]),
          ),
          fakePlatform.notifyCharacteristicToByUuid(
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
                  handle: 0,
                ),
              ],
              includedServices: [],
            ),
          ],
          characteristicValues: {
            '00002a19-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x64]),
          },
        );

        final bluey = await Bluey.create();

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
        final remoteValue = await fakePlatform.readCharacteristicByUuid(
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
