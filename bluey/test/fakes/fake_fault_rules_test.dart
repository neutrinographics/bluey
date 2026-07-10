import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the fault-rule queue (audit R2 / NT-5, NT-13).
///
/// `enqueueFault` scripts fault injection: rules are FIFO, target an
/// operation — optionally narrowed to a device and characteristic —
/// and fire a bounded number of times ("fail twice, then succeed") or
/// until cleared. This is the general mechanism behind flaky-link
/// scenarios; the older `simulateWrite*` booleans remain as sugar.
void main() {
  const deviceId = TestDeviceIds.device1;

  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  Future<Connection> connectTo(String id) async {
    return bluey.connect(Device(address: DeviceAddress(id)));
  }

  void simulateDevice(String id) {
    fakePlatform.simulatePeripheral(
      id: id,
      name: 'Fault Test $id',
      services: [
        TestServiceBuilder(TestUuids.heartRateService)
            .withReadWrite(TestUuids.heartRateMeasurement)
            .withReadWrite(TestUuids.bodySensorLocation)
            .build(),
      ],
      characteristicValues: {
        TestUuids.heartRateMeasurement: Uint8List.fromList([0x01]),
        TestUuids.bodySensorLocation: Uint8List.fromList([0x02]),
      },
    );
  }

  setUp(() async {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = await Bluey.create();
    simulateDevice(deviceId);
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('fail-N-then-succeed (flaky link)', () {
    test('a write rule with times: 2 fails twice then the link recovers',
        () async {
      final connection = await connectTo(deviceId);
      final services = await connection.services();
      final characteristic = services.first.characteristics().first;

      fakePlatform.enqueueFault(
        FakeOp.writeCharacteristic,
        const platform.GattOperationTimeoutException('writeCharacteristic'),
        times: 2,
      );

      final payload = Uint8List.fromList([0xAA]);
      await expectLater(
        characteristic.write(payload),
        throwsA(isA<GattTimeoutException>()),
      );
      await expectLater(
        characteristic.write(payload),
        throwsA(isA<GattTimeoutException>()),
      );

      // Third attempt: the rule is exhausted, the write lands.
      await characteristic.write(payload);
      expect(await characteristic.read(), equals(payload));
    });

    test('times defaults to 1 (one-shot)', () async {
      final connection = await connectTo(deviceId);
      final services = await connection.services();
      final characteristic = services.first.characteristics().first;

      fakePlatform.enqueueFault(
        FakeOp.readCharacteristic,
        const platform.GattOperationTimeoutException('readCharacteristic'),
      );

      await expectLater(
        characteristic.read(),
        throwsA(isA<GattTimeoutException>()),
      );
      expect(await characteristic.read(), equals([0x01]));
    });

    test('times: null keeps failing until clearFaults()', () async {
      final connection = await connectTo(deviceId);
      final services = await connection.services();
      final characteristic = services.first.characteristics().first;

      fakePlatform.enqueueFault(
        FakeOp.readCharacteristic,
        const platform.GattOperationTimeoutException('readCharacteristic'),
        times: null,
      );

      for (var i = 0; i < 5; i++) {
        await expectLater(
          characteristic.read(),
          throwsA(isA<GattTimeoutException>()),
        );
      }

      fakePlatform.clearFaults();
      expect(await characteristic.read(), equals([0x01]));
    });
  });

  group('targeting', () {
    test('a device-scoped rule leaves other devices unaffected', () async {
      const otherId = TestDeviceIds.device2;
      simulateDevice(otherId);

      final faulted = await connectTo(deviceId);
      final healthy = await connectTo(otherId);
      final faultedChar =
          (await faulted.services()).first.characteristics().first;
      final healthyChar =
          (await healthy.services()).first.characteristics().first;

      fakePlatform.enqueueFault(
        FakeOp.writeCharacteristic,
        const platform.GattOperationDisconnectedException(
          'writeCharacteristic',
        ),
        deviceId: deviceId,
        times: null,
      );

      await healthyChar.write(Uint8List.fromList([0xBB]));
      await expectLater(
        faultedChar.write(Uint8List.fromList([0xBB])),
        throwsA(isA<DisconnectedException>()),
      );
    });

    test('a characteristic-scoped rule leaves sibling characteristics '
        'unaffected', () async {
      final connection = await connectTo(deviceId);
      final service = (await connection.services()).first;
      final faultedChar = service
          .characteristics(uuid: UUID(TestUuids.heartRateMeasurement))
          .first;
      final healthyChar = service
          .characteristics(uuid: UUID(TestUuids.bodySensorLocation))
          .first;

      fakePlatform.enqueueFault(
        FakeOp.readCharacteristic,
        const platform.GattOperationTimeoutException('readCharacteristic'),
        characteristicUuid: TestUuids.heartRateMeasurement,
        times: null,
      );

      expect(await healthyChar.read(), equals([0x02]));
      await expectLater(
        faultedChar.read(),
        throwsA(isA<GattTimeoutException>()),
      );
    });
  });

  group('ordering and lifecycle', () {
    test('rules for the same operation fire in FIFO order', () async {
      final connection = await connectTo(deviceId);
      final characteristic =
          (await connection.services()).first.characteristics().first;

      fakePlatform.enqueueFault(
        FakeOp.writeCharacteristic,
        const platform.GattOperationTimeoutException('writeCharacteristic'),
      );
      fakePlatform.enqueueFault(
        FakeOp.writeCharacteristic,
        const platform.GattOperationStatusFailedException(
          'writeCharacteristic',
          133,
        ),
      );

      final payload = Uint8List.fromList([0xCC]);
      await expectLater(
        characteristic.write(payload),
        throwsA(isA<GattTimeoutException>()),
      );
      await expectLater(
        characteristic.write(payload),
        throwsA(
          isA<GattOperationFailedException>().having(
            (e) => e.status,
            'status',
            133,
          ),
        ),
      );
      await characteristic.write(payload);
    });

    test('the thrown error is exactly the enqueued object', () async {
      final connection = await connectTo(deviceId);
      final characteristic =
          (await connection.services()).first.characteristics().first;

      final marker = StateError('marker error');
      fakePlatform.enqueueFault(FakeOp.readCharacteristic, marker);

      await expectLater(
        characteristic.read(),
        throwsA(
          isA<BlueyPlatformException>().having(
            (e) => e.cause,
            'cause',
            same(marker),
          ),
        ),
      );
    });
  });

  group('operation coverage', () {
    test('connect rules target the connect phase per device', () async {
      fakePlatform.enqueueFault(
        FakeOp.connect,
        const platform.PlatformConnectFailedException(
          platform.PlatformConnectFailureReason.notConnectable,
        ),
        deviceId: deviceId,
      );

      await expectLater(
        connectTo(deviceId),
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.reason,
            'reason',
            ConnectionFailureReason.deviceNotConnectable,
          ),
        ),
      );
      // One-shot: retry connects.
      final connection = await connectTo(deviceId);
      expect(connection.state, ConnectionState.linked);
    });

    test('discoverServices rules fail service discovery', () async {
      final connection = await connectTo(deviceId);

      fakePlatform.enqueueFault(
        FakeOp.discoverServices,
        const platform.GattOperationTimeoutException('discoverServices'),
      );

      await expectLater(
        connection.services(),
        throwsA(isA<GattTimeoutException>()),
      );
    });

    test('remaining wrapped ops honor rules (direct fake calls)', () async {
      await connectTo(deviceId);
      final handle = fakePlatform.handleFor(
        deviceId,
        TestUuids.heartRateMeasurement,
      )!;

      const err = platform.GattOperationTimeoutException('op');

      fakePlatform.enqueueFault(FakeOp.setNotification, err);
      await expectLater(
        fakePlatform.setNotification(deviceId, handle, true),
        throwsA(same(err)),
      );

      fakePlatform.enqueueFault(FakeOp.readDescriptor, err);
      await expectLater(
        fakePlatform.readDescriptor(deviceId, handle, 1),
        throwsA(same(err)),
      );

      fakePlatform.enqueueFault(FakeOp.writeDescriptor, err);
      await expectLater(
        fakePlatform.writeDescriptor(deviceId, handle, 1, Uint8List(0)),
        throwsA(same(err)),
      );

      fakePlatform.enqueueFault(FakeOp.requestMtu, err);
      await expectLater(
        fakePlatform.requestMtu(deviceId, 185),
        throwsA(same(err)),
      );

      fakePlatform.enqueueFault(FakeOp.readRssi, err);
      await expectLater(
        fakePlatform.readRssi(deviceId),
        throwsA(same(err)),
      );
    });
  });
}
