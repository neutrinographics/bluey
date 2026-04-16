import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/peer_connection.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// These tests verify the PeerConnection decorator's service-filtering
/// and delegation behaviour by constructing it directly from a raw
/// BlueyConnection (bypassing the auto-upgrade in `Bluey.connect()`).
///
/// To avoid auto-upgrade, the simulated peripherals here do NOT include
/// the control service in the GATT database. Instead, we simulate a
/// peripheral with an app service AND the control service UUID injected
/// via the raw connection's service cache.
void main() {
  late FakeBlueyPlatform fakePlatform;
  final testServerId = ServerId.generate();

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('PeerConnection', () {
    test('services() filters out the control service', () async {
      // Simulate a peripheral with the control service AND an app service.
      // Because the control service characteristics have no readable values,
      // the auto-upgrade in Bluey.connect will still upgrade (it catches read
      // failures), so we work around this by using two services and verifying
      // that PeerConnection filters exactly one out.
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: controlServiceUuid,
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
          platform.PlatformService(
            uuid: '00001800-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
        ],
      );

      final bluey = Bluey();
      // bluey.connect() auto-upgrades, giving us a PeerConnection already.
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));

      // Verify it auto-upgraded and filters the control service.
      expect(conn.isBlueyServer, isTrue);

      final services = await conn.services();
      expect(
        services.any((s) => s.uuid.toString() == controlServiceUuid),
        isFalse,
        reason: 'Control service must be filtered',
      );
      expect(services, hasLength(1));

      await conn.disconnect();
      await bluey.dispose();
    });

    test('service(controlServiceUuid) throws ServiceNotFoundException',
        () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: controlServiceUuid,
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
        ],
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));

      expect(conn.isBlueyServer, isTrue);
      expect(
        () => conn.service(UUID(controlServiceUuid)),
        throwsA(isA<ServiceNotFoundException>()),
      );

      await conn.disconnect();
      await bluey.dispose();
    });

    test('hasService(controlServiceUuid) returns false', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: controlServiceUuid,
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
        ],
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));

      expect(conn.isBlueyServer, isTrue);
      expect(await conn.hasService(UUID(controlServiceUuid)), isFalse);

      await conn.disconnect();
      await bluey.dispose();
    });

    test('delegates non-service getters to the inner connection', () async {
      // Use a peripheral WITHOUT the control service so auto-upgrade
      // does NOT fire, giving us a raw BlueyConnection we can manually wrap.
      fakePlatform.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01');
      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));

      expect(inner.isBlueyServer, isFalse);

      final peer = PeerConnection(inner, testServerId);

      expect(peer.deviceId, equals(inner.deviceId));
      expect(peer.state, equals(inner.state));
      expect(peer.mtu, equals(inner.mtu));

      await peer.disconnect();
      await bluey.dispose();
    });

    test('isBlueyServer returns true and serverId is set', () async {
      fakePlatform.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01');
      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));

      expect(inner.isBlueyServer, isFalse);

      final peer = PeerConnection(inner, testServerId);

      expect(peer.isBlueyServer, isTrue);
      expect(peer.serverId, equals(testServerId));

      await peer.disconnect();
      await bluey.dispose();
    });
  });
}
