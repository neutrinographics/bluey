import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
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

  /// Simulates a Bluey server advertising the control service with a
  /// pre-populated serverId characteristic.
  String simulateBlueyServer(
    FakeBlueyPlatform fakePlatform,
    ServerId id, {
    String? addressSuffix,
  }) {
    final address = 'AA:BB:CC:DD:EE:${addressSuffix ?? '01'}';
    fakePlatform.simulatePeripheral(
      id: address,
      name: 'Bluey Server',
      serviceUuids: [lifecycle.controlServiceUuid],
      services: [
        platform.PlatformService(
          uuid: lifecycle.controlServiceUuid,
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
        'b1e70004-0000-1000-8000-00805f9b34fb': id.toBytes(),
      },
    );
    return address;
  }

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
      simulateBlueyServer(fakePlatform, id1, addressSuffix: '01');
      simulateBlueyServer(fakePlatform, id2, addressSuffix: '02');

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids.toSet(), equals({id1, id2}));
    });

    test('deduplicates by ServerId', () async {
      final id = ServerId.generate();
      simulateBlueyServer(fakePlatform, id, addressSuffix: '01');
      simulateBlueyServer(fakePlatform, id, addressSuffix: '02');

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
      simulateBlueyServer(fakePlatform, id);

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
      simulateBlueyServer(fakePlatform, ServerId.generate());
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
      simulateBlueyServer(fakePlatform, wrongId, addressSuffix: '01');
      simulateBlueyServer(fakePlatform, target, addressSuffix: '02');

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
