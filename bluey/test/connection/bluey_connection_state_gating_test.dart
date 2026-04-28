import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// I002 — public GATT-op methods on `BlueyConnection`,
/// `BlueyRemoteCharacteristic`, and `BlueyRemoteDescriptor` must throw
/// the domain-typed [DisconnectedException] when invoked on a
/// disconnected connection, instead of letting a raw `PlatformException`
/// or other internal error escape.
///
/// Pre-flight: when `_state` is not in {linked, ready}, every public
/// op throws [DisconnectedException] with [DisconnectReason.unknown].
/// Allows callers to pattern-match on Bluey's exception hierarchy
/// rather than the platform's.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  Future<({Connection connection, RemoteCharacteristic char, RemoteDescriptor desc})>
      establishWithChar() async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Sensor',
      services: [
        const platform.PlatformService(
          uuid: '0000180d-0000-1000-8000-00805f9b34fb',
          isPrimary: true,
          characteristics: [
            platform.PlatformCharacteristic(
              uuid: '00002a37-0000-1000-8000-00805f9b34fb',
              properties: platform.PlatformCharacteristicProperties(
                canRead: true,
                canWrite: true,
                canWriteWithoutResponse: false,
                canNotify: true,
                canIndicate: false,
              ),
              descriptors: [
                platform.PlatformDescriptor(
                  uuid: '00002902-0000-1000-8000-00805f9b34fb',
                  handle: 0,
                ),
              ],
              handle: 0,
            ),
          ],
          includedServices: [],
        ),
      ],
      characteristicValues: {
        '00002a37-0000-1000-8000-00805f9b34fb': Uint8List.fromList([0x01]),
      },
    );

    final device = Device(
      id: UUID('00000000-0000-0000-0000-aabbccddee01'),
      address: TestDeviceIds.device1,
      name: 'Sensor',
    );
    final connection = await bluey.connect(device);
    final services = await connection.services();
    final char = services.first.characteristics().first;
    final desc = char.descriptors().first;
    return (connection: connection, char: char, desc: desc);
  }

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() {
    bluey.dispose();
  });

  group('BlueyConnection state gating (I002)', () {
    test('requestMtu after disconnect throws DisconnectedException', () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.connection.requestMtu(Mtu(247, capabilities: platform.Capabilities.android)),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('readRssi after disconnect throws DisconnectedException', () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.connection.readRssi(),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('services after disconnect throws DisconnectedException', () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.connection.services(),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('characteristic.read after disconnect throws DisconnectedException',
        () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.char.read(),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('characteristic.write after disconnect throws DisconnectedException',
        () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.char.write(Uint8List.fromList([0x42])),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('characteristic.notifications after disconnect throws DisconnectedException',
        () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      // Synchronous throw on getter access (matches the existing
      // OperationNotSupportedException pattern when the characteristic
      // doesn't support notify).
      expect(
        () => ctx.char.notifications,
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('descriptor.read after disconnect throws DisconnectedException',
        () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.desc.read(),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('descriptor.write after disconnect throws DisconnectedException',
        () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      await expectLater(
        ctx.desc.write(Uint8List.fromList([0x01, 0x00])),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('DisconnectedException carries the connection deviceId and unknown reason',
        () async {
      final ctx = await establishWithChar();
      await ctx.connection.disconnect();

      try {
        await ctx.connection.requestMtu(Mtu(247, capabilities: platform.Capabilities.android));
        fail('expected DisconnectedException');
      } on DisconnectedException catch (e) {
        expect(e.deviceId, ctx.connection.deviceId);
        expect(e.reason, DisconnectReason.unknown);
      }
    });

    test('healthy connection allows GATT ops (regression guard)', () async {
      final ctx = await establishWithChar();

      // None of these should throw.
      await ctx.connection.requestMtu(Mtu(247, capabilities: platform.Capabilities.android));
      await ctx.char.read();
      await ctx.char.write(Uint8List.fromList([0x01]));

      // Notifications getter must not throw on a healthy connection.
      expect(() => ctx.char.notifications, returnsNormally);

      await ctx.connection.disconnect();
    });
  });
}
