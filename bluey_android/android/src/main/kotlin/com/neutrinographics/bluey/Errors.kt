package com.neutrinographics.bluey

/**
 * Translates a throwable raised by the Kotlin plugin into a [FlutterError]
 * with one of the well-known Pigeon codes the Dart adapter knows how to
 * handle. Use the *client* variant at call sites dispatched through
 * `ConnectionManager` / `Scanner` (client-role); use the *server* variant
 * at call sites dispatched through `GattServer` / `Advertiser` (server-role).
 *
 * An already-translated [FlutterError] passes through unchanged — the
 * inner layers (`GattOpQueue`, `ConnectionManager.statusFailedError`) emit
 * their own `gatt-*` codes and we must NOT overwrite them with
 * `bluey-unknown` when those errors bubble up through the BlueyPlugin
 * wrapper's `recoverCatching` path.
 *
 * Anything that isn't a [BlueyAndroidError] or [FlutterError] falls
 * through to the `bluey-unknown` code with the throwable's message
 * (or class name, if the message is null) so user code never sees raw
 * `PlatformException` regardless of what surfaces.
 */
internal fun Throwable.toClientFlutterError(): FlutterError = when (this) {
    is FlutterError -> this
    is BlueyAndroidError.PermissionDenied ->
        FlutterError("bluey-permission-denied", message, permission)
    is BlueyAndroidError.DeviceNotConnected,
    is BlueyAndroidError.NoQueueForConnection ->
        FlutterError("gatt-disconnected", message, null)
    is BlueyAndroidError.HandleInvalidated ->
        FlutterError("gatt-handle-invalidated", message, null)
    is BlueyAndroidError.ConnectionTimeout ->
        FlutterError("gatt-timeout", message, null)
    is BlueyAndroidError.SetNotificationFailed ->
        FlutterError("gatt-status-failed", message, 0x01)
    is BlueyAndroidError ->
        FlutterError("bluey-unknown", message, null)
    else ->
        FlutterError("bluey-unknown", message ?: javaClass.simpleName, null)
}

internal fun Throwable.toServerFlutterError(): FlutterError = when (this) {
    is FlutterError -> this
    is BlueyAndroidError.PermissionDenied ->
        FlutterError("bluey-permission-denied", message, permission)
    is BlueyAndroidError.CentralNotFound,
    is BlueyAndroidError.NoPendingRequest ->
        FlutterError("gatt-status-failed", message, 0x0A)
    is BlueyAndroidError.AdvertiseDataTooLarge ->
        FlutterError("bluey-advertise-data-too-large", message, null)
    is BlueyAndroidError ->
        FlutterError("bluey-unknown", message, null)
    else ->
        FlutterError("bluey-unknown", message ?: javaClass.simpleName, null)
}
