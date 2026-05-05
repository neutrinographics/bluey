import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  Device deviceFor(String address) => Device(
    id: UUID('00000000-0000-0000-0000-aabbccddee01'),
    address: address,
    name: 'Test Device',
  );

  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();

    fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');
  });

  tearDown(() async {
    await bluey.dispose();
  });

  group('Connection.maxWritePayload', () {
    test(
      'returns WritePayloadLimit wrapping platform value (without response)',
      () async {
        fakePlatform.setMaxWriteLengthOverride(
          TestDeviceIds.device1,
          withResponse: 100,
          withoutResponse: 182,
        );
        final connection = await bluey.connect(deviceFor(TestDeviceIds.device1));

        final limit = await connection.maxWritePayload(withResponse: false);

        expect(limit, isA<WritePayloadLimit>());
        expect(limit.value, equals(182));
      },
    );

    test(
      'returns WritePayloadLimit wrapping platform value (with response)',
      () async {
        fakePlatform.setMaxWriteLengthOverride(
          TestDeviceIds.device1,
          withResponse: 100,
          withoutResponse: 182,
        );
        final connection = await bluey.connect(deviceFor(TestDeviceIds.device1));

        final limit = await connection.maxWritePayload(withResponse: true);

        expect(limit.value, equals(100));
      },
    );

    test('falls back to MTU-3 when no override set', () async {
      // Default fake: connection.mtu = 23 -> maxWrite = 20.
      final connection = await bluey.connect(deviceFor(TestDeviceIds.device1));

      final limit = await connection.maxWritePayload(withResponse: false);

      expect(limit.value, equals(20));
    });
  });
}
