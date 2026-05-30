import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' show lifecycleEvictionAttStatus;
import 'package:bluey/src/shared/error_translation.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

/// Pure-function tests for `translatePlatformException` — the anti-
/// corruption layer between platform-interface exception types and the
/// `BlueyException` domain hierarchy.
///
/// One test per platform exception type → expected domain type. Plus
/// defensive-backstop tests that nothing leaks raw.
void main() {
  const testAddress = 'AA:BB:CC:DD:EE:01';

  group('translatePlatformException', () {
    test('passes BlueyException through unchanged (already-translated)', () {
      final original = ConnectionException(
        DeviceAddress(testAddress),
        ConnectionFailureReason.timeout,
      );
      final result = translatePlatformException(
        original,
        operation: 'connect',
        address: testAddress,
      );
      expect(identical(result, original), isTrue);
    });

    test('GattOperationTimeoutException → GattTimeoutException', () {
      final result = translatePlatformException(
        const platform.GattOperationTimeoutException('readCharacteristic'),
        operation: 'readCharacteristic',
        address: testAddress,
      );
      expect(result, isA<GattTimeoutException>());
    });

    test('GattOperationDisconnectedException → '
        'DisconnectedException(address, linkLoss)', () {
      final result = translatePlatformException(
        const platform.GattOperationDisconnectedException(
          'writeCharacteristic',
        ),
        operation: 'writeCharacteristic',
        address: testAddress,
      );
      expect(result, isA<DisconnectedException>());
      final disconnected = result as DisconnectedException;
      expect(disconnected.address, testAddress);
      expect(disconnected.reason, DisconnectReason.linkLoss);
    });

    test('GattOperationDisconnectedException without deviceId uses a '
        'placeholder UUID — non-GATT call sites (connect) still get a '
        'typed DisconnectedException', () {
      final result = translatePlatformException(
        const platform.GattOperationDisconnectedException('connect'),
        operation: 'connect',
      );
      expect(result, isA<DisconnectedException>());
    });

    test('GattOperationStatusFailedException → '
        'GattOperationFailedException carrying status', () {
      final result = translatePlatformException(
        const platform.GattOperationStatusFailedException(
          'writeCharacteristic',
          0x03,
        ),
        operation: 'writeCharacteristic',
        address: testAddress,
      );
      expect(result, isA<GattOperationFailedException>());
      final failed = result as GattOperationFailedException;
      expect(failed.status, 0x03);
    });

    test('GattOperationUnknownPlatformException with code "gatt-handle-'
        'invalidated" → AttributeHandleInvalidatedException', () {
      final result = translatePlatformException(
        const platform.GattOperationUnknownPlatformException(
          'readCharacteristic',
          code: 'gatt-handle-invalidated',
        ),
        operation: 'readCharacteristic',
        address: testAddress,
      );
      expect(result, isA<AttributeHandleInvalidatedException>());
    });

    test('GattOperationUnknownPlatformException with other code → '
        'BlueyPlatformException preserving the wire code', () {
      final result = translatePlatformException(
        const platform.GattOperationUnknownPlatformException(
          'readCharacteristic',
          code: 'bluey-some-future-code',
          message: 'native-side message',
        ),
        operation: 'readCharacteristic',
        address: testAddress,
      );
      expect(result, isA<BlueyPlatformException>());
      final platformExc = result as BlueyPlatformException;
      expect(platformExc.code, 'bluey-some-future-code');
    });

    test('PlatformAdvertiseDataTooLargeException → '
        'AdvertisingException(dataTooBig)', () {
      final result = translatePlatformException(
        const platform.PlatformAdvertiseDataTooLargeException(
          'AD payload exceeded 31 bytes',
        ),
        operation: 'startAdvertising',
      );
      expect(result, isA<AdvertisingException>());
      final advertising = result as AdvertisingException;
      expect(advertising.reason, AdvertisingFailureReason.dataTooBig);
    });

    test(
      'PlatformRespondToRequestNotFoundException -> RespondNotFoundException',
      () {
        const platformError =
            platform.PlatformRespondToRequestNotFoundException(
              'requestId 42 not found',
            );
        final translated = translatePlatformException(
          platformError,
          operation: 'respondToReadRequest',
        );
        expect(translated, isA<RespondNotFoundException>());
        expect(
          (translated as RespondNotFoundException).message,
          contains('requestId 42 not found'),
        );
      },
    );

    test('PlatformPermissionDeniedException → PermissionDeniedException '
        'wrapping the single denied permission', () {
      final result = translatePlatformException(
        const platform.PlatformPermissionDeniedException(
          'connect',
          permission: 'BLUETOOTH_CONNECT',
        ),
        operation: 'connect',
      );
      expect(result, isA<PermissionDeniedException>());
      final denied = result as PermissionDeniedException;
      expect(denied.permissions, equals(['BLUETOOTH_CONNECT']));
    });

    test('PlatformBluetoothUnavailableException → '
        'BluetoothUnavailableException — adapter-state race backstop', () {
      final result = translatePlatformException(
        const platform.PlatformBluetoothUnavailableException(
          message: 'Bluetooth adapter is unavailable: remote object is dead',
        ),
        operation: 'writeCharacteristic',
        address: testAddress,
      );
      expect(result, isA<BluetoothUnavailableException>());
    });

    test('Flutter PlatformException → BlueyPlatformException (defensive '
        'backstop for un-translated platform errors)', () {
      final result = translatePlatformException(
        PlatformException(code: 'some-future-code', message: 'oops'),
        operation: 'connect',
      );
      expect(result, isA<BlueyPlatformException>());
      final platformExc = result as BlueyPlatformException;
      expect(platformExc.code, 'some-future-code');
    });

    test('arbitrary Object (e.g. StateError) → BlueyPlatformException — '
        'nothing leaks raw to callers', () {
      final result = translatePlatformException(
        StateError('something unrelated'),
        operation: 'configure',
      );
      expect(result, isA<BlueyPlatformException>());
    });
  });

  group('eviction-status translation', () {
    test('reserved eviction status becomes DisconnectedException(evictedByServer)', () {
      final translated = translatePlatformException(
        platform.GattOperationStatusFailedException('write', lifecycleEvictionAttStatus),
        operation: 'write',
        address: 'AA:BB:CC:DD:EE:FF',
      );
      expect(translated, isA<DisconnectedException>());
      final dx = translated as DisconnectedException;
      expect(dx.reason, DisconnectReason.evictedByServer);
      expect(dx.address, 'AA:BB:CC:DD:EE:FF');
    });

    test('a non-reserved status still maps to GattOperationFailedException', () {
      final translated = translatePlatformException(
        platform.GattOperationStatusFailedException('write', 0x01),
        operation: 'write',
      );
      expect(translated, isA<GattOperationFailedException>());
    });
  });
}
