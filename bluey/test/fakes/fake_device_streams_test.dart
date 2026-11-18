import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// The fake keeps the stream promises the real platform packages keep
/// (their `DeviceStreams`, I369), so a unit tested over the fake meets the
/// same stream lifetimes it meets on a phone.
void main() {
  const deviceId = TestDeviceIds.device1;
  const config = PlatformConnectConfig(timeoutMs: null, mtu: null);

  late FakeBlueyPlatform fake;

  setUp(() {
    fake = FakeBlueyPlatform()..simulatePeripheral(id: deviceId);
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('a device connected twice', () {
    test('the second connect keeps the first state stream attached, and '
        'reports nothing, since the link was already up', () async {
      // arrange
      await fake.connect(deviceId, config);
      final states = fake.connectionStateStream(deviceId);
      final expectation = expectLater(
        states,
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );

      // act
      await fake.connect(deviceId, config);
      fake.simulateDisconnection(deviceId);

      // assert
      await expectation;
    });

    test(
      'the second connect keeps the first notification stream attached',
      () async {
        // arrange
        await fake.connect(deviceId, config);
        final notifications = fake.notificationStream(deviceId);
        final expectation = expectLater(notifications, emitsDone);

        // act
        await fake.connect(deviceId, config);
        fake.simulateDisconnection(deviceId);

        // assert
        await expectation;
      },
    );
  });

  group('a drop', () {
    test('reports disconnected, then ends the state stream', () async {
      // arrange
      await fake.connect(deviceId, config);
      final expectation = expectLater(
        fake.connectionStateStream(deviceId),
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );

      // act
      fake.simulateDisconnection(deviceId);

      // assert
      await expectation;
    });

    test('ends the notification stream', () async {
      // arrange
      await fake.connect(deviceId, config);
      final notifications = fake.notificationStream(deviceId);

      // act
      fake.simulateDisconnection(deviceId);

      // assert
      await expectLater(notifications, emitsDone);
    });

    test(
      'leaves the device with no streams, so a reconnect opens new ones',
      () async {
        // arrange
        await fake.connect(deviceId, config);
        fake.simulateDisconnection(deviceId);
        await pumpEventQueue();

        // act
        await fake.connect(deviceId, config);
        final expectation = expectLater(
          fake.connectionStateStream(deviceId),
          emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
        );
        fake.simulateDisconnection(deviceId);

        // assert
        await expectation;
      },
    );
  });

  group('a failed connect', () {
    test('leaves a device that had no streams with none', () async {
      // arrange
      fake.simulateConnectFailure(
        deviceId,
        PlatformConnectFailureReason.timeout,
      );

      // act
      await expectLater(
        fake.connect(deviceId, config),
        throwsA(isA<PlatformConnectFailedException>()),
      );

      // assert
      expect(fake.connectedDeviceIds, isEmpty);
      await expectLater(
        fake.connectionStateStream(deviceId),
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );
    });

    test('ends the streams of a device that had them', () async {
      // arrange
      await fake.connect(deviceId, config);
      final states = fake.connectionStateStream(deviceId);
      fake.simulateConnectFailure(
        deviceId,
        PlatformConnectFailureReason.unknown,
      );

      // act
      await expectLater(
        fake.connect(deviceId, config),
        throwsA(isA<PlatformConnectFailedException>()),
      );

      // assert
      await expectLater(states, emitsDone);
      expect(fake.connectedDeviceIds, isEmpty);
    });
  });

  group('a fault queued for disconnect', () {
    test('fails the disconnect and leaves the link as it was', () async {
      // arrange
      await fake.connect(deviceId, config);
      final expectation = expectLater(
        fake.connectionStateStream(deviceId),
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );
      fake.enqueueFault(
        FakeOp.disconnect,
        PlatformException(code: 'disconnect-failed'),
        deviceId: deviceId,
      );

      // act
      await expectLater(
        fake.disconnect(deviceId),
        throwsA(isA<PlatformException>()),
      );
      fake.simulateDisconnection(deviceId);

      // assert
      await expectation;
    });

    test('is used up, so the next disconnect closes the link', () async {
      // arrange
      await fake.connect(deviceId, config);
      final expectation = expectLater(
        fake.connectionStateStream(deviceId),
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );
      fake.enqueueFault(
        FakeOp.disconnect,
        PlatformException(code: 'disconnect-failed'),
        deviceId: deviceId,
      );
      await expectLater(fake.disconnect(deviceId), throwsA(anything));

      // act
      await fake.disconnect(deviceId);

      // assert
      await expectation;
      expect(fake.connectedDeviceIds, isEmpty);
    });
  });

  group('a state stream error', () {
    test('reaches the device\'s state stream listener', () async {
      // arrange
      await fake.connect(deviceId, config);
      final states = fake.connectionStateStream(deviceId);
      final expectation = expectLater(states, emitsError(isA<StateError>()));

      // act
      fake.simulateConnectionStateError(deviceId, StateError('boom'));

      // assert
      await expectation;
    });
  });
}
