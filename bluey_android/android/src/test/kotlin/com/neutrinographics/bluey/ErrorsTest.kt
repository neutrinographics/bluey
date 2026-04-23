package com.neutrinographics.bluey

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ErrorsTest {

    // --- Client-side mappings ---

    @Test
    fun `DeviceNotConnected to gatt-disconnected (client)`() {
        val e = BlueyAndroidError.DeviceNotConnected.toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `NoQueueForConnection to gatt-disconnected (client)`() {
        val e = BlueyAndroidError.NoQueueForConnection.toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `CharacteristicNotFound to gatt-disconnected (client)`() {
        val e = BlueyAndroidError.CharacteristicNotFound("abc").toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `DescriptorNotFound to gatt-disconnected (client)`() {
        val e = BlueyAndroidError.DescriptorNotFound("abc").toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `ConnectionTimeout to gatt-timeout (client)`() {
        val e = BlueyAndroidError.ConnectionTimeout.toClientFlutterError()
        assertEquals("gatt-timeout", e.code)
    }

    @Test
    fun `GattConnectionCreationFailed to bluey-unknown (client)`() {
        val e = BlueyAndroidError.GattConnectionCreationFailed.toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `SetNotificationFailed to gatt-status-failed 0x01 (client)`() {
        val e = BlueyAndroidError.SetNotificationFailed("abc").toClientFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x01, e.details)
    }

    @Test
    fun `BluetoothAdapterUnavailable to bluey-unknown (client)`() {
        val e = BlueyAndroidError.BluetoothAdapterUnavailable.toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `PermissionDenied to bluey-permission-denied with details permission (client)`() {
        val e = BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT").toClientFlutterError()
        assertEquals("bluey-permission-denied", e.code)
        assertEquals("BLUETOOTH_CONNECT", e.details)
    }

    @Test
    fun `NotInitialized to bluey-unknown (client)`() {
        val e = BlueyAndroidError.NotInitialized("scanner").toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    // --- Server-side mappings ---

    @Test
    fun `CharacteristicNotFound to gatt-status-failed 0x0A (server)`() {
        val e = BlueyAndroidError.CharacteristicNotFound("abc").toServerFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0A, e.details)
    }

    @Test
    fun `CentralNotFound to gatt-status-failed 0x0A (server)`() {
        val e = BlueyAndroidError.CentralNotFound("central-1").toServerFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0A, e.details)
    }

    @Test
    fun `NoPendingRequest to gatt-status-failed 0x0A (server)`() {
        val e = BlueyAndroidError.NoPendingRequest(42L).toServerFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0A, e.details)
    }

    @Test
    fun `FailedToOpenGattServer to bluey-unknown (server)`() {
        val e = BlueyAndroidError.FailedToOpenGattServer.toServerFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `FailedToAddService to bluey-unknown (server)`() {
        val e = BlueyAndroidError.FailedToAddService("abc").toServerFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `PermissionDenied to bluey-permission-denied (server)`() {
        val e = BlueyAndroidError.PermissionDenied("BLUETOOTH_ADVERTISE").toServerFlutterError()
        assertEquals("bluey-permission-denied", e.code)
        assertEquals("BLUETOOTH_ADVERTISE", e.details)
    }

    // --- Regression guard for context-sensitive mapping ---

    @Test
    fun `CharacteristicNotFound server-side does NOT map to gatt-disconnected`() {
        val e = BlueyAndroidError.CharacteristicNotFound("abc").toServerFlutterError()
        assertNotEquals(
            "Server-side notFound must not look like a disconnect",
            "gatt-disconnected",
            e.code
        )
    }

    // --- Catch-all for random Throwables ---

    @Test
    fun `random RuntimeException to bluey-unknown with class name (client)`() {
        val e = RuntimeException("kaboom").toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `random RuntimeException to bluey-unknown with class name (server)`() {
        val e = RuntimeException("kaboom").toServerFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `null-message Throwable falls back to class name (client)`() {
        val thrown: Throwable = object : RuntimeException() {}
        val e = thrown.toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
        assertEquals(thrown.javaClass.simpleName, e.message)
    }

    // --- Already-translated FlutterError pass-through (regression guard) ---
    // The inner layers (GattOpQueue, ConnectionManager.statusFailedError)
    // emit their own FlutterError with gatt-* codes. The BlueyPlugin wrapper's
    // recoverCatching on async callbacks will call toXFlutterError on those
    // errors; the pass-through prevents the outer wrap from overwriting
    // the wire code to bluey-unknown.

    @Test
    fun `pre-existing FlutterError passes through unchanged (client)`() {
        val inner = FlutterError("gatt-timeout", "write timed out", null)
        val e = inner.toClientFlutterError()
        assertEquals("gatt-timeout", e.code)
        assertEquals("write timed out", e.message)
    }

    @Test
    fun `pre-existing FlutterError with details passes through unchanged (client)`() {
        val inner = FlutterError("gatt-status-failed", "write failed", 0x0D)
        val e = inner.toClientFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0D, e.details)
    }

    @Test
    fun `pre-existing FlutterError passes through unchanged (server)`() {
        val inner = FlutterError("gatt-disconnected", "link lost", null)
        val e = inner.toServerFlutterError()
        assertEquals("gatt-disconnected", e.code)
        assertEquals("link lost", e.message)
    }
}
