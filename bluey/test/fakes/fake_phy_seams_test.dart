import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

typedef _Pair = ({PlatformPhy tx, PlatformPhy rx});

/// Contract tests for the seams that make the fake's radio report and
/// refuse PHYs.
void main() {
  const deviceId = TestDeviceIds.device1;
  const fast = (tx: PlatformPhy.le2m, rx: PlatformPhy.leCoded);
  late FakeBlueyPlatform fake;

  setUp(() => fake = FakeBlueyPlatform()..simulatePeripheral(id: deviceId));

  tearDown(() => fake.dispose());

  test('reads le1m both ways until a PHY is simulated', () async {
    // act
    final pair = await fake.getPhy(deviceId);

    // assert
    expect(pair, (tx: PlatformPhy.le1m, rx: PlatformPhy.le1m));
  });

  test('a simulated PHY is read and reported', () async {
    // arrange
    final reported = <_Pair>[];
    fake.phyStream(deviceId).listen(reported.add);

    // act
    fake.simulatePhy(deviceId, tx: PlatformPhy.le2m, rx: PlatformPhy.le2m);
    fake.simulatePhy(deviceId, tx: fast.tx, rx: fast.rx);
    await pumpEventQueue();

    // assert
    expect(reported, [(tx: PlatformPhy.le2m, rx: PlatformPhy.le2m), fast]);
    expect(await fake.getPhy(deviceId), fast);
  });

  test('a simulated error reaches the stream and the reports go on', () async {
    // arrange
    final errors = <Object>[];
    final reported = <_Pair>[];
    fake
        .phyStream(deviceId)
        .listen(reported.add, onError: (Object error) => errors.add(error));

    // act
    fake.simulatePhyError(deviceId, StateError('reports broke'));
    fake.simulatePhy(deviceId, tx: fast.tx, rx: fast.rx);
    await pumpEventQueue();

    // assert
    expect(errors, [isA<StateError>()]);
    expect(reported, [fast]);
  });

  test('a report for another device is not reported', () async {
    // arrange
    final reported = <_Pair>[];
    fake.phyStream(deviceId).listen(reported.add);

    // act
    fake.simulatePhy(TestDeviceIds.device2, tx: fast.tx, rx: fast.rx);
    await pumpEventQueue();

    // assert
    expect(reported, isEmpty);
  });

  test('a request changes nothing until the radio reports', () async {
    // act
    await fake.requestPhy(deviceId, PlatformPhy.le2m, PlatformPhy.le2m);

    // assert
    expect(await fake.getPhy(deviceId), (
      tx: PlatformPhy.le1m,
      rx: PlatformPhy.le1m,
    ));
  });

  for (final (op, call)
      in <(FakeOp, Future<Object?> Function(FakeBlueyPlatform))>[
        (FakeOp.getPhy, (f) => f.getPhy(deviceId)),
        (FakeOp.requestPhy, (f) => f.requestPhy(deviceId, null, null)),
      ]) {
    test('a fault enqueued for ${op.name} is thrown by it', () async {
      // arrange
      fake.enqueueFault(
        op,
        const GattOperationTimeoutException('phy'),
        deviceId: deviceId,
      );

      // act
      final answer = call(fake);

      // assert
      await expectLater(answer, throwsA(isA<GattOperationTimeoutException>()));
    });
  }
}
