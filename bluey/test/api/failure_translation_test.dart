import 'package:bluey/src/api/failure_translation.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/platform/bluetooth_state.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

const _device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  group('connectionFailureAsException', () {
    for (final reason in ConnectFailureReason.values) {
      test('a connect that failed for ${reason.name} is a ConnectionException '
          'for the device with the reason of the same name', () {
        // arrange
        final failure = ConnectFailed(reason);

        // act
        final exception = connectionFailureAsException(
          failure,
          device: _device,
        );

        // assert
        expect(
          exception,
          isA<ConnectionException>()
              .having((e) => e.deviceAddress, 'deviceAddress', _device)
              .having((e) => e.reason.name, 'reason', reason.name),
        );
      });
    }

    test('a link ended on request is a requested disconnect', () {
      // arrange
      const failure = LinkEnded(EndedOnRequest());

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(
        exception,
        isA<DisconnectedException>()
            .having((e) => e.address, 'address', _device.value)
            .having((e) => e.reason, 'reason', DisconnectReason.requested),
      );
    });

    test('a link ended by a drop is a link-loss disconnect', () {
      // arrange
      const failure = LinkEnded(EndedByDrop());

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(
        exception,
        isA<DisconnectedException>()
            .having((e) => e.address, 'address', _device.value)
            .having((e) => e.reason, 'reason', DisconnectReason.linkLoss),
      );
    });

    for (final outage in RadioOutage.values) {
      test('a link ended by a radio outage (${outage.name}) is a stale '
          'connection invalidated by the adapter state of the same name', () {
        // arrange
        final failure = LinkEnded(EndedByRadioOutage(outage));

        // act
        final exception = connectionFailureAsException(
          failure,
          device: _device,
        );

        // assert
        expect(
          exception,
          isA<StaleHandleException>()
              .having(
                (e) => e.instanceType,
                'instanceType',
                InvalidatedInstance.connection,
              )
              .having(
                (e) => e.cause,
                'cause',
                AdapterTransitionInvalidation(
                  BluetoothState.values.byName(outage.name),
                ),
              ),
        );
      });
    }

    test('an unavailable radio is Bluetooth being unavailable', () {
      // arrange
      const failure = RadioUnavailable();

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(exception, isA<BluetoothUnavailableException>());
    });

    test('a missing permission is a denial naming that permission alone', () {
      // arrange
      const failure = PermissionMissing('BLUETOOTH_CONNECT');

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(
        exception,
        isA<PermissionDeniedException>().having(
          (e) => e.permissions,
          'permissions',
          ['BLUETOOTH_CONNECT'],
        ),
      );
    });

    test('an operation that timed out is a GATT timeout of that operation', () {
      // arrange
      const failure = OperationTimedOut('readRssi');

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(
        exception,
        isA<GattTimeoutException>().having(
          (e) => e.operation,
          'operation',
          'readRssi',
        ),
      );
    });

    test('a rejected operation is a failed GATT operation with its status', () {
      // arrange
      const failure = OperationRejected('requestMtu', 133);

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(
        exception,
        isA<GattOperationFailedException>()
            .having((e) => e.operation, 'operation', 'requestMtu')
            .having((e) => e.status, 'status', 133),
      );
    });

    test('an unexpected platform failure is a platform exception keeping its '
        'detail, code and cause', () {
      // arrange
      final cause = StateError('underneath');
      final failure = UnexpectedPlatformFailure(
        'it broke',
        code: 'weird',
        cause: cause,
      );

      // act
      final exception = connectionFailureAsException(failure, device: _device);

      // assert
      expect(
        exception,
        isA<BlueyPlatformException>()
            .having((e) => e.message, 'message', 'it broke')
            .having((e) => e.code, 'code', 'weird')
            .having((e) => e.cause, 'cause', same(cause)),
      );
    });
  });

  group('linkEndAsException', () {
    test('reads each end as a failure on that link would', () {
      // arrange
      const ends = <LinkEnd>[
        EndedOnRequest(),
        EndedByDrop(),
        EndedByRadioOutage(RadioOutage.off),
      ];

      // act
      final exceptions = [
        for (final end in ends) linkEndAsException(end, device: _device),
      ];

      // assert
      expect(exceptions.map((e) => e.toString()), [
        for (final end in ends)
          connectionFailureAsException(
            LinkEnded(end),
            device: _device,
          ).toString(),
      ]);
      expect(exceptions.map((e) => e.runtimeType), [
        DisconnectedException,
        DisconnectedException,
        StaleHandleException,
      ]);
    });
  });

  group('valueOrThrow', () {
    test('answers the value of a success', () {
      // arrange
      const answer = Right<ConnectionFailure, int>(42);

      // act
      final value = valueOrThrow(answer, device: _device);

      // assert
      expect(value, 42);
    });

    test('throws a failure as the exception an app gets for it', () {
      // arrange
      const answer = Left<ConnectionFailure, int>(
        OperationTimedOut('readRssi'),
      );

      // act
      void read() => valueOrThrow(answer, device: _device);

      // assert
      expect(
        read,
        throwsA(
          isA<GattTimeoutException>().having(
            (e) => e.operation,
            'operation',
            'readRssi',
          ),
        ),
      );
    });
  });
}
