import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Load-bearing tests for I088: duplicate characteristic UUIDs across two
/// different services must route by handle, not by UUID.
///
/// Without handle-based routing, a read or write on one service's char would
/// be answered by the other service's char (whichever was discovered first
/// in the lookup table). The handle-identity rewrite (D.3–D.8) eliminates
/// this ambiguity by giving every (service, char) attribute a distinct
/// handle and threading that handle through every GATT op.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  // Two different service UUIDs, but they share a single char UUID.
  // This is the I088 shape: same charUuid under two different services.
  const serviceA = '0000aaaa-0000-1000-8000-00805f9b34fb';
  const serviceB = '0000bbbb-0000-1000-8000-00805f9b34fb';
  const sharedCharUuid = '0000cccc-0000-1000-8000-00805f9b34fb';

  Future<Connection> connectAndDiscover({
    Map<int, Uint8List> valuesByHandle = const {},
  }) async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Duplicate-UUID Peripheral',
      services: const [
        platform.PlatformService(
          uuid: serviceA,
          isPrimary: true,
          characteristics: [
            platform.PlatformCharacteristic(
              uuid: sharedCharUuid,
              properties: TestProperties.readWrite,
              descriptors: [],
            ),
          ],
          includedServices: [],
        ),
        platform.PlatformService(
          uuid: serviceB,
          isPrimary: true,
          characteristics: [
            platform.PlatformCharacteristic(
              uuid: sharedCharUuid,
              properties: TestProperties.readWrite,
              descriptors: [],
            ),
          ],
          includedServices: [],
        ),
      ],
    );

    final bluey = Bluey();
    final device = await scanFirstDevice(bluey);
    final connection = await bluey.connect(device);

    // Trigger discovery so the fake mints handles, then seed per-handle
    // backing values for duplicate-UUID chars.
    final services = await connection.services();
    valuesByHandle.forEach((handle, value) {
      fakePlatform.setCharacteristicValueByHandle(
        TestDeviceIds.device1,
        handle,
        value,
      );
    });
    // Discard `services` — the test will call `connection.services()` again.
    services.length;
    return connection;
  }

  test(
    'reads route to the correct char by handle on duplicate-UUID services',
    () async {
      // Connect first to discover handles, then seed values by handle.
      final connection = await connectAndDiscover();
      final services = await connection.services();
      final charA = services[0].characteristics.single;
      final charB = services[1].characteristics.single;

      fakePlatform.setCharacteristicValueByHandle(
        TestDeviceIds.device1,
        charA.handle.value,
        Uint8List.fromList([0x0A, 0x0A]),
      );
      fakePlatform.setCharacteristicValueByHandle(
        TestDeviceIds.device1,
        charB.handle.value,
        Uint8List.fromList([0x0B, 0x0B]),
      );

      final readA = await charA.read();
      final readB = await charB.read();

      expect(readA, equals(Uint8List.fromList([0x0A, 0x0A])));
      expect(readB, equals(Uint8List.fromList([0x0B, 0x0B])));
    },
  );

  test(
    'writes route to the correct char by handle on duplicate-UUID services',
    () async {
      final connection = await connectAndDiscover();
      final services = await connection.services();
      final charA = services[0].characteristics.single;
      final charB = services[1].characteristics.single;

      await charA.write(Uint8List.fromList([0xA1]));
      await charB.write(Uint8List.fromList([0xB2]));

      // Read each char back via its own handle and confirm the values
      // landed in the right places.
      final backA = await charA.read();
      final backB = await charB.read();

      expect(backA, equals(Uint8List.fromList([0xA1])));
      expect(backB, equals(Uint8List.fromList([0xB2])));
    },
  );

  test(
    'RemoteCharacteristic.handle distinguishes two same-UUID chars',
    () async {
      final connection = await connectAndDiscover();
      final services = await connection.services();
      final charA = services[0].characteristics.single;
      final charB = services[1].characteristics.single;

      expect(charA.uuid, equals(charB.uuid));
      expect(charA.handle, isNot(equals(charB.handle)));
    },
  );
}
