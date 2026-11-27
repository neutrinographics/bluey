import 'package:bluey/src/api/discovery/scan_failed_exception.dart';
import 'package:bluey/src/api/discovery/scan_failure_translation.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scanFailureAsException', () {
    for (final reason in ScanRefusalReason.values) {
      test('a scan refused for ${reason.name} is a ScanFailedException', () {
        // arrange
        final failure = ScanRefused(reason);

        // act
        final exception = scanFailureAsException(failure);

        // assert
        expect(
          exception,
          isA<ScanFailedException>().having(
            (e) => e.reason.name,
            'reason',
            reason.name,
          ),
        );
      });
    }

    test('a missing permission is a PermissionDeniedException', () {
      // arrange
      const failure = ScanPermissionMissing('BLUETOOTH_SCAN');

      // act
      final exception = scanFailureAsException(failure);

      // assert
      expect(
        exception,
        isA<PermissionDeniedException>().having(
          (e) => e.permissions,
          'permissions',
          ['BLUETOOTH_SCAN'],
        ),
      );
    });

    test('an unavailable radio is a BluetoothUnavailableException', () {
      // arrange
      const failure = ScanRadioUnavailable();

      // act
      final exception = scanFailureAsException(failure);

      // assert
      expect(exception, isA<BluetoothUnavailableException>());
    });

    test('an unexpected failure is a BlueyPlatformException keeping all', () {
      // arrange
      final cause = StateError('native');
      final failure = UnexpectedScanFailure('boom', code: 'E1', cause: cause);

      // act
      final exception = scanFailureAsException(failure);

      // assert
      expect(exception.runtimeType, BlueyPlatformException);
      final platform = exception as BlueyPlatformException;
      expect(platform.message, 'boom');
      expect(platform.code, 'E1');
      expect(platform.cause, cause);
    });
  });
}
