import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/peer/peer_discovery.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('PeerDiscovery.discover', () {
    test('returns empty when no Bluey servers advertising', () async {
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(ids, isEmpty);
    });

    test('returns one entry per unique ServerId', () async {
      final id1 = ServerId.generate();
      final id2 = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id1,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: id2,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids.toSet(), equals({id1, id2}));
    });

    test('deduplicates by ServerId', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: id,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids, hasLength(1));
    });
  });

  group('PeerDiscovery.connectTo', () {
    test('returns a Connection when a match is found', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final connection = await discovery.connectTo(
        id,
        scanTimeout: const Duration(milliseconds: 500),
      );
      expect(connection, isNotNull);
      // PeerDiscovery returns the BlueyConnection bare — services have
      // not been discovered yet, so it sits at `linked`. The caller
      // (BlueyPeer) then runs services() and upgrade() to promote.
      expect(connection.state, ConnectionState.linked);
      await connection.disconnect();
    });

    test('throws PeerNotFoundException when no match within timeout', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
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
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: wrongId,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: target,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final connection = await discovery.connectTo(
        target,
        scanTimeout: const Duration(milliseconds: 500),
      );
      // PeerDiscovery returns the BlueyConnection bare — services have
      // not been discovered yet, so it sits at `linked`. The caller
      // (BlueyPeer) then runs services() and upgrade() to promote.
      expect(connection.state, ConnectionState.linked);
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
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ],
        // No characteristicValues -- readCharacteristic will throw
        characteristicValues: {},
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );

      // Only the good server should be returned.
      expect(ids, hasLength(1));
      expect(ids.first, equals(goodId));
    });
  });

  // I055: peer discovery must filter the OS-level scan on the control
  // service UUID so probing is O(matches) rather than O(nearby devices).
  group('PeerDiscovery scan filter (I055)', () {
    test('discover scans with the control service UUID as filter', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      await discovery.discover(timeout: const Duration(milliseconds: 200));

      expect(
        fakePlatform.lastScanConfig?.serviceUuids,
        equals([lifecycle.controlServiceUuid]),
      );
    });

    test('connectTo scans with the control service UUID as filter', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      final connection = await discovery.connectTo(
        id,
        scanTimeout: const Duration(milliseconds: 500),
      );

      expect(
        fakePlatform.lastScanConfig?.serviceUuids,
        equals([lifecycle.controlServiceUuid]),
      );
      await connection.disconnect();
    });
  });

  // I056: probe-connect must use a short bounded timeout so a single
  // unresponsive candidate doesn't stall the whole discovery session.
  group('PeerDiscovery probe timeout (I056)', () {
    test('discover uses 3s default probe timeout when none provided', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        logger: testLogger(),
      );
      await discovery.discover(timeout: const Duration(milliseconds: 200));

      expect(fakePlatform.lastConnectConfig?.timeoutMs, equals(3000));
    });

    test(
      'discover threads custom probeTimeout through to platform connect',
      () async {
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: ServerId.generate(),
        );
        final discovery = PeerDiscovery(
          platformApi: fakePlatform,
          logger: testLogger(),
        );
        await discovery.discover(
          timeout: const Duration(milliseconds: 200),
          probeTimeout: const Duration(milliseconds: 750),
        );

        expect(fakePlatform.lastConnectConfig?.timeoutMs, equals(750));
      },
    );

    test(
      'connectTo threads custom probeTimeout through to platform connect',
      () async {
        final id = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: id,
        );
        final discovery = PeerDiscovery(
          platformApi: fakePlatform,
          logger: testLogger(),
        );
        final connection = await discovery.connectTo(
          id,
          scanTimeout: const Duration(milliseconds: 500),
          probeTimeout: const Duration(milliseconds: 1500),
        );

        expect(fakePlatform.lastConnectConfig?.timeoutMs, equals(1500));
        await connection.disconnect();
      },
    );
  });
}
