import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/infrastructure/platform_errors.dart' as platform;
import '../../domain/scan_failure.dart';

/// Everything BlueyPlatform can throw at a scan, in Discovery's words, so no
/// platform exception climbs above the adapter.
///
/// Anything the platform should not throw is still answered, as an
/// [UnexpectedScanFailure] that keeps what was thrown.
ScanFailure scanFailureFrom(Object error) => switch (error) {
  PlatformScanFailedException(:final reason) => ScanRefused(
    ScanRefusalReason.values.byName(reason.name),
  ),
  _ => switch (platform.platformErrorOf(error)) {
    platform.PermissionDenied(:final permission) => ScanPermissionMissing(
      permission,
    ),
    platform.RadioUnavailable() => const ScanRadioUnavailable(),
    platform.Unexpected(:final detail, :final code, :final cause) =>
      UnexpectedScanFailure(detail, code: code, cause: cause),
  },
};
