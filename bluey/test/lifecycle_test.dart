import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/server_id.dart';
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

    test('heartbeat timeout fires disconnect after client opts into lifecycle',
        () {
      fakeAsync((async) {
        final bluey = Bluey();
        final server = bluey.server(
          lifecycleInterval: const Duration(seconds: 5),
        )!;

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
    });

    test('heartbeat resets timer', () {
      fakeAsync((async) {
        final bluey = Bluey();
        final server = bluey.server(
          lifecycleInterval: const Duration(seconds: 5),
        )!;

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
        final server = bluey.server(
          lifecycleInterval: const Duration(seconds: 5),
        )!;

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
        final server = bluey.server(
          lifecycleInterval: const Duration(seconds: 5),
        )!;

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
        final server = bluey.server(
          lifecycleInterval: const Duration(seconds: 5),
        )!;

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
        (c) =>
            c.uuid.toLowerCase() == 'b1e70004-0000-1000-8000-00805f9b34fb',
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
  });
}
