import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_end.dart';
import '../../domain/link_operation.dart';

/// Everything BlueyPlatform can throw at a Connection operation, in
/// Connection's words, so no platform exception climbs above the adapters.
///
/// A GATT status is passed on whatever it is: what a status means to the
/// lifecycle protocol is not Connection's to know. Anything the platform
/// should not throw is still answered, as an [UnexpectedPlatformFailure]
/// that keeps what was thrown.
ConnectionFailure connectionFailureFrom(
  Object error, {
  required LinkOperation operation,
}) => switch (error) {
  GattOperationTimeoutException() => OperationTimedOut(operation),
  GattOperationDisconnectedException() => const LinkHadEnded(EndedByDrop()),
  GattOperationStatusFailedException(:final status) => OperationRejected(
    operation,
    status,
  ),
  GattOperationUnknownPlatformException(:final code, :final message) =>
    UnexpectedPlatformFailure(
      message ?? 'unknown platform error ($code)',
      code: code,
      cause: error,
    ),
  PlatformConnectFailedException(:final reason) => ConnectFailed(
    _connectReasonOf(reason),
  ),
  PlatformPermissionDeniedException(:final permission) => PermissionMissing(
    permission,
  ),
  PlatformBluetoothUnavailableException() => const RadioUnavailable(),
  PlatformException(:final code, :final message) => UnexpectedPlatformFailure(
    message ?? 'platform error ($code)',
    code: code,
    cause: error,
  ),
  _ => UnexpectedPlatformFailure(error.toString(), cause: error),
};

/// Runs one platform call and answers what it threw as a failure, so an
/// adapter's every call reads the same way and none forgets to translate.
///
/// A programming error under the call is answered too, as an
/// [UnexpectedPlatformFailure], because the caller is promised a value for
/// anything the call throws.
Future<Either<ConnectionFailure, T>> answering<T>(
  LinkOperation operation,
  Future<T> Function() call,
) async {
  try {
    return Right(await call());
  } on Object catch (error) {
    return Left(connectionFailureFrom(error, operation: operation));
  }
}

ConnectFailureReason _connectReasonOf(PlatformConnectFailureReason reason) =>
    switch (reason) {
      PlatformConnectFailureReason.timeout => ConnectFailureReason.timeout,
      PlatformConnectFailureReason.deviceNotFound =>
        ConnectFailureReason.deviceNotFound,
      PlatformConnectFailureReason.notConnectable =>
        ConnectFailureReason.deviceNotConnectable,
      PlatformConnectFailureReason.pairingFailed =>
        ConnectFailureReason.pairingFailed,
      PlatformConnectFailureReason.connectionLimitReached =>
        ConnectFailureReason.connectionLimitReached,
      PlatformConnectFailureReason.unknown => ConnectFailureReason.unknown,
    };
