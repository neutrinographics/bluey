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

  group('bluey.discoverPeers', () {
    test('returns all nearby Bluey servers', () async {
      final id1 = ServerId.generate();
      final id2 = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id1);
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:02', serverId: id2);

      final bluey = Bluey();
      final peers = await bluey.discoverPeers(
        timeout: const Duration(milliseconds: 500),
      );
      expect(peers.map((p) => p.serverId).toSet(), equals({id1, id2}));
      await bluey.dispose();
    });

    test('returns empty list when no Bluey servers advertising', () async {
      final bluey = Bluey();
      final peers = await bluey.discoverPeers(
        timeout: const Duration(milliseconds: 200),
      );
      expect(peers, isEmpty);
      await bluey.dispose();
    });
  });

  group('bluey.peer', () {
    test('returns a BlueyPeer with the given serverId', () {
      final bluey = Bluey();
      final id = ServerId.generate();
      final peer = bluey.peer(id);
      expect(peer.serverId, equals(id));
      bluey.dispose();
    });

    test('connect() succeeds against a matching server', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id);

      final bluey = Bluey();
      final peer = bluey.peer(id);
      final conn = await peer.connect();
      expect(conn.state, ConnectionState.ready);
      await conn.disconnect();
      await bluey.dispose();
    });

    test('connect() throws PeerNotFoundException when no match', () async {
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: ServerId.generate());

      final bluey = Bluey();
      final peer = bluey.peer(
        ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
      );

      expect(
        () => peer.connect(scanTimeout: const Duration(milliseconds: 300)),
        throwsA(isA<PeerNotFoundException>()),
      );

      await bluey.dispose();
    });
  });

  group('bluey.connect auto-upgrade', () {
    test('auto-upgrades to peer connection for Bluey servers', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final bluey = Bluey();
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Bluey Server',
      );
      final conn = await bluey.connect(device);

      expect(conn.isBlueyServer, isTrue);
      expect(conn.serverId, equals(id));

      // The control service should be hidden
      final services = await conn.services();
      final controlServicePresent = services.any(
        (s) => s.uuid.toString().toLowerCase() == 'b1e70001-0000-1000-8000-00805f9b34fb',
      );
      expect(controlServicePresent, isFalse);

      await conn.disconnect();
      await bluey.dispose();
    });

    test('returns raw connection for non-Bluey devices', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Generic Device',
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
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Generic Device',
      );
      final conn = await bluey.connect(device);

      expect(conn.isBlueyServer, isFalse);
      expect(conn.serverId, isNull);

      await conn.disconnect();
      await bluey.dispose();
    });
  });
}
