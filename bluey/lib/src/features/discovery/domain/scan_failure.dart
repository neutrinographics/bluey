import 'package:meta/meta.dart';

import '../../../shared/domain/failure.dart';

/// Why the platform refused to start a scan, in Discovery's words.
enum ScanRefusalReason {
  alreadyStarted,
  registrationFailed,
  internalError,
  unsupported,
  outOfHardwareResources,
  startedTooOften,
  unknown,
}

/// Everything a scan can answer or end with instead of results.
///
/// Sealed so the edge's translator switches over it with no default: a new
/// kind does not compile until the edge says what an app is told. Each
/// failure is equal by value.
@immutable
sealed class ScanFailure implements Failure {
  const ScanFailure();
}

/// The platform refused to start the scan.
final class ScanRefused extends ScanFailure {
  const ScanRefused(this.reason);

  final ScanRefusalReason reason;

  @override
  String get message => switch (reason) {
    ScanRefusalReason.alreadyStarted =>
      'The scan was refused: the platform is already scanning for it.',
    ScanRefusalReason.registrationFailed =>
      'The scan was refused: the platform could not register it.',
    ScanRefusalReason.internalError =>
      'The scan was refused: the platform failed internally.',
    ScanRefusalReason.unsupported =>
      'The scan was refused: this device does not support it.',
    ScanRefusalReason.outOfHardwareResources =>
      'The scan was refused: the platform has no scan resources left.',
    ScanRefusalReason.startedTooOften =>
      'The scan was refused: scans were started too often.',
    ScanRefusalReason.unknown =>
      'The scan was refused for a reason the platform did not give.',
  };

  @override
  bool operator ==(Object other) =>
      other is ScanRefused && other.reason == reason;

  @override
  int get hashCode => Object.hash(ScanRefused, reason);
}

/// The app has not been granted what scanning needs.
final class ScanPermissionMissing extends ScanFailure {
  const ScanPermissionMissing(this.permission);

  /// The platform's name for what was not granted.
  final String permission;

  @override
  String get message => 'The scan needs the $permission permission.';

  @override
  bool operator ==(Object other) =>
      other is ScanPermissionMissing && other.permission == permission;

  @override
  int get hashCode => Object.hash(ScanPermissionMissing, permission);
}

/// The radio is off or cannot scan, so no scan can run.
final class ScanRadioUnavailable extends ScanFailure {
  const ScanRadioUnavailable();

  @override
  String get message => 'The scan cannot run: the radio is not available.';

  @override
  bool operator ==(Object other) => other is ScanRadioUnavailable;

  @override
  int get hashCode => (ScanRadioUnavailable).hashCode;
}

/// A failure Discovery has no word for; keeps the platform's detail and
/// cause so nothing is lost on the way to the app.
final class UnexpectedScanFailure extends ScanFailure {
  const UnexpectedScanFailure(this.detail, {this.code, required this.cause});

  final String detail;

  /// The platform's own code, when it gave one.
  final String? code;

  final Object cause;

  @override
  String get message => 'The scan failed unexpectedly: $detail.';

  @override
  bool operator ==(Object other) =>
      other is UnexpectedScanFailure &&
      other.detail == detail &&
      other.code == code &&
      other.cause == cause;

  @override
  int get hashCode => Object.hash(UnexpectedScanFailure, detail, code, cause);
}
