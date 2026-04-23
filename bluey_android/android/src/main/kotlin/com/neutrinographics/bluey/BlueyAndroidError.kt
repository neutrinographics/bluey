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

    data class CharacteristicNotFound(val uuid: String) :
        BlueyAndroidError("Characteristic not found: $uuid")

    data class DescriptorNotFound(val uuid: String) :
        BlueyAndroidError("Descriptor not found: $uuid")

    // --- Connect phase → gatt-timeout / bluey-unknown ---

    object ConnectionTimeout : BlueyAndroidError("Connection timeout")

    object GattConnectionCreationFailed : BlueyAndroidError("GATT connection creation failed")

    // --- Sync setNotification reject → gatt-status-failed(0x01) ---

    data class SetNotificationFailed(val uuid: String) :
        BlueyAndroidError("Failed to set notification: $uuid")

    // --- Server-side request path → gatt-status-failed(0x0A) ---

    data class CentralNotFound(val id: String) :
        BlueyAndroidError("Central not found: $id")

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

    data class NotInitialized(val component: String) :
        BlueyAndroidError("$component not initialized")

    // --- Permission → bluey-permission-denied ---

    data class PermissionDenied(val permission: String) :
        BlueyAndroidError("Missing $permission permission")
}
