import 'package:bluey/bluey.dart';
import 'package:bluey/src/peer/peer_discovery.dart';
import 'package:bluey/src/peer/server_id.dart';
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

  group('PeerDiscovery.discover', () {
    test('returns empty when no Bluey servers advertising', () async {
      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(ids, isEmpty);
    });

    test('returns one entry per unique ServerId', () async {
      final id1 = ServerId.generate();
      final id2 = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id1);
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:02', serverId: id2);

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids.toSet(), equals({id1, id2}));
    });

    test('deduplicates by ServerId', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id);
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:02', serverId: id);

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids, hasLength(1));
    });
  });

  group('PeerDiscovery.connectTo', () {
    test('returns a Connection when a match is found', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id);

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final connection = await discovery.connectTo(
        id,
        scanTimeout: const Duration(milliseconds: 500),
      );
      expect(connection, isNotNull);
      expect(connection.state, ConnectionState.connected);
      await connection.disconnect();
    });

    test('throws PeerNotFoundException when no match within timeout', () async {
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: ServerId.generate());
      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final target = ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

      expect(
        () => discovery.connectTo(
          target,
          scanTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<PeerNotFoundException>()),
      );
    });

    test('skips non-matching candidates and finds the correct one', () async {
      final wrongId = ServerId.generate();
      final target = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: wrongId);
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:02', serverId: target);

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final connection = await discovery.connectTo(
        target,
        scanTimeout: const Duration(milliseconds: 500),
      );
      expect(connection.state, ConnectionState.connected);
      await connection.disconnect();
    });
  });
}
