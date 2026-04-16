import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/peer_connection.dart';
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

  group('PeerConnection', () {
    test('services() filters out the control service', () async {
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
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      final peer = PeerConnection(inner);

      final services = await peer.services();
      expect(
        services.any((s) => s.uuid.toString() == controlServiceUuid),
        isFalse,
        reason: 'Control service must be filtered',
      );
      expect(services, hasLength(1));

      await peer.disconnect();
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
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      await inner.services(); // populate cache
      final peer = PeerConnection(inner);

      expect(
        () => peer.service(UUID(controlServiceUuid)),
        throwsA(isA<ServiceNotFoundException>()),
      );

      await peer.disconnect();
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
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      final peer = PeerConnection(inner);

      expect(await peer.hasService(UUID(controlServiceUuid)), isFalse);

      await peer.disconnect();
      await bluey.dispose();
    });

    test('delegates non-service getters to the inner connection', () async {
      fakePlatform.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01');
      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      final peer = PeerConnection(inner);

      expect(peer.deviceId, equals(inner.deviceId));
      expect(peer.state, equals(inner.state));
      expect(peer.mtu, equals(inner.mtu));

      await peer.disconnect();
      await bluey.dispose();
    });
  });
}
