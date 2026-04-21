import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests verifying that the public API rewraps platform-interface
/// disconnect exceptions into the domain-level [DisconnectedException]
/// with [DisconnectReason.linkLoss].
///
/// [platform.GattOperationDisconnectedException] is an internal contract
/// type emitted by the platform queue when a pending GATT op is drained
/// on link loss. Public callers of [BlueyConnection] and friends must
/// only ever see [BlueyException] subtypes so they can pattern-match
/// exhaustively.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  const _serviceUuid = TestUuids.customService;
  const _charUuid = TestUuids.customChar1;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;

    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Disconnect Test Device',
      services: [
        TestServiceBuilder(_serviceUuid).withWritable(_charUuid).build(),
      ],
    );

    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  final deviceUuid = UUID('00000000-0000-0000-0000-aabbccddee01');

  Device buildDevice() => Device(
    id: deviceUuid,
    address: TestDeviceIds.device1,
    name: 'Disconnect Test Device',
  );

  group('BlueyConnection GATT disconnect rewrap', () {
    test(
      'writeCharacteristic rewraps platform disconnect into DisconnectedException',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        expect(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<DisconnectedException>()),
        );

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'platform.GattOperationDisconnectedException does not leak past the public API',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isNot(isA<platform.GattOperationDisconnectedException>())),
        );

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'thrown DisconnectedException is also a BlueyException (sealed-hierarchy match)',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<BlueyException>()),
        );

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'DisconnectedException carries deviceId and DisconnectReason.linkLoss',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        try {
          await char.write(Uint8List.fromList([0x01]));
          fail('Expected DisconnectedException');
        } on DisconnectedException catch (e) {
          expect(e.deviceId, equals(deviceUuid));
          expect(e.reason, equals(DisconnectReason.linkLoss));
        }

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );
  });
}
