import 'dart:typed_data';

import 'package:bluey_android/src/device_streams.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DeviceStreams streams;

  setUp(() {
    streams = DeviceStreams();
  });

  PlatformNotification notificationFor(String deviceId) => PlatformNotification(
    deviceId: deviceId,
    characteristicUuid: '2a37',
    value: Uint8List.fromList([1]),
    characteristicHandle: 7,
  );

  group('a device opened twice', () {
    test('a second open keeps the first stream attached', () async {
      // arrange
      streams.open('dev');
      final first = streams.statesOf('dev');

      // act
      streams.open('dev');

      // assert
      final expectation = expectLater(
        first,
        emits(PlatformConnectionState.connected),
      );
      streams.reportState('dev', PlatformConnectionState.connected);
      await expectation;
    });
  });

  group('opening a device', () {
    test('open answers true when it creates the pair', () {
      // arrange
      const deviceId = 'dev';

      // act
      final created = streams.open(deviceId);

      // assert
      expect(created, isTrue);
    });

    test('open answers false when the pair is already live', () {
      // arrange
      streams.open('dev');

      // act
      final created = streams.open('dev');

      // assert
      expect(created, isFalse);
    });
  });

  group('the device\'s last event', () {
    test(
      'the disconnected report is delivered, and then both streams end',
      () async {
        // arrange
        streams.open('dev');
        final states = expectLater(
          streams.statesOf('dev'),
          emitsInOrder([PlatformConnectionState.disconnected, emitsDone]),
        );
        final notifications = expectLater(
          streams.notificationsOf('dev'),
          emitsDone,
        );

        // act
        streams.reportState('dev', PlatformConnectionState.disconnected);

        // assert
        await states;
        await notifications;
      },
    );

    test('after the last report the device has no streams', () async {
      // arrange
      streams.open('dev');
      streams.statesOf('dev').listen((_) {});

      // act
      streams.reportState('dev', PlatformConnectionState.disconnected);
      await pumpEventQueue();

      // assert
      expect(streams.statesOf('dev'), emitsError(isA<StateError>()));
      expect(streams.notificationsOf('dev'), emitsError(isA<StateError>()));
    });
  });

  group('closing a device', () {
    test('close ends both streams and is safe to repeat', () async {
      // arrange
      streams.open('dev');
      final states = expectLater(streams.statesOf('dev'), emitsDone);
      final notifications = expectLater(
        streams.notificationsOf('dev'),
        emitsDone,
      );

      // act
      await streams.close('dev');
      await streams.close('dev');

      // assert
      await states;
      await notifications;
      expect(streams.statesOf('dev'), emitsError(isA<StateError>()));
    });
  });

  group('a device with no streams', () {
    test('a report for a device with no streams is dropped', () {
      // arrange
      const deviceId = 'never-opened';

      // act
      void report() {
        streams.reportState(deviceId, PlatformConnectionState.connected);
        streams.reportNotification(deviceId, notificationFor(deviceId));
      }

      // assert
      expect(report, returnsNormally);
      expect(streams.statesOf(deviceId), emitsError(isA<StateError>()));
      expect(streams.notificationsOf(deviceId), emitsError(isA<StateError>()));
    });
  });

  group('a device with open streams', () {
    test('a notification reaches the device\'s open stream', () async {
      // arrange
      streams.open('dev');
      final received = expectLater(
        streams.notificationsOf('dev'),
        emits(
          isA<PlatformNotification>().having(
            (n) => n.characteristicHandle,
            'characteristicHandle',
            7,
          ),
        ),
      );

      // act
      streams.reportNotification('dev', notificationFor('dev'));

      // assert
      await received;
    });
  });
}
