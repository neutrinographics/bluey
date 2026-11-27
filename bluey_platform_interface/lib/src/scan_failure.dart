/// Why the platform refused to run a scan, in the platform's own terms.
///
/// The first six are Android's `SCAN_FAILED_*` codes 1 to 6 in order; any
/// other code is [unknown] and travels with [PlatformScanFailedException.code].
enum PlatformScanFailureReason {
  alreadyStarted,
  registrationFailed,
  internalError,
  unsupported,
  outOfHardwareResources,
  startedTooOften,
  unknown,
}

/// A scan the platform refused to start or lost, delivered as an error on the
/// stream `BlueyPlatform.scan` returned, since no other channel reaches the
/// app that asked.
///
/// The domain layer translates this into Discovery's scan failure.
class PlatformScanFailedException implements Exception {
  final PlatformScanFailureReason reason;

  /// The platform's raw code, kept when [reason] is
  /// [PlatformScanFailureReason.unknown] so a log can still say which.
  final int? code;

  const PlatformScanFailedException(this.reason, {this.code});

  @override
  String toString() =>
      'PlatformScanFailedException: ${reason.name}'
      '${code != null ? ' (code $code)' : ''}';
}
