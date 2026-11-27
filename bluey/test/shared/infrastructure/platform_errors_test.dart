import 'package:bluey/src/shared/infrastructure/platform_errors.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('platformErrorOf', () {
    test('a denied permission names the permission', () {
      final error = platformErrorOf(
        const PlatformPermissionDeniedException(
          'scan',
          permission: 'BLUETOOTH_SCAN',
        ),
      );

      expect(error, isA<PermissionDenied>());
      expect((error as PermissionDenied).permission, 'BLUETOOTH_SCAN');
    });

    test('an unavailable adapter is the radio being unavailable', () {
      final error = platformErrorOf(
        const PlatformBluetoothUnavailableException(),
      );

      expect(error, isA<RadioUnavailable>());
    });

    test('a platform exception keeps its message and code', () {
      final cause = PlatformException(code: 'boom', message: 'it broke');

      final error = platformErrorOf(cause) as Unexpected;

      expect(error.detail, 'it broke');
      expect(error.code, 'boom');
      expect(error.cause, same(cause));
    });

    test('a platform exception with no message is worded by its code', () {
      final error =
          platformErrorOf(PlatformException(code: 'boom')) as Unexpected;

      expect(error.detail, 'platform error (boom)');
    });

    test('anything else is worded by what it says', () {
      final cause = StateError('nope');

      final error = platformErrorOf(cause) as Unexpected;

      expect(error.detail, cause.toString());
      expect(error.code, isNull);
      expect(error.cause, same(cause));
    });
  });
}
