import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every kind of BlueyException, as an app wrote the switch before a refused
/// scan had an exception of its own.
String _kindOf(BlueyException exception) => switch (exception) {
  BluetoothUnavailableException() => 'unavailable',
  BluetoothDisabledException() => 'disabled',
  PermissionDeniedException() => 'permission',
  ConnectionException() => 'connection',
  DisconnectedException() => 'disconnected',
  ServiceNotFoundException() => 'service',
  CharacteristicNotFoundException() => 'characteristic',
  AmbiguousAttributeException() => 'ambiguous',
  AttributeHandleInvalidatedException() => 'handle',
  AttributeNotFoundException() => 'attribute',
  GattException() => 'gatt',
  GattTimeoutException() => 'timeout',
  GattOperationFailedException() => 'gattFailed',
  OperationNotSupportedException() => 'notSupported',
  ServerRespondFailedException() => 'respond',
  RespondNotFoundException() => 'respondNotFound',
  AdvertisingException() => 'advertising',
  PeerNotFoundException() => 'peer',
  NotABlueyPeerException() => 'notAPeer',
  LocalIdentityRequiredException() => 'identity',
  PeerIdentityMismatchException() => 'mismatch',
  UnsupportedOperationException() => 'unsupported',
  BlueyPlatformException() => 'platform',
  StaleHandleException() => 'stale',
};

void main() {
  group('ScanFailedException', () {
    test('names the reason the scan was refused for', () {
      // arrange
      const reason = ScanFailureReason.registrationFailed;

      // act
      final exception = ScanFailedException(reason);

      // assert
      expect(exception.reason, reason);
      expect(exception.message, 'The scan was refused: registrationFailed');
    });

    test('is a platform exception, so an app matching those still sees it', () {
      // arrange
      final exception = ScanFailedException(ScanFailureReason.unknown);

      // act
      final BlueyException asBluey = exception;

      // assert
      expect(exception, isA<BlueyPlatformException>());
      expect(_kindOf(asBluey), 'platform');
    });

    test('has a reason for each of the platform\'s refusals', () {
      // arrange
      const expected = [
        'alreadyStarted',
        'registrationFailed',
        'internalError',
        'unsupported',
        'outOfHardwareResources',
        'startedTooOften',
        'unknown',
      ];

      // act
      final names = [
        for (final reason in ScanFailureReason.values) reason.name,
      ];

      // assert
      expect(names, expected);
    });
  });
}
