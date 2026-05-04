import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests verifying that the public API rewraps platform-interface timeout
/// exceptions into the domain-level [GattTimeoutException].
///
/// [GattOperationTimeoutException] is an internal contract type used by
/// [LifecycleClient]. Public callers of [BlueyConnection] and friends must
/// only ever see [BlueyException] subtypes so they can pattern-match
/// exhaustively.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  /// A minimal peripheral with one writable characteristic.
  const _serviceUuid = TestUuids.customService;
  const _charUuid = TestUuids.customChar1;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;

    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Timeout Test Device',
      services: [
        TestServiceBuilder(_serviceUuid).withWritable(_charUuid).build(),
      ],
    );

    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  group('BlueyConnection GATT timeout rewrap', () {
    test(
      'writeCharacteristic rewraps platform timeout into GattTimeoutException',
      () async {
        final device = Device(
          id: UUID('00000000-0000-0000-0000-aabbccddee01'),
          address: TestDeviceIds.device1,
          name: 'Timeout Test Device',
        );
        final conn = await bluey.connect(device);
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteTimeout = true;

        expect(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<GattTimeoutException>()),
        );

        fakePlatform.simulateWriteTimeout = false;
        await conn.disconnect();
      },
    );

    test('thrown GattTimeoutException is also a BlueyException', () async {
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Timeout Test Device',
      );
      final conn = await bluey.connect(device);
      final services = await conn.services();
      final svc = services.first;
      final char = svc.characteristic(UUID(_charUuid));

      fakePlatform.simulateWriteTimeout = true;

      expect(
        () => char.write(Uint8List.fromList([0x01])),
        throwsA(isA<BlueyException>()),
      );

      fakePlatform.simulateWriteTimeout = false;
      await conn.disconnect();
    });
  });
}
