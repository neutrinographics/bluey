import '../../features/discovery/domain/scan_failure.dart';
import '../../shared/exceptions.dart';
import 'scan_failed_exception.dart';

/// The exception an app gets for [failure], so a failure below the edge
/// reaches an app as the exception it already catches for the same cause.
BlueyException scanFailureAsException(ScanFailure failure) => switch (failure) {
  ScanRefused(:final reason) => ScanFailedException(_reasonOf(reason)),
  ScanPermissionMissing(:final permission) => PermissionDeniedException([
    permission,
  ]),
  ScanRadioUnavailable() => const BluetoothUnavailableException(),
  UnexpectedScanFailure(:final detail, :final code, :final cause) =>
    BlueyPlatformException(detail, code: code, cause: cause),
};

ScanFailureReason _reasonOf(ScanRefusalReason reason) => switch (reason) {
  ScanRefusalReason.alreadyStarted => ScanFailureReason.alreadyStarted,
  ScanRefusalReason.registrationFailed => ScanFailureReason.registrationFailed,
  ScanRefusalReason.internalError => ScanFailureReason.internalError,
  ScanRefusalReason.unsupported => ScanFailureReason.unsupported,
  ScanRefusalReason.outOfHardwareResources =>
    ScanFailureReason.outOfHardwareResources,
  ScanRefusalReason.startedTooOften => ScanFailureReason.startedTooOften,
  ScanRefusalReason.unknown => ScanFailureReason.unknown,
};
