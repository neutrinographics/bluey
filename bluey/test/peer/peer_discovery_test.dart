import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/peer/peer_discovery.dart';
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

  group('PeerDiscovery error handling', () {
    // 25. discover skips candidates that fail to connect
    test('discover skips candidates that fail to connect', () async {
      final goodId = ServerId.generate();
      final badId = ServerId.generate();

      // Set up two Bluey servers.
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: badId,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: goodId,
      );

      // Remove the first peripheral AFTER scanning will have discovered it
      // but BEFORE the probe connects. PeerDiscovery scans first, collects
      // all candidate addresses, then probes each one sequentially. We can
      // remove the peripheral so that connect() throws for that address.
      //
      // To achieve this timing, we wrap the call: first let scan collect
      // candidates (the fake emits them synchronously in the next microtask),
      // then remove the bad peripheral. However, since discover() is a
      // single await, we need a different approach: remove the peripheral
      // after the scan phase but before the probe phase.
      //
      // The simplest reliable approach: use a custom subclass or just remove
      // the peripheral synchronously before calling discover(). But then scan
      // won't find it. Instead, let scan find it, then by the time
      // _probeServerId tries to connect, the peripheral is gone.
      //
      // Actually, the fake's scan emits in a Future(() { ... }), so the
      // scan completes in the same microtask. The connect happens later.
      // We can't intercept between scan and connect in a single discover().
      //
      // Alternative approach: set up the bad peripheral without the serverId
      // characteristic value, so readCharacteristic throws during the probe.
      fakePlatform.removePeripheral('AA:BB:CC:DD:EE:01');
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Bad Server',
        serviceUuids: [lifecycle.controlServiceUuid],
        services: [
          platform.PlatformService(
            uuid: lifecycle.controlServiceUuid,
            isPrimary: true,
            characteristics: const [
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
        // No characteristicValues -- readCharacteristic will throw
        characteristicValues: {},
      );

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );

      // Only the good server should be returned.
      expect(ids, hasLength(1));
      expect(ids.first, equals(goodId));
    });
  });
}
