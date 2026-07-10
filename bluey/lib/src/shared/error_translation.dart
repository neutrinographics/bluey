import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;

import '../connection/lifecycle_client.dart';
import '../discovery/device_address.dart';
import '../lifecycle.dart' show lifecycleEvictionAttStatus;
import 'exceptions.dart';

/// Translates a platform-interface exception (or any other [Object]) into
/// the domain [BlueyException] hierarchy. Pure: usable from sync error
/// handlers, stream `onError` callbacks, and as the body of
/// [withErrorTranslation].
///
/// [operation] is a diagnostic label only — used in exception messages
/// and log lines, never in control flow. Do not branch on its value.
/// [address] is optional; non-GATT call sites (connect, scan) pass
/// `null`. It is the raw platform identifier (MAC on Android, UUID
/// string on iOS) — context-neutral, do not parse.
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
  String? address,
}) {
  if (error is BlueyException) return error;

  if (error is platform.GattOperationTimeoutException) {
    return GattTimeoutException(operation);
  }
  if (error is platform.GattOperationDisconnectedException) {
    return DisconnectedException(
      address ?? '',
      DisconnectReason.linkLoss,
    );
  }
  if (error is platform.GattOperationStatusFailedException) {
    if (error.status == lifecycleEvictionAttStatus) {
      // Server evicted us: our session is gone (heartbeat-silence timeout on
      // an inferring server). Surface as a connection-fatal disconnect so the
      // app reconnects via existing logic (I338). The connection layer drives
      // the actual teardown (LifecycleClient eviction fast-path / disconnect).
      return DisconnectedException(address ?? '', DisconnectReason.evictedByServer);
    }
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
  if (error is platform.PlatformConnectFailedException) {
    return ConnectionException(
      DeviceAddress(address ?? ''),
      switch (error.reason) {
        platform.PlatformConnectFailureReason.timeout =>
          ConnectionFailureReason.timeout,
        platform.PlatformConnectFailureReason.deviceNotFound =>
          ConnectionFailureReason.deviceNotFound,
        platform.PlatformConnectFailureReason.notConnectable =>
          ConnectionFailureReason.deviceNotConnectable,
        platform.PlatformConnectFailureReason.pairingFailed =>
          ConnectionFailureReason.pairingFailed,
        platform.PlatformConnectFailureReason.connectionLimitReached =>
          ConnectionFailureReason.connectionLimitReached,
        platform.PlatformConnectFailureReason.unknown =>
          ConnectionFailureReason.unknown,
      },
    );
  }
  if (error is platform.PlatformPermissionDeniedException) {
    return PermissionDeniedException([error.permission]);
  }
  if (error is platform.PlatformBluetoothUnavailableException) {
    return const BluetoothUnavailableException();
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
/// [address] is the raw platform identifier (MAC on Android, UUID
/// string on iOS) — context-neutral, do not parse.
Future<T> withErrorTranslation<T>(
  Future<T> Function() body, {
  required String operation,
  String? address,
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
      address: address,
    );
  } finally {
    lifecycleClient?.markUserOpEnded();
  }
}
