import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// The fake keeps the stream promises the real platform packages keep
/// (the platform interface's `DeviceStreams`, I369), so a unit tested over
/// the fake meets the same stream lifetimes it meets on a phone.
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

  group('a device connected twice keeps its link', () {
    test(
      'the MTU negotiated on the first connect survives the second',
      () async {
        // arrange
        await fake.connect(deviceId, config);
        await fake.requestMtu(deviceId, 185);

        // act
        await fake.connect(deviceId, config);

        // assert
        expect(
          await fake.getMaximumWriteLength(deviceId, withResponse: true),
          182,
        );
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

    test('leaves a connected device its streams and its connection, since '
        'an earlier connect opened them', () async {
      // arrange
      await fake.connect(deviceId, config);
      final expectation = expectLater(
        fake.connectionStateStream(deviceId),
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );
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
      expect(fake.connectedDeviceIds, [deviceId]);
      fake.simulateDisconnection(deviceId);
      await expectation;
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

  group('a connect between a requested disconnect\'s two signals', () {
    Future<void> expectTheNextLinkKeepsItsStreams() async {
      final next = expectLater(
        fake.connectionStateStream(deviceId),
        emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
      );
      await pumpEventQueue();
      fake.simulateDisconnection(deviceId);
      await next;
    }

    test('a connect made between the last report and the answer keeps its '
        'streams', () async {
      // arrange
      fake.disconnectSignals = FakeDisconnectSignals.reportThenAnswer;
      await fake.connect(deviceId, config);
      var answered = false;
      final closing = fake
          .disconnect(deviceId)
          .whenComplete(() => answered = true);
      await pumpEventQueue();
      expect(answered, isFalse);

      // act
      await fake.connect(deviceId, config);
      await closing;

      // assert
      await expectTheNextLinkKeepsItsStreams();
    });

    test('a connect made between the answer and the last report keeps its '
        'streams', () async {
      // arrange
      fake.disconnectSignals = FakeDisconnectSignals.answerThenReport;
      await fake.connect(deviceId, config);
      await fake.disconnect(deviceId);

      // act
      await fake.connect(deviceId, config);

      // assert
      await expectTheNextLinkKeepsItsStreams();
    });
  });
}
