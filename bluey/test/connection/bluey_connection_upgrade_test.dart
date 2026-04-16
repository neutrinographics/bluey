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

  group('BlueyConnection late upgrade via service change', () {
    test('auto-upgrades when services change and control service appears',
        () async {
      // Start with a non-Bluey peripheral (no control service)
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      ));

      expect(conn.isBlueyServer, isFalse);

      // Server restarts and registers the control service.
      // Update the simulated peripheral's services and fire service change.
      final serverId = ServerId.generate();
      fakePlatform.simulateServiceChange(
        'AA:BB:CC:DD:EE:01',
        newServices: [
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
        newCharacteristicValues: {
          'b1e70003-0000-1000-8000-00805f9b34fb':
              lifecycle.encodeInterval(const Duration(seconds: 10)),
          'b1e70004-0000-1000-8000-00805f9b34fb': serverId.toBytes(),
        },
      );

      // Give async handlers time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(conn.isBlueyServer, isTrue);
      expect(conn.serverId, equals(serverId));

      await conn.disconnect();
      await bluey.dispose();
    });

    test('does not re-upgrade when already a Bluey server', () async {
      final serverId = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: serverId,
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      ));

      expect(conn.isBlueyServer, isTrue);

      final states = <ConnectionState>[];
      conn.stateChanges.listen(states.add);

      // Fire service change -- should be ignored since already upgraded
      fakePlatform.simulateServiceChange('AA:BB:CC:DD:EE:01');
      await Future.delayed(const Duration(milliseconds: 100));

      // No extra connected event from a redundant upgrade
      expect(states.where((s) => s == ConnectionState.connected), isEmpty);

      await conn.disconnect();
      await bluey.dispose();
    });

    test('service change for different device is ignored', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      ));

      expect(conn.isBlueyServer, isFalse);

      // Fire service change for a different device
      fakePlatform.simulateServiceChange('XX:YY:ZZ:00:11:22');
      await Future.delayed(const Duration(milliseconds: 100));

      // Should still be a raw connection
      expect(conn.isBlueyServer, isFalse);

      await conn.disconnect();
      await bluey.dispose();
    });

    test('service change without control service does not upgrade', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Server',
      ));

      expect(conn.isBlueyServer, isFalse);

      // Fire service change with a regular service (not Bluey control)
      fakePlatform.simulateServiceChange(
        'AA:BB:CC:DD:EE:01',
        newServices: [
          const platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(conn.isBlueyServer, isFalse);

      await conn.disconnect();
      await bluey.dispose();
    });
  });

  group('BlueyConnection additional coverage', () {
    // 15. disconnect() is idempotent
    test('disconnect() is idempotent', () async {
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
      // Second disconnect should be a no-op -- no error.
      await conn.disconnect();

      await bluey.dispose();
    });

    // 16. isBlueyServer becomes false after disconnect
    test('isBlueyServer becomes false after disconnect', () async {
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

      await conn.disconnect();

      expect(conn.isBlueyServer, isFalse);

      await bluey.dispose();
    });

    // 17. services(cache: true) returns cached data without re-discovery
    test('services(cache: true) returns cached data without re-discovery',
        () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Regular',
        services: const [
          platform.PlatformService(
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

      // First call triggers discovery (which was already done during connect,
      // but this call with cache: false re-discovers).
      final services1 = await conn.services();

      // Second call with cache: true should return cached data.
      final services2 = await conn.services(cache: true);

      expect(services2, hasLength(services1.length));
      expect(
        services2.map((s) => s.uuid.toString()).toList(),
        equals(services1.map((s) => s.uuid.toString()).toList()),
      );

      await conn.disconnect();
      await bluey.dispose();
    });
  });
}
