import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the seams that make the fake's radio report and
/// refuse bond states.
void main() {
  const deviceId = TestDeviceIds.device1;
  late FakeBlueyPlatform fake;

  setUp(() => fake = FakeBlueyPlatform()..simulatePeripheral(id: deviceId));

  tearDown(() => fake.dispose());

  test('reads none until a bond state is simulated', () async {
    // act
    final state = await fake.getBondState(deviceId);

    // assert
    expect(state, PlatformBondState.none);
  });

  test('a simulated bond state is read and reported', () async {
    // arrange
    final reported = <PlatformBondState>[];
    fake.bondStateStream(deviceId).listen(reported.add);

    // act
    fake.simulateBondState(deviceId, PlatformBondState.bonding);
    fake.simulateBondState(deviceId, PlatformBondState.bonded);
    await pumpEventQueue();

    // assert
    expect(reported, [PlatformBondState.bonding, PlatformBondState.bonded]);
    expect(await fake.getBondState(deviceId), PlatformBondState.bonded);
  });

  test('a simulated error reaches the stream and the reports go on', () async {
    // arrange
    final errors = <Object>[];
    final reported = <PlatformBondState>[];
    fake
        .bondStateStream(deviceId)
        .listen(reported.add, onError: (Object error) => errors.add(error));

    // act
    fake.simulateBondStateError(deviceId, StateError('reports broke'));
    fake.simulateBondState(deviceId, PlatformBondState.bonded);
    await pumpEventQueue();

    // assert
    expect(errors, [isA<StateError>()]);
    expect(reported, [PlatformBondState.bonded]);
  });

  test('a report for another device is not reported', () async {
    // arrange
    final reported = <PlatformBondState>[];
    fake.bondStateStream(deviceId).listen(reported.add);

    // act
    fake.simulateBondState(TestDeviceIds.device2, PlatformBondState.bonded);
    await pumpEventQueue();

    // assert
    expect(reported, isEmpty);
  });

  for (final (op, call)
      in <(FakeOp, Future<Object?> Function(FakeBlueyPlatform))>[
        (FakeOp.getBondState, (f) => f.getBondState(deviceId)),
        (FakeOp.bond, (f) => f.bond(deviceId)),
        (FakeOp.removeBond, (f) => f.removeBond(deviceId)),
      ]) {
    test('a fault enqueued for ${op.name} is thrown by it', () async {
      // arrange
      fake.enqueueFault(
        op,
        const GattOperationTimeoutException('bond'),
        deviceId: deviceId,
      );

      // act
      final answer = call(fake);

      // assert
      await expectLater(answer, throwsA(isA<GattOperationTimeoutException>()));
    });
  }
}
