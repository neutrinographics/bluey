import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattOperationTimeoutException', () {
    test('exposes the operation name and a default message', () {
      const e = GattOperationTimeoutException('writeCharacteristic');

      expect(e.operation, equals('writeCharacteristic'));
      expect(
        e.toString(),
        contains('writeCharacteristic'),
        reason: 'toString should mention the operation for log readability',
      );
    });

    test('is an Exception so it can be caught with on Exception', () {
      const e = GattOperationTimeoutException('readCharacteristic');
      expect(e, isA<Exception>());
    });

    test('two instances with the same operation are equal', () {
      const a = GattOperationTimeoutException('readCharacteristic');
      const b = GattOperationTimeoutException('readCharacteristic');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('GattOperationDisconnectedException', () {
    test('exposes the operation name and a default message', () {
      const e = GattOperationDisconnectedException('writeCharacteristic');

      expect(e.operation, equals('writeCharacteristic'));
      expect(
        e.toString(),
        contains('writeCharacteristic'),
        reason: 'toString should mention the operation for log readability',
      );
    });

    test('is an Exception so it can be caught with on Exception', () {
      const e = GattOperationDisconnectedException('readCharacteristic');
      expect(e, isA<Exception>());
    });

    test('two instances with the same operation are equal', () {
      const a = GattOperationDisconnectedException('readCharacteristic');
      const b = GattOperationDisconnectedException('readCharacteristic');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('GattOperationStatusFailedException', () {
    test('exposes the operation name, status, and a default message', () {
      const e = GattOperationStatusFailedException('writeCharacteristic', 1);

      expect(e.operation, equals('writeCharacteristic'));
      expect(e.status, equals(1));
      expect(
        e.toString(),
        allOf(contains('writeCharacteristic'), contains('1')),
        reason: 'toString should mention both the operation and status code',
      );
    });

    test('is an Exception so it can be caught with on Exception', () {
      const e = GattOperationStatusFailedException('readCharacteristic', 8);
      expect(e, isA<Exception>());
    });

    test('two instances with the same operation and status are equal', () {
      const a = GattOperationStatusFailedException('readCharacteristic', 3);
      const b = GattOperationStatusFailedException('readCharacteristic', 3);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs by status', () {
      const a = GattOperationStatusFailedException('readCharacteristic', 3);
      const b = GattOperationStatusFailedException('readCharacteristic', 5);
      expect(a, isNot(equals(b)));
    });
  });

  group('PlatformPermissionDeniedException', () {
    test('carries operation, permission, and message', () {
      const e = PlatformPermissionDeniedException(
        'writeCharacteristic',
        permission: 'BLUETOOTH_CONNECT',
        message: 'Missing BLUETOOTH_CONNECT permission',
      );
      expect(e.operation, 'writeCharacteristic');
      expect(e.permission, 'BLUETOOTH_CONNECT');
      expect(e.message, 'Missing BLUETOOTH_CONNECT permission');
    });

    test('equality by value', () {
      const a = PlatformPermissionDeniedException('op', permission: 'P');
      const b = PlatformPermissionDeniedException('op', permission: 'P');
      expect(a, equals(b));
    });
  });

  group('PlatformAdvertiseDataTooLargeException', () {
    test('toString includes the message', () {
      const e = PlatformAdvertiseDataTooLargeException('AD payload exceeded 31 bytes');
      expect(e.toString(), contains('PlatformAdvertiseDataTooLargeException'));
      expect(e.toString(), contains('AD payload exceeded 31 bytes'));
    });

    test('two instances with the same message are equal', () {
      const a = PlatformAdvertiseDataTooLargeException('msg');
      const b = PlatformAdvertiseDataTooLargeException('msg');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
