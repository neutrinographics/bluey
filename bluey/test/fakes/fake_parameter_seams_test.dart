import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the seams that make the fake's radio answer and refuse
/// connection parameters.
void main() {
  const deviceId = TestDeviceIds.device1;
  const brisk = PlatformConnectionParameters(
    intervalMs: 15.0,
    latency: 4,
    timeoutMs: 2000,
  );
  late FakeBlueyPlatform fake;

  setUp(() => fake = FakeBlueyPlatform()..simulatePeripheral(id: deviceId));

  tearDown(() => fake.dispose());

  test('reads 30 ms, 0 and 4,000 ms until parameters are simulated', () async {
    // act
    final parameters = await fake.getConnectionParameters(deviceId);

    // assert
    expect(
      (parameters.intervalMs, parameters.latency, parameters.timeoutMs),
      (30.0, 0, 4000),
    );
  });

  test('simulated parameters are read for their device alone', () async {
    // act
    fake.simulateConnectionParameters(deviceId, brisk);

    // assert
    expect(await fake.getConnectionParameters(deviceId), same(brisk));
    expect(
      (await fake.getConnectionParameters(TestDeviceIds.device2)).intervalMs,
      30.0,
    );
  });

  for (final (op, call)
      in <(FakeOp, Future<Object?> Function(FakeBlueyPlatform))>[
        (
          FakeOp.getConnectionParameters,
          (f) => f.getConnectionParameters(deviceId),
        ),
        (
          FakeOp.requestConnectionParameters,
          (f) => f.requestConnectionParameters(deviceId, brisk),
        ),
      ]) {
    test('a fault enqueued for ${op.name} is thrown by it', () async {
      // arrange
      fake.enqueueFault(
        op,
        const GattOperationTimeoutException('parameters'),
        deviceId: deviceId,
      );

      // act
      final answer = call(fake);

      // assert
      await expectLater(answer, throwsA(isA<GattOperationTimeoutException>()));
    });
  }
}
