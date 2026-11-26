import 'package:bluey/src/api/connection/connection_failure_translation.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_failures.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/error_translation.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

/// The fields an app reads from [exception] beyond its text, so the parity
/// check sees an address, a code or a reason that `toString()` leaves out.
/// An exception type with no projection fails the test rather than passing
/// unseen.
Map<String, Object?> fieldsOf(BlueyException exception) => {
  'action': exception.action,
  ...switch (exception) {
    DisconnectedException(:final address, :final reason) => {
      'address': address,
      'reason': reason,
    },
    ConnectionException(:final deviceAddress, :final reason) => {
      'deviceAddress': deviceAddress,
      'reason': reason,
    },
    BlueyPlatformException(:final code) => {'code': code},
    GattTimeoutException(:final operation) => {'operation': operation},
    GattOperationFailedException(:final operation, :final status) => {
      'operation': operation,
      'status': status,
    },
    PermissionDeniedException(:final permissions) => {
      'permissions': permissions,
    },
    BluetoothUnavailableException() => const <String, Object?>{},
    _ => fail('No field projection for ${exception.runtimeType}.'),
  },
};

void main() {
  group('a platform error read through Connection reads as it does today', () {
    final platformErrors = <Object>[
      const GattOperationTimeoutException('connect'),
      const GattOperationDisconnectedException('readRssi'),
      const GattOperationStatusFailedException('requestMtu', 133),
      const GattOperationUnknownPlatformException(
        'readRssi',
        code: 'some-code',
        message: 'detail',
      ),
      const GattOperationUnknownPlatformException(
        'readRssi',
        code: 'some-code',
      ),
      for (final reason in PlatformConnectFailureReason.values)
        PlatformConnectFailedException(reason),
      const PlatformPermissionDeniedException(
        'connect',
        permission: 'BLUETOOTH_CONNECT',
      ),
      const PlatformBluetoothUnavailableException(),
      PlatformException(code: 'x', message: 'y'),
      PlatformException(code: 'x'),
      StateError('anything else'),
      Exception('Not connected to device: ${device.value}'),
    ];
    for (final error in platformErrors) {
      test('${error.runtimeType} ($error) translates as it does today', () {
        // arrange
        final today = translatePlatformException(
          error,
          operation: 'op',
          address: device.value,
        );

        // act
        final now = connectionFailureAsException(
          connectionFailureFrom(error, operation: 'op'),
          device: device,
        );

        // assert
        expect(now.runtimeType, today.runtimeType);
        expect(now.toString(), today.toString());
        expect(fieldsOf(now), fieldsOf(today));
        expect(now.cause, same(today.cause));
      });
    }
  });

  group('the one row that differs from today', () {
    test('a rejected request reads as rejected whatever its status', () {
      // arrange
      const error = GattOperationStatusFailedException('requestMtu', 0x80);

      // act
      final now = connectionFailureAsException(
        connectionFailureFrom(error, operation: 'requestMtu'),
        device: device,
      );

      // assert
      expect(
        now,
        isA<GattOperationFailedException>().having(
          (e) => e.status,
          'status',
          0x80,
        ),
      );
    });
  });
}
