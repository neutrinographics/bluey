package com.neutrinographics.bluey

/**
 * Plugin-internal error vocabulary. Every site in the Kotlin plugin that
 * would previously throw `IllegalStateException` or `SecurityException`
 * now throws a [BlueyAndroidError] case instead. Two extension helpers
 * in `Errors.kt` translate each case to a [FlutterError] with a known
 * Pigeon code at the FFI boundary — `toClientFlutterError()` for methods
 * dispatched through `ConnectionManager` / `Scanner`, `toServerFlutterError()`
 * for methods dispatched through `GattServer`.
 *
 * Never crosses the Pigeon boundary directly; always translated first.
 */
internal sealed class BlueyAndroidError(message: String) : Exception(message) {

    // --- Client-side preconditions → gatt-disconnected ---

    object DeviceNotConnected : BlueyAndroidError("Device not connected")

    object NoQueueForConnection : BlueyAndroidError("No queue for connection")

    /**
     * The Dart side issued a GATT op carrying a `characteristicHandle`
     * or `descriptorHandle`, but that handle is no longer in the per-device
     * handle table. Indicates the peer fired Service Changed (so
     * `onServiceChanged` cleared the table) and the caller is still holding
     * a stale [BlueyRemoteCharacteristic] / [BlueyRemoteDescriptor] reference
     * from the prior discovery. Surfaces as `gatt-handle-invalidated` so the
     * Dart adapter can throw `AttributeHandleInvalidatedException` and prompt
     * the caller to re-discover.
     */
    data class HandleInvalidated(val handle: Long) :
        BlueyAndroidError("GATT handle $handle not found in handle table")

    // --- Connect phase → gatt-timeout / bluey-unknown ---

    object ConnectionTimeout : BlueyAndroidError("Connection timeout")

    object GattConnectionCreationFailed : BlueyAndroidError("GATT connection creation failed")

    /**
     * A concurrent `connect(deviceId)` call was made while a previous connect
     * to the same address was still in flight. Surfaces as `bluey-unknown`
     * via the catch-all path in [Throwable.toClientFlutterError]. Calling
     * `connect()` twice on the same device is a programming error
     * (`BlueyConnection` should not do this); rejecting it loudly beats the
     * pre-fix behaviour where the second call returned a false-positive
     * success because `connections[deviceId]` was already populated.
     */
    data class ConnectInProgress(val deviceId: String) :
        BlueyAndroidError("Connect already in progress for $deviceId")

    // --- Sync setNotification reject → gatt-status-failed(0x01) ---

    data class SetNotificationFailed(val uuid: String) :
        BlueyAndroidError("Failed to set notification: $uuid")

    // --- Server-side request path → gatt-status-failed(0x0A) ---

    data class CentralNotFound(val id: String) :
        BlueyAndroidError("Central not found: $id")

    data class NoPendingRequest(val id: Long) :
        BlueyAndroidError("No pending request for id: $id")

    // --- Server-side setup → bluey-unknown ---

    object FailedToOpenGattServer : BlueyAndroidError("Failed to open GATT server")

    data class FailedToAddService(val uuid: String, val status: Int? = null) :
        BlueyAndroidError(
            if (status != null) "Failed to add service: $uuid (status=$status)"
            else "Failed to add service: $uuid"
        )

    // --- System state → bluey-unknown ---

    object BluetoothAdapterUnavailable : BlueyAndroidError("Bluetooth adapter unavailable")
    object BluetoothNotAvailableOrDisabled : BlueyAndroidError("Bluetooth not available or disabled")
    object BleScannerNotAvailable : BlueyAndroidError("BLE scanner not available")
    object BleAdvertisingNotSupported : BlueyAndroidError("BLE advertising not supported")

    data class InvalidDeviceAddress(val address: String) :
        BlueyAndroidError("Invalid device address: $address")

    data class AdvertisingStartFailed(val reason: String) : BlueyAndroidError(reason)

    /**
     * The Android BLE stack rejected the advertisement payload because it
     * exceeded the 31-byte (or 31 + 31-byte scan response) limit. Surfaces
     * as `bluey-advertise-data-too-large` so the Dart adapter can throw the
     * typed `PlatformAdvertiseDataTooLargeException`, which the domain
     * layer translates to `AdvertisingException(AdvertisingFailureReason.dataTooBig)`.
     */
    data class AdvertiseDataTooLarge(val reason: String) : BlueyAndroidError(reason)

    data class NotInitialized(val component: String) :
        BlueyAndroidError("$component not initialized")

    // --- Permission → bluey-permission-denied ---

    data class PermissionDenied(val permission: String) :
        BlueyAndroidError("Missing $permission permission")
}
