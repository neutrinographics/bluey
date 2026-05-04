import 'dart:typed_data';

import 'package:bluey/bluey.dart';
// ignore: implementation_imports
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

const _heartbeatCharUuid = 'b1e70002-0000-1000-8000-00805f9b34fb';
const _serverIdCharUuid = 'b1e70004-0000-1000-8000-00805f9b34fb';
const _clientId = '00000000-0000-0000-0000-000000000001';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    BlueyPlatform.instance = fakePlatform;
  });

  group('Server-side identity reception (peerConnections)', () {
    test('emits PeerClient carrying the central\'s ServerId on first valid '
        'heartbeat', () async {
      final localId = ServerId('11111111-1111-4111-8111-111111111111');
      final remoteId = ServerId('22222222-2222-4222-8222-222222222222');
      final bluey = Bluey(localIdentity: localId);
      final server = bluey.server()!;
      await server.startAdvertising();

      final emissions = <PeerClient>[];
      server.peerConnections.listen(emissions.add);

      fakePlatform.simulateCentralConnection(centralId: _clientId);
      await Future<void>.delayed(Duration.zero);

      await fakePlatform.simulateWriteRequest(
        centralId: _clientId,
        characteristicUuid: _heartbeatCharUuid,
        value: heartbeatPayloadFrom(remoteId),
        responseNeeded: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, hasLength(1));
      expect(emissions.single.serverId, equals(remoteId));

      await server.dispose();
      await bluey.dispose();
    });

    test('rejects malformed heartbeat writes — no PeerClient emission, '
        'no client tracking', () async {
      final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
      final server = bluey.server()!;
      await server.startAdvertising();

      final emissions = <PeerClient>[];
      server.peerConnections.listen(emissions.add);

      fakePlatform.simulateCentralConnection(centralId: _clientId);
      await Future<void>.delayed(Duration.zero);

      // Legacy 1-byte payload — was valid pre-cutover, now rejected.
      await fakePlatform.simulateWriteRequest(
        centralId: _clientId,
        characteristicUuid: _heartbeatCharUuid,
        value: Uint8List.fromList([0x01]),
        responseNeeded: true,
      );
      // Wrong-marker payload of correct length.
      final junk = Uint8List(18);
      junk[0] = lifecycle.protocolVersion;
      junk[1] = 0x77;
      await fakePlatform.simulateWriteRequest(
        centralId: _clientId,
        characteristicUuid: _heartbeatCharUuid,
        value: junk,
        responseNeeded: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        emissions,
        isEmpty,
        reason: 'malformed/legacy writes must not promote to a PeerClient',
      );

      await server.dispose();
      await bluey.dispose();
    });

    test(
      'rejects unknown protocol versions — no PeerClient emission',
      () async {
        final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
        final server = bluey.server()!;
        await server.startAdvertising();

        final emissions = <PeerClient>[];
        server.peerConnections.listen(emissions.add);

        fakePlatform.simulateCentralConnection(centralId: _clientId);
        await Future<void>.delayed(Duration.zero);

        // Future-version payload — version 0xFE.
        final futureVersion = Uint8List(18);
        futureVersion[0] = 0xFE;
        futureVersion[1] = 0x01;
        await fakePlatform.simulateWriteRequest(
          centralId: _clientId,
          characteristicUuid: _heartbeatCharUuid,
          value: futureVersion,
          responseNeeded: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(emissions, isEmpty);

        await server.dispose();
        await bluey.dispose();
      },
    );

    test('PeerClient stream emits exactly once per identification, even after '
        'many heartbeats', () async {
      final remoteId = TestServerIds.remoteIdentity;
      final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
      final server = bluey.server()!;
      await server.startAdvertising();

      final emissions = <PeerClient>[];
      server.peerConnections.listen(emissions.add);

      fakePlatform.simulateCentralConnection(centralId: _clientId);
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 5; i++) {
        await fakePlatform.simulateWriteRequest(
          centralId: _clientId,
          characteristicUuid: _heartbeatCharUuid,
          value: heartbeatPayloadFrom(remoteId),
          responseNeeded: true,
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(emissions, hasLength(1));
      expect(emissions.single.serverId, equals(remoteId));

      await server.dispose();
      await bluey.dispose();
    });
  });

  group('Server-side advertised identity', () {
    test(
      'serverId read response is versioned (17 bytes, leading 0x01)',
      () async {
        final id = ServerId('cccccccc-cccc-4ccc-cccc-cccccccccccc');
        final bluey = Bluey(localIdentity: id);
        final server = bluey.server()!;
        await server.startAdvertising();

        fakePlatform.simulateCentralConnection(centralId: _clientId);
        await Future<void>.delayed(Duration.zero);

        fakePlatform.simulateReadRequest(
          centralId: _clientId,
          characteristicUuid: _serverIdCharUuid,
        );
        await Future<void>.delayed(Duration.zero);

        final call = fakePlatform.respondReadCalls.last;
        final value = call.value!;
        expect(value, hasLength(17));
        expect(value[0], equals(lifecycle.protocolVersion));
        expect(
          lifecycle.lifecycleCodec.decodeAdvertisedIdentity(value),
          equals(id),
        );

        await server.dispose();
        await bluey.dispose();
      },
    );
  });

  group('Client-side identity announcement', () {
    test('BlueyPeer.connect() heartbeats announce the local Bluey instance\'s '
        'identity', () async {
      final localId = ServerId('33333333-3333-4333-8333-333333333333');
      final remoteId = ServerId('44444444-4444-4444-8444-444444444444');
      const address = 'AA:BB:CC:DD:EE:01';
      fakePlatform.simulateBlueyServer(address: address, serverId: remoteId);

      final bluey = Bluey(localIdentity: localId);
      final peer = bluey.peer(remoteId);
      final peerConn = await peer.connect();

      // Wait for the initial heartbeat write triggered during connect.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
        (w) =>
            w.deviceId == address &&
            w.characteristicUuid.toLowerCase() == _heartbeatCharUuid,
      );
      expect(heartbeatWrites, isNotEmpty);
      for (final w in heartbeatWrites) {
        final decoded = lifecycle.lifecycleCodec.decodeMessage(w.value);
        expect(
          decoded.senderId,
          equals(localId),
          reason: 'every heartbeat carries the local identity',
        );
      }

      await peerConn.disconnect();
      await bluey.dispose();
    });

    test('PeerConnection.disconnect() courtesy write carries the local '
        'identity', () async {
      final localId = ServerId('55555555-5555-4555-8555-555555555555');
      final remoteId = ServerId('66666666-6666-4666-8666-666666666666');
      const address = 'AA:BB:CC:DD:EE:02';
      fakePlatform.simulateBlueyServer(address: address, serverId: remoteId);

      final bluey = Bluey(localIdentity: localId);
      final peer = bluey.peer(remoteId);
      final peerConn = await peer.connect();
      await Future<void>.delayed(Duration.zero);

      final before = fakePlatform.writeCharacteristicCalls.length;
      await peerConn.disconnect();

      final disconnectWrites =
          fakePlatform.writeCharacteristicCalls
              .skip(before)
              .where(
                (w) => w.characteristicUuid.toLowerCase() == _heartbeatCharUuid,
              )
              .toList();
      expect(disconnectWrites, isNotEmpty);
      final decoded = lifecycle.lifecycleCodec.decodeMessage(
        disconnectWrites.first.value,
      );
      expect(decoded, isA<lifecycle.CourtesyDisconnect>());
      expect(decoded.senderId, equals(localId));

      await bluey.dispose();
    });
  });

  group('Bluey.peer / discoverPeers identity gating', () {
    test('peer() throws when localIdentity is null', () {
      final bluey = Bluey();
      expect(
        () => bluey.peer(TestServerIds.remoteIdentity),
        throwsA(isA<LocalIdentityRequiredException>()),
      );
      bluey.dispose();
    });

    test('discoverPeers() throws when localIdentity is null', () async {
      final bluey = Bluey();
      await expectLater(
        bluey.discoverPeers(),
        throwsA(isA<LocalIdentityRequiredException>()),
      );
      await bluey.dispose();
    });

    test(
      'tryUpgrade throws LocalIdentityRequiredException when localIdentity is null',
      () async {
        // Construct a connection through the non-peer path; tryUpgrade is
        // the upgrade hook and now requires identity to install lifecycle.
        const address = 'AA:BB:CC:DD:EE:01';
        fakePlatform.simulateBlueyServer(
          address: address,
          serverId: TestServerIds.remoteIdentity,
        );

        final bluey = Bluey();
        final scanner = bluey.scanner();
        final result = await scanner.scan().first;
        scanner.dispose();
        final connection = await bluey.connect(result.device);

        await expectLater(
          bluey.tryUpgrade(connection),
          throwsA(isA<LocalIdentityRequiredException>()),
        );

        await connection.disconnect();
        await bluey.dispose();
      },
    );
  });
}
