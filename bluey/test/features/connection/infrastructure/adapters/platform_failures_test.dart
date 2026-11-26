import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_failures.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connectionFailureFrom', () {
    test('a GATT timeout is the operation timing out', () {
      // arrange
      const error = GattOperationTimeoutException('readRssi');

      // act
      final failure = connectionFailureFrom(error, operation: 'rssi');

      // assert
      expect(failure, const OperationTimedOut('rssi'));
    });

    test('a GATT disconnect is the link ended by a drop', () {
      // arrange
      const error = GattOperationDisconnectedException('readRssi');

      // act
      final failure = connectionFailureFrom(error, operation: 'rssi');

      // assert
      expect(failure, const LinkHadEnded(EndedByDrop()));
    });

    test('a GATT status is the operation rejected with that status', () {
      // arrange
      const error = GattOperationStatusFailedException('requestMtu', 0x80);

      // act
      final failure = connectionFailureFrom(error, operation: 'mtu');

      // assert
      expect(failure, const OperationRejected('mtu', 0x80));
    });

    test('an unknown GATT platform error keeps its code, its message and '
        'itself, and names its code when it has no message', () {
      // arrange
      const withMessage = GattOperationUnknownPlatformException(
        'connect',
        code: 'weird',
        message: 'it broke',
      );
      const withoutMessage = GattOperationUnknownPlatformException(
        'connect',
        code: 'weird',
      );

      // act
      final failures = [
        connectionFailureFrom(withMessage, operation: 'connect'),
        connectionFailureFrom(withoutMessage, operation: 'connect'),
      ];

      // assert
      expect(failures, const [
        UnexpectedPlatformFailure(
          'it broke',
          code: 'weird',
          cause: withMessage,
        ),
        UnexpectedPlatformFailure(
          'unknown platform error (weird)',
          code: 'weird',
          cause: withoutMessage,
        ),
      ]);
    });

    test('a failed connect is ConnectFailed with its reason in Connection\'s '
        'words', () {
      // arrange
      final reasons = PlatformConnectFailureReason.values;

      // act
      final failures = [
        for (final reason in reasons)
          connectionFailureFrom(
            PlatformConnectFailedException(reason, status: 133),
            operation: 'connect',
          ),
      ];

      // assert
      expect(failures, const [
        ConnectFailed(ConnectFailureReason.timeout),
        ConnectFailed(ConnectFailureReason.deviceNotFound),
        ConnectFailed(ConnectFailureReason.deviceNotConnectable),
        ConnectFailed(ConnectFailureReason.pairingFailed),
        ConnectFailed(ConnectFailureReason.connectionLimitReached),
        ConnectFailed(ConnectFailureReason.unknown),
      ]);
    });

    test('a denied permission is that permission missing', () {
      // arrange
      const error = PlatformPermissionDeniedException(
        'connect',
        permission: 'BLUETOOTH_CONNECT',
      );

      // act
      final failure = connectionFailureFrom(error, operation: 'connect');

      // assert
      expect(failure, const PermissionMissing('BLUETOOTH_CONNECT'));
    });

    test('an unavailable adapter is the radio unavailable', () {
      // arrange
      const error = PlatformBluetoothUnavailableException(message: 'off');

      // act
      final failure = connectionFailureFrom(error, operation: 'connect');

      // assert
      expect(failure, const RadioUnavailable());
    });

    test('a Flutter platform error keeps its code, its message and itself, '
        'and names its code when it has no message', () {
      // arrange
      final withMessage = PlatformException(code: 'E1', message: 'no channel');
      final withoutMessage = PlatformException(code: 'E1');

      // act
      final failures = [
        connectionFailureFrom(withMessage, operation: 'disconnect'),
        connectionFailureFrom(withoutMessage, operation: 'disconnect'),
      ];

      // assert
      expect(failures, [
        UnexpectedPlatformFailure('no channel', code: 'E1', cause: withMessage),
        UnexpectedPlatformFailure(
          'platform error (E1)',
          code: 'E1',
          cause: withoutMessage,
        ),
      ]);
    });

    test('anything else is unexpected, described by itself', () {
      // arrange
      final error = StateError('boom');

      // act
      final failure = connectionFailureFrom(error, operation: 'connect');

      // assert
      expect(
        failure,
        UnexpectedPlatformFailure('Bad state: boom', cause: error),
      );
    });
  });

  group('answering', () {
    test('a call that returns answers its value', () async {
      // act
      final answer = await answering('connect', () async => 'AA');

      // assert
      expect(answer, const Right<ConnectionFailure, String>('AA'));
    });

    test('a call that throws answers what it threw as a failure', () async {
      // act
      final answer = await answering<String>(
        'connect',
        () async => throw const GattOperationTimeoutException('connect'),
      );

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, String>(OperationTimedOut('connect')),
      );
    });
  });
}
