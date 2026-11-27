import '../../shared/exceptions.dart';

/// Why the platform refused to start a scan.
enum ScanFailureReason {
  alreadyStarted,
  registrationFailed,
  internalError,
  unsupported,
  outOfHardwareResources,
  startedTooOften,
  unknown,
}

/// The platform refused to start a scan; the scan's stream carries it and
/// ends, and the scanner can scan again.
///
/// A platform exception, so an app that already matches
/// [BlueyPlatformException] keeps working and an exhaustive switch over
/// [BlueyException] needs no new branch; an app that wants the [reason]
/// matches this class.
final class ScanFailedException extends BlueyPlatformException {
  ScanFailedException(this.reason)
    : super('The scan was refused: ${reason.name}');

  final ScanFailureReason reason;
}
