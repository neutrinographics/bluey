import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:bluey/src/shared/domain/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';

/// Names the subtype, so the test fails to compile when the family gains a
/// member this list does not name.
String _kindOf(ConnectionFailure failure) => switch (failure) {
  ConnectFailed() => 'connect failed',
  LinkHadEnded() => 'link ended',
  RadioUnavailable() => 'radio unavailable',
  PermissionMissing() => 'permission missing',
  OperationTimedOut() => 'operation timed out',
  OperationRejected() => 'operation rejected',
  UnexpectedPlatformFailure() => 'unexpected platform failure',
  FeatureUnsupported() => 'feature unsupported',
  MtuAboveMaximum() => 'MTU above maximum',
};

void main() {
  final cause = StateError('platform said no');

  final sameValues = <String, (ConnectionFailure, ConnectionFailure)>{
    'ConnectFailed': (
      const ConnectFailed(ConnectFailureReason.timeout),
      const ConnectFailed(ConnectFailureReason.timeout),
    ),
    'LinkHadEnded': (
      const LinkHadEnded(EndedByDrop()),
      const LinkHadEnded(EndedByDrop()),
    ),
    'RadioUnavailable': (const RadioUnavailable(), const RadioUnavailable()),
    'PermissionMissing': (
      const PermissionMissing('bluetoothConnect'),
      const PermissionMissing('bluetoothConnect'),
    ),
    'OperationTimedOut': (
      const OperationTimedOut(LinkOperation.open),
      const OperationTimedOut(LinkOperation.open),
    ),
    'OperationRejected': (
      const OperationRejected(LinkOperation.close, 133),
      const OperationRejected(LinkOperation.close, 133),
    ),
    'UnexpectedPlatformFailure': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
    ),
    'UnexpectedPlatformFailure whatever its cause': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('boom', code: 'E1', cause: StateError('other')),
    ),
    'FeatureUnsupported': (
      const FeatureUnsupported(LinkOperation.negotiateMtu),
      const FeatureUnsupported(LinkOperation.negotiateMtu),
    ),
    'MtuAboveMaximum': (
      MtuAboveMaximum(requested: Mtu(248), maximum: 247),
      MtuAboveMaximum(requested: Mtu(248), maximum: 247),
    ),
  };

  final otherValues = <String, (ConnectionFailure, ConnectionFailure)>{
    'ConnectFailed': (
      const ConnectFailed(ConnectFailureReason.timeout),
      const ConnectFailed(ConnectFailureReason.deviceNotFound),
    ),
    'LinkHadEnded': (
      const LinkHadEnded(EndedByDrop()),
      const LinkHadEnded(EndedOnRequest()),
    ),
    'RadioUnavailable': (
      const RadioUnavailable(),
      const OperationTimedOut(LinkOperation.open),
    ),
    'PermissionMissing': (
      const PermissionMissing('bluetoothConnect'),
      const PermissionMissing('bluetoothScan'),
    ),
    'OperationTimedOut': (
      const OperationTimedOut(LinkOperation.open),
      const OperationTimedOut(LinkOperation.close),
    ),
    'OperationRejected by operation': (
      const OperationRejected(LinkOperation.close, 133),
      const OperationRejected(LinkOperation.open, 133),
    ),
    'OperationRejected by status': (
      const OperationRejected(LinkOperation.close, 133),
      const OperationRejected(LinkOperation.close, 8),
    ),
    'UnexpectedPlatformFailure by detail': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('bang', code: 'E1', cause: cause),
    ),
    'UnexpectedPlatformFailure by code': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('boom', code: 'E2', cause: cause),
    ),
    'FeatureUnsupported': (
      const FeatureUnsupported(LinkOperation.negotiateMtu),
      const FeatureUnsupported(LinkOperation.open),
    ),
    'MtuAboveMaximum by requested': (
      MtuAboveMaximum(requested: Mtu(248), maximum: 247),
      MtuAboveMaximum(requested: Mtu(249), maximum: 247),
    ),
    'MtuAboveMaximum by maximum': (
      MtuAboveMaximum(requested: Mtu(248), maximum: 247),
      MtuAboveMaximum(requested: Mtu(248), maximum: 185),
    ),
  };

  group('ConnectionFailure equality', () {
    for (final MapEntry(key: name, value: (first, second))
        in sameValues.entries) {
      test('$name equals another of the same values', () {
        // arrange
        final failure = first;

        // act
        final equal = failure == second;

        // assert
        expect(equal, isTrue);
        expect(failure.hashCode, second.hashCode);
      });
    }

    for (final MapEntry(key: name, value: (first, second))
        in otherValues.entries) {
      test('$name differs from one of other values', () {
        // arrange
        final failure = first;

        // act
        final equal = failure == second;

        // assert
        expect(equal, isFalse);
      });
    }
  });

  group('ConnectionFailure message', () {
    final sentences = <ConnectionFailure, String>{
      const ConnectFailed(ConnectFailureReason.timeout):
          'The connect failed: the device did not answer in time.',
      const ConnectFailed(ConnectFailureReason.deviceNotFound):
          'The connect failed: the device was not found.',
      const ConnectFailed(ConnectFailureReason.deviceNotConnectable):
          'The connect failed: the device does not accept connections.',
      const ConnectFailed(ConnectFailureReason.pairingFailed):
          'The connect failed: pairing with the device failed.',
      const ConnectFailed(ConnectFailureReason.connectionLimitReached):
          'The connect failed: the platform holds as many links as it can.',
      const ConnectFailed(ConnectFailureReason.unknown):
          'The connect failed for a reason the platform did not give.',
      const LinkHadEnded(EndedOnRequest()):
          'The link ended: a disconnect was requested.',
      const LinkHadEnded(EndedByDrop()): 'The link ended: it was lost.',
      const LinkHadEnded(EndedByRadioOutage(RadioOutage.off)):
          'The link ended: the radio became unusable (off).',
      const RadioUnavailable(): 'The radio is unavailable.',
      const PermissionMissing('bluetoothConnect'):
          'The permission bluetoothConnect is missing.',
      const OperationTimedOut(LinkOperation.open):
          'Opening the link timed out.',
      const OperationTimedOut(LinkOperation.close):
          'Closing the link timed out.',
      const OperationRejected(LinkOperation.open, 133):
          'Opening the link was rejected with status 133.',
      const OperationRejected(LinkOperation.close, 8):
          'Closing the link was rejected with status 8.',
      const UnexpectedPlatformFailure('boom'):
          'The platform failed unexpectedly: boom.',
      const UnexpectedPlatformFailure('boom', code: 'E1'):
          'The platform failed unexpectedly (E1): boom.',
      const OperationTimedOut(LinkOperation.negotiateMtu):
          'Negotiating the MTU timed out.',
      const FeatureUnsupported(LinkOperation.negotiateMtu):
          'Negotiating the MTU is not supported on this platform.',
      const OperationTimedOut(LinkOperation.readWritePayloadLimit):
          'Reading the write payload limit timed out.',
      const OperationRejected(LinkOperation.readSignalStrength, 133):
          'Reading the signal strength was rejected with status 133.',
      const FeatureUnsupported(LinkOperation.readBondState):
          'Reading the bond state is not supported on this platform.',
      const FeatureUnsupported(LinkOperation.followBondState):
          'Following the bond state is not supported on this platform.',
      const OperationRejected(LinkOperation.bond, 133):
          'Bonding was rejected with status 133.',
      const OperationTimedOut(LinkOperation.removeBond):
          'Removing the bond timed out.',
      const OperationTimedOut(LinkOperation.readPhy):
          'Reading the PHY timed out.',
      const FeatureUnsupported(LinkOperation.readTransmitPhy):
          'Reading the transmit PHY is not supported on this platform.',
      const FeatureUnsupported(LinkOperation.readReceivePhy):
          'Reading the receive PHY is not supported on this platform.',
      const FeatureUnsupported(LinkOperation.followPhy):
          'Following the PHY is not supported on this platform.',
      const OperationRejected(LinkOperation.requestPhy, 133):
          'Requesting a PHY was rejected with status 133.',
      const OperationTimedOut(LinkOperation.readConnectionParameters):
          'Reading the connection parameters timed out.',
      const OperationRejected(LinkOperation.requestConnectionParameters, 133):
          'Requesting connection parameters was rejected with status 133.',
      MtuAboveMaximum(requested: Mtu(248), maximum: 247):
          "An MTU of 248 is above this platform's maximum of 247.",
    };

    for (final MapEntry(key: failure, value: sentence) in sentences.entries) {
      test('${_kindOf(failure)} reads "$sentence"', () {
        // arrange
        final Failure asFailure = failure;

        // act
        final message = asFailure.message;

        // assert
        expect(message, sentence);
      });
    }
  });
}
