import 'package:meta/meta.dart';

import '../../../shared/domain/failure.dart';
import 'link_end.dart';

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

  @override
  String toString() => message;
}

/// A connect ended without a link.
final class ConnectFailed extends ConnectionFailure {
  const ConnectFailed(this.reason);

  /// Why the link was not opened.
  final ConnectFailureReason reason;

  @override
  String get message => 'The connect failed: ${reason.name}.';

  @override
  bool operator ==(Object other) =>
      other is ConnectFailed && other.reason == reason;

  @override
  int get hashCode => Object.hash(ConnectFailed, reason);
}

/// The link an operation needed has ended, so the operation cannot run on it.
final class LinkEnded extends ConnectionFailure {
  const LinkEnded(this.end);

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
  bool operator ==(Object other) => other is LinkEnded && other.end == end;

  @override
  int get hashCode => Object.hash(LinkEnded, end);
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

  /// The operation that timed out, named for a log.
  final String operation;

  @override
  String get message => 'The operation $operation timed out.';

  @override
  bool operator ==(Object other) =>
      other is OperationTimedOut && other.operation == operation;

  @override
  int get hashCode => Object.hash(OperationTimedOut, operation);
}

/// The radio answered an operation with a status other than success.
final class OperationRejected extends ConnectionFailure {
  const OperationRejected(this.operation, this.status);

  /// The operation that was rejected, named for a log.
  final String operation;

  /// The platform's status code, which an app receives unchanged.
  final int status;

  @override
  String get message =>
      'The operation $operation was rejected with status $status.';

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
      other.code == code &&
      other.cause == cause;

  @override
  int get hashCode =>
      Object.hash(UnexpectedPlatformFailure, detail, code, cause);
}
