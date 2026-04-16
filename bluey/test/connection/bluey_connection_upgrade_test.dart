import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// Tests for BlueyConnection upgrade behavior.
///
/// After the merge of PeerConnection into BlueyConnection, a single
/// connection class handles both raw BLE and Bluey-protocol connections.
/// These tests verify the upgrade path and conditional behavior.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyConnection upgrade', () {
    test('new connection starts with isBlueyServer=false and serverId=null',
        () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Regular',
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
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Regular',
      ));

      expect(conn.isBlueyServer, isFalse);
      expect(conn.serverId, isNull);

      await conn.disconnect();
      await bluey.dispose();
    });

    test('auto-upgrades to Bluey when control service is present', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Bluey Server',
      ));

      expect(conn.isBlueyServer, isTrue);
      expect(conn.serverId, equals(id));

      await conn.disconnect();
      await bluey.dispose();
    });

    test('upgraded connection hides control service from services()', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Bluey Server',
      ));

      final services = await conn.services();
      expect(
        services.any((s) => lifecycle.isControlService(s.uuid.toString())),
        isFalse,
        reason: 'Control service should be hidden after upgrade',
      );

      await conn.disconnect();
      await bluey.dispose();
    });

    test('upgraded connection sends disconnect command on disconnect()', () {
      fakeAsync((async) {
        final id = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: id,
        );

        final bluey = Bluey();

        late Connection conn;
        bluey
            .connect(Device(
              id: UUID('00000000-0000-0000-0000-aabbccddee01'),
              address: 'AA:BB:CC:DD:EE:01',
              name: 'Test',
            ))
            .then((c) => conn = c);
        async.flushMicrotasks();

        expect(conn.isBlueyServer, isTrue);

        // Clear the write log so we only see writes from disconnect.
        fakePlatform.writeCharacteristicCalls.clear();

        conn.disconnect();
        async.flushMicrotasks();

        // The disconnect command [0x00] should have been written to the
        // heartbeat characteristic.
        final disconnectWrites =
            fakePlatform.writeCharacteristicCalls.where(
          (call) =>
              call.characteristicUuid == lifecycle.heartbeatCharUuid &&
              call.value.length == 1 &&
              call.value[0] == 0x00,
        );
        expect(disconnectWrites, isNotEmpty,
            reason: 'Should send disconnect command');

        bluey.dispose();
        async.flushMicrotasks();
      });
    });

    test('non-Bluey connection does not send disconnect command', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Regular',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Regular',
      ));

      await conn.disconnect();

      final disconnectWrites = fakePlatform.writeCharacteristicCalls.where(
        (w) => w.characteristicUuid == lifecycle.heartbeatCharUuid,
      );
      expect(disconnectWrites, isEmpty,
          reason: 'Non-Bluey connection should not write to heartbeat char');

      await bluey.dispose();
    });

    test('upgraded connection is in connected state', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Bluey Server',
      ));

      expect(conn.state, ConnectionState.connected);
      expect(conn.isBlueyServer, isTrue);

      await conn.disconnect();
      await bluey.dispose();
    });

    test('service(controlServiceUuid) throws after upgrade', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: lifecycle.controlServiceUuid,
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
        () => conn.service(UUID(lifecycle.controlServiceUuid)),
        throwsA(isA<ServiceNotFoundException>()),
      );

      await conn.disconnect();
      await bluey.dispose();
    });

    test('hasService(controlServiceUuid) returns false after upgrade',
        () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: lifecycle.controlServiceUuid,
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
        await conn.hasService(UUID(lifecycle.controlServiceUuid)),
        isFalse,
      );

      await conn.disconnect();
      await bluey.dispose();
    });
  });
}
