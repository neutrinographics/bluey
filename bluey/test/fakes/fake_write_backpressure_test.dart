import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the write-without-response backpressure model
/// (audit R9 / NT-10).
///
/// On a real link, a write-without-response future resolves only when
/// the native layer hands the packet off (iOS gates on
/// `canSendWriteWithoutResponse`; see I339). With a saturation budget
/// set, the fake parks writes beyond the budget until the test drains
/// them — so domain behavior under a saturated link is testable.
void main() {
  const deviceId = TestDeviceIds.device1;

  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;
  late RemoteCharacteristic characteristic;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = await Bluey.create();
    fakePlatform.simulatePeripheral(
      id: deviceId,
      name: 'Backpressure Test',
      services: [
        TestServiceBuilder(TestUuids.heartRateService)
            .withCharacteristic(
              TestUuids.heartRateMeasurement,
              TestProperties.writeWithoutResponse,
            )
            .build(),
      ],
    );
    final connection = await bluey.connect(
      Device(address: const DeviceAddress(deviceId)),
    );
    characteristic =
        (await connection.services()).first.characteristics().first;
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('write-without-response backpressure', () {
    test('writes beyond the saturation budget park until drained, in FIFO '
        'order', () async {
      fakePlatform.setWriteWithoutResponseBudget(deviceId, 2);

      final completed = <int>[];
      for (var i = 0; i < 4; i++) {
        characteristic
            .write(Uint8List.fromList([i]), withResponse: false)
            .then((_) => completed.add(i));
      }
      await pumpEventQueue();

      expect(completed, equals([0, 1]),
          reason: 'the first two writes fit the budget');
      expect(fakePlatform.pendingWriteCount(deviceId), 2);

      fakePlatform.drainPendingWrites(deviceId, count: 1);
      await pumpEventQueue();
      expect(completed, equals([0, 1, 2]), reason: 'FIFO drain');

      fakePlatform.drainPendingWrites(deviceId);
      await pumpEventQueue();
      expect(completed, equals([0, 1, 2, 3]));
      expect(fakePlatform.pendingWriteCount(deviceId), 0);
    });

    test('writes WITH response are not subject to the budget', () async {
      fakePlatform.setWriteWithoutResponseBudget(deviceId, 0);

      // The characteristic is WWR-only, so use the platform surface
      // directly for the with-response variant.
      final handle = fakePlatform.handleFor(
        deviceId,
        TestUuids.heartRateMeasurement,
      )!;
      await fakePlatform.writeCharacteristic(
        deviceId,
        handle,
        Uint8List.fromList([0xAA]),
        true,
      );
      expect(fakePlatform.pendingWriteCount(deviceId), 0);
    });

    test('a disconnect drains parked writes with a disconnected error '
        '(the I315-shaped teardown)', () async {
      fakePlatform.setWriteWithoutResponseBudget(deviceId, 0);

      Object? error;
      characteristic
          .write(Uint8List.fromList([0x01]), withResponse: false)
          .catchError((Object e) {
        error = e;
      });
      await pumpEventQueue();
      expect(fakePlatform.pendingWriteCount(deviceId), 1);

      fakePlatform.simulateDisconnection(deviceId);
      await pumpEventQueue();

      expect(error, isA<BlueyException>());
      expect(fakePlatform.pendingWriteCount(deviceId), 0);
    });
  });
}
