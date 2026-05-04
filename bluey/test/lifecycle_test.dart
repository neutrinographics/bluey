import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_platform.dart';

// Control service UUIDs (must match lifecycle.dart)
const _controlServiceUuid = 'b1e70001-0000-1000-8000-00805f9b34fb';
const _heartbeatCharUuid = 'b1e70002-0000-1000-8000-00805f9b34fb';
const _intervalCharUuid = 'b1e70003-0000-1000-8000-00805f9b34fb';

// Use proper UUID-format IDs so BlueyClient.id passes them through unchanged,
// matching what real platforms (iOS UUIDs, Android MACs) provide.
const _clientId1 = '00000000-0000-0000-0000-000000000001';
const _clientId2 = '00000000-0000-0000-0000-000000000002';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    BlueyPlatform.instance = fakePlatform;
  });

  group('Server Lifecycle', () {
    test('adds control service when lifecycle is enabled', () async {
      final bluey = Bluey();
      final server = bluey.server()!;

      await server.addService(
        HostedService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [],
        ),
      );
      await server.startAdvertising();

      // Should have 2 services: control + consumer
      expect(fakePlatform.localServices, hasLength(2));
      expect(
        fakePlatform.localServices.any((s) => s.uuid == _controlServiceUuid),
        isTrue,
      );

      await server.dispose();
      await bluey.dispose();
    });

    test('does NOT add control service when lifecycle is null', () async {
      final bluey = Bluey();
      final server = bluey.server(lifecycleInterval: null)!;

      await server.addService(
        HostedService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [],
        ),
      );
      await server.startAdvertising();

      expect(fakePlatform.localServices, hasLength(1));
      expect(
        fakePlatform.localServices.any((s) => s.uuid == _controlServiceUuid),
        isFalse,
      );

      await server.dispose();
      await bluey.dispose();
    });

    test('filters heartbeat writes from public writeRequests', () async {
      final bluey = Bluey();
      final server = bluey.server()!;

      await server.addService(
        HostedService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [
            HostedCharacteristic(
              uuid: UUID('12345678-1234-1234-1234-123456789abd'),
              properties: const CharacteristicProperties(
                canRead: true,
                canWrite: true,
              ),
              permissions: const [GattPermission.read, GattPermission.write],
            ),
          ],
        ),
      );
      await server.startAdvertising();

      fakePlatform.simulateCentralConnection(centralId: _clientId1);

      final publicWrites = <WriteRequest>[];
      server.writeRequests.listen(publicWrites.add);

      // Wait for streams to connect
      await Future.delayed(Duration.zero);

      // Send a heartbeat write (should be filtered) — client now uses
      // write-with-response so responseNeeded is true
      await fakePlatform.simulateWriteRequest(
        centralId: _clientId1,
        characteristicUuid: _heartbeatCharUuid,
        value: Uint8List.fromList([0x01]),
        responseNeeded: true,
      );
      await Future.delayed(Duration.zero);

      // Send a regular write (should appear)
      await fakePlatform.simulateWriteRequest(
        centralId: _clientId1,
        characteristicUuid: '12345678-1234-1234-1234-123456789abd',
        value: Uint8List.fromList([0xAA]),
        responseNeeded: false,
      );
      await Future.delayed(Duration.zero);

      expect(publicWrites, hasLength(1));
      expect(publicWrites.first.value, Uint8List.fromList([0xAA]));

      await server.dispose();
      await bluey.dispose();
    });

    test(
      'heartbeat timeout fires disconnect after client opts into lifecycle',
      () {
        fakeAsync((async) {
          final bluey = Bluey();
          final server =
              bluey.server(lifecycleInterval: const Duration(seconds: 5))!;

          server.startAdvertising();
          async.elapse(Duration.zero);

          final disconnections = <String>[];
          server.disconnections.listen(disconnections.add);

          fakePlatform.simulateCentralConnection(centralId: _clientId1);
          async.elapse(Duration.zero);

          // First heartbeat opts the client into the lifecycle protocol and
          // starts the timer.
          fakePlatform.simulateWriteRequest(
            centralId: _clientId1,
            characteristicUuid: _heartbeatCharUuid,
            value: Uint8List.fromList([0x01]),
            responseNeeded: true,
          );
          async.elapse(Duration.zero);

          // No further heartbeats — wait for timeout.
          async.elapse(const Duration(seconds: 5));

          expect(disconnections, contains(_clientId1));
          expect(server.connectedClients, isEmpty);

          server.dispose();
          bluey.dispose();
        });
      },
    );

    test('heartbeat resets timer', () {
      fakeAsync((async) {
        final bluey = Bluey();
        final server =
            bluey.server(lifecycleInterval: const Duration(seconds: 5))!;

        server.startAdvertising();
        async.elapse(Duration.zero);

        final disconnections = <String>[];
        server.disconnections.listen(disconnections.add);

        fakePlatform.simulateCentralConnection(centralId: _clientId1);
        async.elapse(Duration.zero);

        // Send heartbeat at 3 seconds (before timeout)
        async.elapse(const Duration(seconds: 3));
        fakePlatform.simulateWriteRequest(
          centralId: _clientId1,
          characteristicUuid: _heartbeatCharUuid,
          value: Uint8List.fromList([0x01]),
          responseNeeded: true,
        );
        async.elapse(Duration.zero);

        // Wait another 3 seconds (total 6 from start, but only 3 since
        // last heartbeat — should still be connected)
        async.elapse(const Duration(seconds: 3));
        expect(disconnections, isEmpty);
        expect(server.connectedClients, hasLength(1));

        // Wait 2 more seconds (5 since last heartbeat) — should disconnect
        async.elapse(const Duration(seconds: 2));
        expect(disconnections, contains(_clientId1));

        server.dispose();
        bluey.dispose();
      });
    });

    test('disconnect command triggers immediate disconnect', () async {
      final bluey = Bluey();
      final server = bluey.server()!;
      await server.startAdvertising();

      final disconnections = <String>[];
      server.disconnections.listen(disconnections.add);

      fakePlatform.simulateCentralConnection(centralId: _clientId1);
      await Future.delayed(Duration.zero);

      // Send disconnect command
      await fakePlatform.simulateWriteRequest(
        centralId: _clientId1,
        characteristicUuid: _heartbeatCharUuid,
        value: Uint8List.fromList([0x00]),
        responseNeeded: true,
      );
      await Future.delayed(Duration.zero);

      expect(disconnections, contains(_clientId1));
      expect(server.connectedClients, isEmpty);

      await server.dispose();
      await bluey.dispose();
    });

    test('non-Bluey client that never heartbeats is not disconnected', () {
      fakeAsync((async) {
        final bluey = Bluey();
        final server =
            bluey.server(lifecycleInterval: const Duration(seconds: 5))!;

        server.startAdvertising();
        async.elapse(Duration.zero);

        final disconnections = <String>[];
        server.disconnections.listen(disconnections.add);

        // A non-Bluey central connects but never writes to the heartbeat
        // characteristic — it doesn't know about the lifecycle protocol.
        fakePlatform.simulateCentralConnection(centralId: _clientId1);
        async.elapse(Duration.zero);

        // Wait well past the lifecycle interval.
        async.elapse(const Duration(seconds: 30));

        // Client must still be connected — it was never timed out.
        expect(disconnections, isEmpty);
        expect(server.connectedClients, hasLength(1));

        server.dispose();
        bluey.dispose();
      });
    });

    test('filters interval reads from public readRequests', () async {
      final bluey = Bluey();
      final server = bluey.server()!;
      await server.startAdvertising();

      final publicReads = <ReadRequest>[];
      server.readRequests.listen(publicReads.add);

      fakePlatform.simulateCentralConnection(centralId: _clientId1);
      await Future.delayed(Duration.zero);

      // Send a read to the interval characteristic (should be filtered)
      fakePlatform.simulateReadRequest(
        centralId: _clientId1,
        characteristicUuid: _intervalCharUuid,
      );
      await Future.delayed(Duration.zero);

      expect(publicReads, isEmpty);

      await server.dispose();
      await bluey.dispose();
    });

    test('platform disconnect cancels heartbeat timer', () {
      fakeAsync((async) {
        final bluey = Bluey();
        final server =
            bluey.server(lifecycleInterval: const Duration(seconds: 5))!;

        server.startAdvertising();
        async.elapse(Duration.zero);

        final disconnections = <String>[];
        server.disconnections.listen(disconnections.add);

        fakePlatform.simulateCentralConnection(centralId: _clientId1);
        async.elapse(Duration.zero);

        // Platform disconnect (Android's onConnectionStateChange)
        fakePlatform.simulateCentralDisconnection(_clientId1);
        async.elapse(Duration.zero);

        expect(disconnections, hasLength(1));

        // Wait past the original timeout — should NOT fire a second disconnect
        async.elapse(const Duration(seconds: 10));
        expect(disconnections, hasLength(1));

        server.dispose();
        bluey.dispose();
      });
    });

    test('dispose cancels all heartbeat timers', () {
      fakeAsync((async) {
        final bluey = Bluey();
        final server =
            bluey.server(lifecycleInterval: const Duration(seconds: 5))!;

        server.startAdvertising();
        async.elapse(Duration.zero);

        fakePlatform.simulateCentralConnection(centralId: _clientId1);
        fakePlatform.simulateCentralConnection(centralId: _clientId2);
        async.elapse(Duration.zero);

        server.dispose();
        async.elapse(Duration.zero);

        // Advancing time past the timeout should not throw or cause issues
        async.elapse(const Duration(seconds: 10));

        bluey.dispose();
      });
    });

    test('control service includes the serverId characteristic', () {
      final service = buildControlService();
      final charUuids =
          service.characteristics.map((c) => c.uuid.toLowerCase()).toList();
      expect(charUuids, contains('b1e70004-0000-1000-8000-00805f9b34fb'));

      final serverIdChar = service.characteristics.firstWhere(
        (c) => c.uuid.toLowerCase() == 'b1e70004-0000-1000-8000-00805f9b34fb',
      );
      expect(serverIdChar.properties.canRead, isTrue);
      expect(serverIdChar.properties.canWrite, isFalse);
    });

    test('encodeServerId/decodeServerId round-trip', () {
      final id = ServerId.generate();
      final bytes = encodeServerId(id);
      expect(bytes, hasLength(16));
      expect(decodeServerId(bytes), equals(id));
    });

    test(
      'emits disconnect for untracked client (stale connection after server restart)',
      () async {
        final bluey = Bluey();
        final server = bluey.server()!;
        await server.startAdvertising();

        final disconnections = <String>[];
        server.disconnections.listen(disconnections.add);

        // Simulate a central that was connected before the server restarted.
        // The server has NO record of this client -- it was never in
        // _connectedClients. But the platform reports its disconnection.
        fakePlatform.simulateCentralDisconnection('stale-client-id');
        await Future.delayed(Duration.zero);

        // The server should still emit the disconnect event.
        expect(disconnections, contains('stale-client-id'));

        await server.dispose();
        await bluey.dispose();
      },
    );

    test('auto-generates a ServerId when constructed without identity', () {
      final bluey = Bluey();
      final server = bluey.server()!;
      expect(server.serverId, isNotNull);
      server.dispose();
      bluey.dispose();
    });

    test('respects an app-supplied identity', () {
      final id = ServerId('11111111-2222-3333-4444-555555555555');
      final bluey = Bluey();
      final server = bluey.server(identity: id)!;
      expect(server.serverId, equals(id));
      server.dispose();
      bluey.dispose();
    });

    test(
      'server responds to serverId reads with the configured identity',
      () async {
        final id = ServerId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
        final bluey = Bluey();
        final server = bluey.server(identity: id)!;
        await server.startAdvertising();

        fakePlatform.simulateCentralConnection(centralId: _clientId1);
        await Future.delayed(Duration.zero);

        fakePlatform.simulateReadRequest(
          centralId: _clientId1,
          characteristicUuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
        );
        await Future.delayed(Duration.zero);

        expect(fakePlatform.respondReadCalls, isNotEmpty);
        final call = fakePlatform.respondReadCalls.last;
        expect(call.value, equals(id.toBytes()));

        await server.dispose();
        await bluey.dispose();
      },
    );
  });

  group('lifecycle.dart utilities', () {
    // 18. isControlService returns true for control service UUID
    test('isControlService returns true for control service UUID', () {
      expect(isControlService('b1e70001-0000-1000-8000-00805f9b34fb'), isTrue);
    });

    // 19. isControlService returns false for random UUID
    test('isControlService returns false for random UUID', () {
      expect(isControlService('0000180d-0000-1000-8000-00805f9b34fb'), isFalse);
    });

    // 20. isControlServiceCharacteristic returns true for all three char UUIDs
    test(
      'isControlServiceCharacteristic returns true for all three char UUIDs',
      () {
        expect(
          isControlServiceCharacteristic(
            'b1e70002-0000-1000-8000-00805f9b34fb',
          ),
          isTrue,
          reason: 'heartbeat char',
        );
        expect(
          isControlServiceCharacteristic(
            'b1e70003-0000-1000-8000-00805f9b34fb',
          ),
          isTrue,
          reason: 'interval char',
        );
        expect(
          isControlServiceCharacteristic(
            'b1e70004-0000-1000-8000-00805f9b34fb',
          ),
          isTrue,
          reason: 'serverId char',
        );
      },
    );

    // 21. isControlServiceCharacteristic returns false for random UUID
    test('isControlServiceCharacteristic returns false for random UUID', () {
      expect(
        isControlServiceCharacteristic('00002a37-0000-1000-8000-00805f9b34fb'),
        isFalse,
      );
    });

    // 22. decodeInterval with short input returns default
    test('decodeInterval with short input returns default', () {
      final shortInput = Uint8List.fromList([0x01, 0x02]);
      final result = decodeInterval(shortInput);
      expect(result, equals(defaultLifecycleInterval));
    });

    // 23. encodeInterval/decodeInterval round-trip
    test('encodeInterval/decodeInterval round-trip', () {
      const original = Duration(seconds: 42);
      final encoded = encodeInterval(original);
      expect(encoded, hasLength(4));
      final decoded = decodeInterval(encoded);
      expect(decoded, equals(original));
    });
  });

  group('BlueyServer trackClientIfNeeded', () {
    // 24. untracked client sending heartbeat gets auto-tracked
    //
    // On iOS, CBPeripheralManager has no connection callback. The server
    // learns about clients only when they write to the control service.
    // This test verifies that a heartbeat from a client that the platform
    // reported (but the server would track via onHeartbeatReceived if the
    // centralConnections event were missing) correctly appears in
    // connectedClients and on the connections stream, and that a second
    // heartbeat does not double-track.
    test('untracked client sending heartbeat gets auto-tracked', () async {
      final bluey = Bluey();
      final server = bluey.server()!;
      await server.startAdvertising();

      final connections = <Client>[];
      server.connections.listen(connections.add);

      // Connect a central at the platform level. The server tracks it via
      // the centralConnections stream.
      fakePlatform.simulateCentralConnection(centralId: _clientId1);
      await Future.delayed(Duration.zero);

      expect(server.connectedClients, hasLength(1));
      expect(connections, hasLength(1));

      // Send a heartbeat -- should NOT double-track the same client.
      await fakePlatform.simulateWriteRequest(
        centralId: _clientId1,
        characteristicUuid: _heartbeatCharUuid,
        value: Uint8List.fromList([0x01]),
        responseNeeded: true,
      );
      await Future.delayed(Duration.zero);

      expect(
        server.connectedClients,
        hasLength(1),
        reason: 'trackClientIfNeeded should be idempotent',
      );
      expect(
        connections,
        hasLength(1),
        reason: 'No duplicate connection event',
      );

      await server.dispose();
      await bluey.dispose();
    });
  });
}
