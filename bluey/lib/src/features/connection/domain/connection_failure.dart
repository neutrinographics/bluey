import 'package:meta/meta.dart';

import '../../../shared/domain/failure.dart';
import 'link_end.dart';
import 'link_operation.dart';
import 'value_objects/mtu.dart';

/// Why a connect did not open a link, in Connection's words, so the edge can
/// tell an app that the device was out of reach from one that refused.
enum ConnectFailureReason {
  timeout,
  deviceNotFound,
  deviceNotConnectable,
  pairingFailed,
  connectionLimitReached,
  unknown,
}

/// Everything a Connection operation can answer instead of its value.
///
/// The family is sealed so the edge's translator switches over it with no
/// default: a new kind of failure does not compile until the edge says which
/// exception an app gets for it. Each failure is equal by value.
@immutable
sealed class ConnectionFailure implements Failure {
  const ConnectionFailure();
}

/// A connect ended without a link.
final class ConnectFailed extends ConnectionFailure {
  const ConnectFailed(this.reason);

  /// Why the link was not opened.
  final ConnectFailureReason reason;

  @override
  String get message => switch (reason) {
    ConnectFailureReason.timeout =>
      'The connect failed: the device did not answer in time.',
    ConnectFailureReason.deviceNotFound =>
      'The connect failed: the device was not found.',
    ConnectFailureReason.deviceNotConnectable =>
      'The connect failed: the device does not accept connections.',
    ConnectFailureReason.pairingFailed =>
      'The connect failed: pairing with the device failed.',
    ConnectFailureReason.connectionLimitReached =>
      'The connect failed: the platform holds as many links as it can.',
    ConnectFailureReason.unknown =>
      'The connect failed for a reason the platform did not give.',
  };

  @override
  bool operator ==(Object other) =>
      other is ConnectFailed && other.reason == reason;

  @override
  int get hashCode => Object.hash(ConnectFailed, reason);
}

/// The link an operation needed has ended, so the operation cannot run on it.
final class LinkHadEnded extends ConnectionFailure {
  const LinkHadEnded(this.end);

  /// How the link ended, which decides whether the app is told it asked for
  /// the disconnect or lost the link.
  final LinkEnd end;

  @override
  String get message => switch (end) {
    EndedOnRequest() => 'The link ended: a disconnect was requested.',
    EndedByDrop() => 'The link ended: it was lost.',
    EndedByRadioOutage(:final outage) =>
      'The link ended: the radio became unusable (${outage.name}).',
  };

  @override
  bool operator ==(Object other) => other is LinkHadEnded && other.end == end;

  @override
  int get hashCode => Object.hash(LinkHadEnded, end);
}

/// The radio cannot be used right now, so nothing was asked of it.
final class RadioUnavailable extends ConnectionFailure {
  const RadioUnavailable();

  @override
  String get message => 'The radio is unavailable.';

  @override
  bool operator ==(Object other) => other is RadioUnavailable;

  @override
  int get hashCode => (RadioUnavailable).hashCode;
}

/// The platform refused because the app lacks a permission.
final class PermissionMissing extends ConnectionFailure {
  const PermissionMissing(this.permission);

  /// The platform's name for the permission, as the platform reported it.
  final String permission;

  @override
  String get message => 'The permission $permission is missing.';

  @override
  bool operator ==(Object other) =>
      other is PermissionMissing && other.permission == permission;

  @override
  int get hashCode => Object.hash(PermissionMissing, permission);
}

/// The radio did not answer an operation in time; the link may still be open.
final class OperationTimedOut extends ConnectionFailure {
  const OperationTimedOut(this.operation);

  /// The operation that timed out.
  final LinkOperation operation;

  @override
  String get message => '${_attemptOf(operation)} timed out.';

  @override
  bool operator ==(Object other) =>
      other is OperationTimedOut && other.operation == operation;

  @override
  int get hashCode => Object.hash(OperationTimedOut, operation);
}

/// The radio answered an operation with a status other than success.
final class OperationRejected extends ConnectionFailure {
  const OperationRejected(this.operation, this.status);

  /// The operation that was rejected.
  final LinkOperation operation;

  /// The platform's status code, which an app receives unchanged.
  final int status;

  @override
  String get message =>
      '${_attemptOf(operation)} was rejected with status $status.';

  @override
  bool operator ==(Object other) =>
      other is OperationRejected &&
      other.operation == operation &&
      other.status == status;

  @override
  int get hashCode => Object.hash(OperationRejected, operation, status);
}

/// The platform failed in a way Connection does not recognise; the [cause]
/// is kept so the edge can hand it on rather than lose it.
///
/// Two failures are equal when they say the same thing: a cause is rarely
/// equal by value, so counting it would make every such failure unique.
final class UnexpectedPlatformFailure extends ConnectionFailure {
  const UnexpectedPlatformFailure(this.detail, {this.code, this.cause});

  /// What the platform said went wrong.
  final String detail;

  /// The platform's error code, when it gave one.
  final String? code;

  /// What the platform threw, when there was something.
  final Object? cause;

  @override
  String get message =>
      code == null
          ? 'The platform failed unexpectedly: $detail.'
          : 'The platform failed unexpectedly ($code): $detail.';

  @override
  bool operator ==(Object other) =>
      other is UnexpectedPlatformFailure &&
      other.detail == detail &&
      other.code == code;

  @override
  int get hashCode => Object.hash(UnexpectedPlatformFailure, detail, code);
}

/// The platform cannot do [operation] at all, so nothing was asked of the
/// radio.
final class FeatureUnsupported extends ConnectionFailure {
  const FeatureUnsupported(this.operation);

  /// The operation this platform lacks.
  final LinkOperation operation;

  @override
  String get message =>
      '${_attemptOf(operation)} is not supported on this platform.';

  @override
  bool operator ==(Object other) =>
      other is FeatureUnsupported && other.operation == operation;

  @override
  int get hashCode => Object.hash(FeatureUnsupported, operation);
}

/// The MTU asked for is one the Bluetooth specification allows but this
/// platform will not ask for.
final class MtuAboveMaximum extends ConnectionFailure {
  const MtuAboveMaximum({required this.requested, required this.maximum});

  /// The MTU that was asked for.
  final Mtu requested;

  /// The largest MTU this platform asks for.
  final int maximum;

  @override
  String get message =>
      "An MTU of ${requested.value} is above this platform's maximum of "
      '$maximum.';

  @override
  bool operator ==(Object other) =>
      other is MtuAboveMaximum &&
      other.requested == requested &&
      other.maximum == maximum;

  @override
  int get hashCode => Object.hash(MtuAboveMaximum, requested, maximum);
}

/// The attempt at [operation] as a message opens it, for a person reading
/// the failure rather than an app matching it.
String _attemptOf(LinkOperation operation) => switch (operation) {
  LinkOperation.open => 'Opening the link',
  LinkOperation.close => 'Closing the link',
  LinkOperation.negotiateMtu => 'Negotiating the MTU',
  LinkOperation.readWritePayloadLimit => 'Reading the write payload limit',
  LinkOperation.readSignalStrength => 'Reading the signal strength',
};
