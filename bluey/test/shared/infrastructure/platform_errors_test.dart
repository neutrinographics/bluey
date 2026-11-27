import 'package:bluey/src/shared/infrastructure/platform_errors.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('platformErrorOf', () {
    test('a denied permission names the permission', () {
      // arrange
      const thrown = PlatformPermissionDeniedException(
        'scan',
        permission: 'BLUETOOTH_SCAN',
      );

      // act
      final error = platformErrorOf(thrown);

      // assert
      expect(error, isA<PermissionDenied>());
      expect((error as PermissionDenied).permission, 'BLUETOOTH_SCAN');
    });

    test('an unavailable adapter is the radio being unavailable', () {
      // arrange
      const thrown = PlatformBluetoothUnavailableException();

      // act
      final error = platformErrorOf(thrown);

      // assert
      expect(error, isA<RadioUnavailable>());
    });

    test('a platform exception keeps its message and code', () {
      // arrange
      final cause = PlatformException(code: 'boom', message: 'it broke');

      // act
      final error = platformErrorOf(cause) as Unexpected;

      // assert
      expect(error.detail, 'it broke');
      expect(error.code, 'boom');
      expect(error.cause, same(cause));
    });

    test('a platform exception with no message is worded by its code', () {
      // arrange
      final cause = PlatformException(code: 'boom');

      // act
      final error = platformErrorOf(cause) as Unexpected;

      // assert
      expect(error.detail, 'platform error (boom)');
    });

    test('anything else is worded by what it says', () {
      // arrange
      final cause = StateError('nope');

      // act
      final error = platformErrorOf(cause) as Unexpected;

      // assert
      expect(error.detail, cause.toString());
      expect(error.code, isNull);
      expect(error.cause, same(cause));
    });
  });
}
