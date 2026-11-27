import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/infrastructure/adapters/platform_scan_failures.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scanFailureFrom', () {
    for (final reason in PlatformScanFailureReason.values) {
      test('a platform refusal for ${reason.name} is the same refusal', () {
        // arrange
        final error = PlatformScanFailedException(reason);

        // act
        final failure = scanFailureFrom(error);

        // assert
        expect(
          failure,
          ScanRefused(ScanRefusalReason.values.byName(reason.name)),
        );
      });
    }

    test('a missing permission is the scan lacking it', () {
      // arrange
      const error = PlatformPermissionDeniedException(
        'scan',
        permission: 'BLUETOOTH_SCAN',
      );

      // act
      final failure = scanFailureFrom(error);

      // assert
      expect(failure, const ScanPermissionMissing('BLUETOOTH_SCAN'));
    });

    test('an unavailable adapter is the radio being unavailable', () {
      // arrange
      const error = PlatformBluetoothUnavailableException();

      // act
      final failure = scanFailureFrom(error);

      // assert
      expect(failure, const ScanRadioUnavailable());
    });

    test('anything else keeps its detail, code and cause', () {
      // arrange
      final error = PlatformException(code: 'E1', message: 'boom');

      // act
      final failure = scanFailureFrom(error);

      // assert
      expect(failure, UnexpectedScanFailure('boom', code: 'E1', cause: error));
    });
  });
}
