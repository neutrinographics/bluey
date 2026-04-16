import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

String _simulateBlueyServer(
  FakeBlueyPlatform fakePlatform,
  ServerId id, {
  String? addressSuffix,
  Duration intervalValue = const Duration(seconds: 10),
}) {
  final address = 'AA:BB:CC:DD:EE:${addressSuffix ?? '01'}';
  fakePlatform.simulatePeripheral(
    id: address,
    name: 'Bluey Server',
    serviceUuids: [controlServiceUuid],
    services: [
      platform.PlatformService(
        uuid: controlServiceUuid,
        isPrimary: true,
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: false,
              canWrite: true,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
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
    characteristicValues: {
      'b1e70003-0000-1000-8000-00805f9b34fb': encodeInterval(intervalValue),
      'b1e70004-0000-1000-8000-00805f9b34fb': id.toBytes(),
    },
  );
  return address;
}

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
      _simulateBlueyServer(fakePlatform, id1, addressSuffix: '01');
      _simulateBlueyServer(fakePlatform, id2, addressSuffix: '02');

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
      _simulateBlueyServer(fakePlatform, id);

      final bluey = Bluey();
      final peer = bluey.peer(id);
      final conn = await peer.connect();
      expect(conn.state, ConnectionState.connected);
      await conn.disconnect();
      await bluey.dispose();
    });

    test('connect() throws PeerNotFoundException when no match', () async {
      _simulateBlueyServer(fakePlatform, ServerId.generate());

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
}
