import '../../features/connection/application/connection_log_words.dart';
import '../../features/connection/domain/connection_failure.dart';
import '../../features/connection/domain/link_end.dart';
import '../../features/connection/domain/link_operation.dart';
import '../../platform/bluetooth_state.dart';
import '../../shared/domain/device_address.dart';
import '../../shared/domain/either.dart';
import '../../shared/exceptions.dart';

/// The exception an app gets for [failure], so moving an operation below the
/// edge changes nothing an app catches.
///
/// A rejected operation reads as rejected whatever its status, unlike today's
/// shared translation, which reads `0x80` as an eviction: only a GATT read or
/// write can be answered that way by a Bluey server, and Connection does not
/// know the lifecycle protocol.
///
/// [platform] is the platform's name, which an app reads in the exception for
/// an operation the platform cannot do.
BlueyException connectionFailureAsException(
  ConnectionFailure failure, {
  required DeviceAddress device,
  required String platform,
}) => switch (failure) {
  ConnectFailed(:final reason) => ConnectionException(
    device,
    _connectionFailureReasonOf(reason),
  ),
  LinkHadEnded(:final end) => linkEndAsException(end, device: device),
  RadioUnavailable() => const BluetoothUnavailableException(),
  PermissionMissing(:final permission) => PermissionDeniedException([
    permission,
  ]),
  OperationTimedOut(:final operation) => GattTimeoutException(
    operationWordOf(operation),
  ),
  OperationRejected(:final operation, :final status) =>
    GattOperationFailedException(operationWordOf(operation), status),
  UnexpectedPlatformFailure(:final detail, :final code, :final cause) =>
    BlueyPlatformException(detail, code: code, cause: cause),
  FeatureUnsupported(:final operation) => UnsupportedOperationException(
    operationWordOf(operation),
    platform,
  ),
  MtuAboveMaximum(:final maximum) => UnsupportedOperationException(
    '${operationWordOf(LinkOperation.negotiateMtu)} above $maximum',
    platform,
  ),
};

/// The exception an app gets for using a link that has ended, so a caller
/// holding the end itself, not a failure, reads it as the operation would.
///
/// A radio outage makes the connection stale rather than disconnected: the
/// app must build a new one once the radio is back.
BlueyException linkEndAsException(
  LinkEnd end, {
  required DeviceAddress device,
}) => switch (end) {
  EndedOnRequest() => DisconnectedException(
    device.value,
    DisconnectReason.requested,
  ),
  EndedByDrop() => DisconnectedException(
    device.value,
    DisconnectReason.linkLoss,
  ),
  EndedByRadioOutage(:final outage) => StaleHandleException(
    cause: AdapterTransitionInvalidation(_bluetoothStateOf(outage)),
    instanceType: InvalidatedInstance.connection,
  ),
};

/// The value, or the failure thrown as the exception an app gets today.
T valueOrThrow<T>(
  Either<ConnectionFailure, T> answer, {
  required DeviceAddress device,
  required String platform,
}) => answer.fold(
  (failure) =>
      throw connectionFailureAsException(
        failure,
        device: device,
        platform: platform,
      ),
  (value) => value,
);

ConnectionFailureReason _connectionFailureReasonOf(
  ConnectFailureReason reason,
) => switch (reason) {
  ConnectFailureReason.timeout => ConnectionFailureReason.timeout,
  ConnectFailureReason.deviceNotFound => ConnectionFailureReason.deviceNotFound,
  ConnectFailureReason.deviceNotConnectable =>
    ConnectionFailureReason.deviceNotConnectable,
  ConnectFailureReason.pairingFailed => ConnectionFailureReason.pairingFailed,
  ConnectFailureReason.connectionLimitReached =>
    ConnectionFailureReason.connectionLimitReached,
  ConnectFailureReason.unknown => ConnectionFailureReason.unknown,
};

BluetoothState _bluetoothStateOf(RadioOutage outage) => switch (outage) {
  RadioOutage.off => BluetoothState.off,
  RadioOutage.unauthorized => BluetoothState.unauthorized,
  RadioOutage.unsupported => BluetoothState.unsupported,
  RadioOutage.unknown => BluetoothState.unknown,
};
