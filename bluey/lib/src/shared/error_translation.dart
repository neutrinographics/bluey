import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;

import '../connection/lifecycle_client.dart';
import 'exceptions.dart';
import 'uuid.dart';

/// Translates a platform-interface exception (or any other [Object]) into
/// the domain [BlueyException] hierarchy. Pure: usable from sync error
/// handlers, stream `onError` callbacks, and as the body of
/// [withErrorTranslation].
///
/// [operation] is a diagnostic label only — used in exception messages
/// and log lines, never in control flow. Do not branch on its value.
/// [deviceId] is optional; non-GATT call sites (connect, scan) pass
/// `null`.
///
/// Already-translated [BlueyException] instances pass through unchanged
/// — calling this twice on an exception is idempotent.
///
/// This is the anti-corruption layer between the Platform bounded
/// context (`bluey_platform_interface`) and the Domain bounded context
/// (`bluey`). It must be the *only* place these mappings live;
/// duplicating them elsewhere reintroduces the string-matching drift
/// problem we replaced this layer with.
BlueyException translatePlatformException(
  Object error, {
  required String operation,
  UUID? deviceId,
}) {
  if (error is BlueyException) return error;

  if (error is platform.GattOperationTimeoutException) {
    return GattTimeoutException(operation);
  }
  if (error is platform.GattOperationDisconnectedException) {
    return DisconnectedException(
      deviceId ?? UUID.short(0x0000),
      DisconnectReason.linkLoss,
    );
  }
  if (error is platform.GattOperationStatusFailedException) {
    return GattOperationFailedException(operation, error.status);
  }
  if (error is platform.GattOperationUnknownPlatformException) {
    if (error.code == 'gatt-handle-invalidated') {
      return AttributeHandleInvalidatedException();
    }
    return BlueyPlatformException(
      error.message ?? 'unknown platform error (${error.code})',
      code: error.code,
      cause: error,
    );
  }
  if (error is platform.PlatformPermissionDeniedException) {
    return PermissionDeniedException([error.permission]);
  }
  if (error is platform.PlatformAdvertiseDataTooLargeException) {
    return AdvertisingException(AdvertisingFailureReason.dataTooBig);
  }
  if (error is platform.PlatformRespondToRequestNotFoundException) {
    return RespondNotFoundException(error.message);
  }
  if (error is PlatformException) {
    return BlueyPlatformException(
      error.message ?? 'platform error (${error.code})',
      code: error.code,
      cause: error,
    );
  }

  // Defensive backstop: anything else gets wrapped, never leaked raw.
  return BlueyPlatformException(error.toString(), cause: error);
}

/// Future-shaped sugar over [translatePlatformException], with optional
/// lifecycle-accounting hooks for user-op accounting.
///
/// Lifecycle hooks fire iff [lifecycleClient] is non-null:
/// - `markUserOpStarted()` before the body
/// - `recordActivity()` on success
/// - `recordUserOpFailure(originalError)` before re-throw on failure
/// - `markUserOpEnded()` in finally
///
/// [recordUserOpFailure] is intentionally called with the *original*
/// platform exception (not the translated domain exception). The
/// filter inside `recordUserOpFailure` does an
/// `is platform.GattOperationTimeoutException` check that would not
/// match the translated `GattTimeoutException`.
///
/// [operation] is a diagnostic label only — used in exception messages
/// and log lines, never in control flow. Do not branch on its value.
Future<T> withErrorTranslation<T>(
  Future<T> Function() body, {
  required String operation,
  UUID? deviceId,
  LifecycleClient? lifecycleClient,
}) async {
  lifecycleClient?.markUserOpStarted();
  try {
    final result = await body();
    lifecycleClient?.recordActivity();
    return result;
  } catch (error) {
    lifecycleClient?.recordUserOpFailure(error);
    throw translatePlatformException(
      error,
      operation: operation,
      deviceId: deviceId,
    );
  } finally {
    lifecycleClient?.markUserOpEnded();
  }
}
