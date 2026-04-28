package com.neutrinographics.bluey

import android.Manifest
import android.bluetooth.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.mockk.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import java.util.UUID as JavaUUID

/**
 * Integration tests for ConnectionManager routing GATT ops through
 * GattOpQueue. Verifies:
 *   - Ops are serialized at the BluetoothGatt layer (no concurrent gatt.X())
 *   - BluetoothGattCallback events are marshaled to main thread via handler.post
 *   - Drain on disconnect fires pending callbacks with gatt-disconnected
 *   - setNotification routes the CCCD write through the queue
 *   - Incoming notifications bypass the queue entirely
 */
class ConnectionManagerQueueTest {

    private lateinit var mockContext: Context
    private lateinit var mockAdapter: BluetoothAdapter
    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var mockGatt: BluetoothGatt
    private lateinit var mockDevice: BluetoothDevice
    private lateinit var connectionManager: ConnectionManager
    private var capturedGattCallback: BluetoothGattCallback? = null

    private val testCharUuid = JavaUUID.fromString("12345678-1234-1234-1234-123456789abd")
    private val testServiceUuid = JavaUUID.fromString("12345678-1234-1234-1234-123456789abc")
    private val cccdUuid = JavaUUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private val deviceAddress = "AA:BB:CC:DD:EE:01"

    @Before
    fun setUp() {
        // Pin SDK_INT to TIRAMISU so production code takes the modern gatt API
        // branch (3-arg writeCharacteristic / 2-arg writeDescriptor) that the
        // mocks are wired to match.  Under unit-test JVM the field defaults to 0
        // which would cause the deprecated 1-arg overload to be invoked instead,
        // making every mock stub miss and every write fail synchronously.
        setSdkVersion(Build.VERSION_CODES.TIRAMISU)

        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.v(any(), any()) } returns 0

        // With SDK_INT == TIRAMISU the BLUETOOTH_CONNECT permission check fires.
        // Grant permission so ConnectionManager.connect proceeds past the guard.
        mockkStatic(ContextCompat::class)
        every {
            ContextCompat.checkSelfPermission(any(), Manifest.permission.BLUETOOTH_CONNECT)
        } returns PackageManager.PERMISSION_GRANTED

        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns mockk(relaxed = true)

        // Execute handler.post immediately; leave postDelayed as a no-op that returns true
        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run()
            true
        }
        every { anyConstructed<Handler>().postDelayed(any(), any()) } returns true
        every { anyConstructed<Handler>().removeCallbacks(any()) } just Runs

        mockContext = mockk(relaxed = true)
        mockAdapter = mockk(relaxed = true)
        mockFlutterApi = mockk(relaxed = true)
        mockGatt = mockk(relaxed = true)
        mockDevice = mockk(relaxed = true)

        every { mockDevice.address } returns deviceAddress
        every { mockAdapter.getRemoteDevice(deviceAddress) } returns mockDevice
        // SDK_INT is now TIRAMISU, so the 4-arg connectGatt form (API 23+) fires.
        every { mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>(), any()) } answers {
            capturedGattCallback = thirdArg()
            mockGatt
        }
        every { mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>()) } answers {
            capturedGattCallback = thirdArg()
            mockGatt
        }

        connectionManager = ConnectionManager(mockContext, mockAdapter, mockFlutterApi)

        // Simulate a completed connection so internal `connections[deviceId]` + queues[deviceId]
        // are populated. The ConnectionManager.connect API returns a connection ID;
        // simulate STATE_CONNECTED by firing the captured gatt callback.
        var connectResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            connectResult = result
        }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
        assertNotNull("connect callback should have fired after STATE_CONNECTED", connectResult)
        assertTrue("connect should succeed in setUp", connectResult!!.isSuccess)
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
        // Restore SDK_INT so other test classes are not affected
        setSdkVersion(0)
    }

    /**
     * Uses sun.misc.Unsafe to overwrite the final Build.VERSION.SDK_INT field.
     * This matches the approach used in BlueyPluginTest and avoids requiring
     * mockk-agent / byte-buddy for final-field mocking.
     */
    private fun setSdkVersion(version: Int) {
        val sdkIntField = Build.VERSION::class.java.getDeclaredField("SDK_INT")
        val unsafeClass = Class.forName("sun.misc.Unsafe")
        val theUnsafe = unsafeClass.getDeclaredField("theUnsafe")
        theUnsafe.isAccessible = true
        val unsafe = theUnsafe.get(null)
        val staticFieldBase = unsafeClass.getMethod("staticFieldBase", java.lang.reflect.Field::class.java)
        val staticFieldOffset = unsafeClass.getMethod("staticFieldOffset", java.lang.reflect.Field::class.java)
        val putInt = unsafeClass.getMethod(
            "putInt", Any::class.java, Long::class.javaPrimitiveType, Int::class.javaPrimitiveType,
        )
        putInt.invoke(
            unsafe,
            staticFieldBase.invoke(unsafe, sdkIntField),
            staticFieldOffset.invoke(unsafe, sdkIntField) as Long,
            version,
        )
    }

    /**
     * Creates a mock characteristic and wires it into mockGatt.services so
     * ConnectionManager.findCharacteristic (which iterates service.characteristics)
     * can locate it.
     */
    private fun mockCharacteristic(
        charUuid: JavaUUID = testCharUuid,
    ): BluetoothGattCharacteristic {
        val char = mockk<BluetoothGattCharacteristic>(relaxed = true)
        every { char.uuid } returns charUuid
        val service = mockk<BluetoothGattService>(relaxed = true)
        every { service.uuid } returns testServiceUuid
        every { service.getCharacteristic(charUuid) } returns char
        // findCharacteristic iterates service.characteristics, not getCharacteristic
        every { service.characteristics } returns listOf(char)
        every { mockGatt.services } returns listOf(service)
        return char
    }

    @Test
    fun `two writes back-to-back execute in submission order`() {
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(
            any<BluetoothGattCharacteristic>(), any(), any(),
        ) } returns BluetoothGatt.GATT_SUCCESS

        val results = mutableListOf<String>()

        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true, null,
        ) { results.add("first=$it") }

        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x02), true, null,
        ) { results.add("second=$it") }

        // Only the first write should have reached the OS yet
        verify(exactly = 1) {
            mockGatt.writeCharacteristic(char, byteArrayOf(0x01), any())
        }
        verify(exactly = 0) {
            mockGatt.writeCharacteristic(char, byteArrayOf(0x02), any())
        }

        // Fire onCharacteristicWrite for the first op
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)

        // Now the second write is in flight
        verify(exactly = 1) {
            mockGatt.writeCharacteristic(char, byteArrayOf(0x02), any())
        }

        // Complete second
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)
        assertEquals(2, results.size)
    }

    @Test
    fun `onConnectionStateChange DISCONNECTED drains pending with gatt-disconnected`() {
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(
            any<BluetoothGattCharacteristic>(), any(), any(),
        ) } returns BluetoothGatt.GATT_SUCCESS

        val results = mutableListOf<Result<Unit>>()
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true, null,
        ) { results.add(it) }
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x02), true, null,
        ) { results.add(it) }

        // Both ops must still be in flight (neither synchronously completed nor failed)
        // before the disconnect fires.  If this asserts 0, drain is what populates results,
        // not a sync failure path.
        assertEquals(
            "Writes must still be in flight before disconnect",
            0, results.size,
        )

        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        assertEquals(2, results.size)
        for (r in results) {
            assertTrue(r.isFailure)
            val err = r.exceptionOrNull() as FlutterError
            assertEquals("gatt-disconnected", err.code)
        }
    }

    @Test
    fun `setNotification routes CCCD write through queue`() {
        val char = mockCharacteristic()
        val cccd = mockk<BluetoothGattDescriptor>(relaxed = true)
        every { cccd.uuid } returns cccdUuid
        every { char.getDescriptor(cccdUuid) } returns cccd
        every { char.properties } returns BluetoothGattCharacteristic.PROPERTY_NOTIFY
        every { mockGatt.setCharacteristicNotification(char, true) } returns true
        every { mockGatt.writeDescriptor(any<BluetoothGattDescriptor>(), any()) } returns BluetoothGatt.GATT_SUCCESS

        var captured: Result<Unit>? = null
        connectionManager.setNotification(
            deviceAddress, testCharUuid.toString(), true, null,
        ) { captured = it }

        verify { mockGatt.setCharacteristicNotification(char, true) }
        verify(exactly = 1) { mockGatt.writeDescriptor(cccd, any()) }

        // Fire onDescriptorWrite to complete the CCCD write
        capturedGattCallback!!.onDescriptorWrite(mockGatt, cccd, BluetoothGatt.GATT_SUCCESS)

        assertNotNull(captured)
        assertTrue(captured!!.isSuccess)
    }

    @Test
    fun `onCharacteristicWrite with non-success status emits gatt-status-failed FlutterError`() {
        // Regression guard for the iOS-server-force-kill scenario: when the
        // peer removes its GATT service (via Service Changed + app exit),
        // subsequent writes return a non-success status (typically 0x01,
        // GATT_INVALID_HANDLE). That must reach callers as a typed protocol
        // error — not as a bare IllegalStateException that Pigeon marshals
        // with an unhelpful "IllegalStateException" error code.
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(
            any<BluetoothGattCharacteristic>(), any(), any(),
        ) } returns BluetoothGatt.GATT_SUCCESS

        var captured: Result<Unit>? = null
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true, null,
        ) { captured = it }

        // Fire the OS callback with GATT_INVALID_HANDLE (status 0x01)
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, 0x01)

        assertNotNull(captured)
        assertTrue(captured!!.isFailure)
        val err = captured!!.exceptionOrNull()
        assertTrue(
            "expected FlutterError with code gatt-status-failed, got ${err?.javaClass?.simpleName}: $err",
            err is FlutterError && err.code == "gatt-status-failed",
        )
        val flutterError = err as FlutterError
        assertEquals(
            "FlutterError.details must carry the native status for Dart-side matching",
            0x01, flutterError.details,
        )
        assertTrue(
            "message should mention 'status' for log readability",
            flutterError.message?.contains("status") == true,
        )
    }

    @Test
    fun `setNotification propagates SecurityException from inline sync enable`() {
        val char = mockCharacteristic()
        val denied = SecurityException("BLUETOOTH_CONNECT revoked")
        every { mockGatt.setCharacteristicNotification(char, true) } throws denied

        var captured: Result<Unit>? = null
        connectionManager.setNotification(
            deviceAddress, testCharUuid.toString(), true, null,
        ) { captured = it }

        assertNotNull("callback must fire even when sync enable throws", captured)
        assertTrue(captured!!.isFailure)
        val error = captured!!.exceptionOrNull()
        assertTrue(
            "SecurityException must surface as BlueyAndroidError.PermissionDenied",
            error is BlueyAndroidError.PermissionDenied,
        )
        assertEquals(
            "BLUETOOTH_CONNECT",
            (error as BlueyAndroidError.PermissionDenied).permission,
        )
    }

    @Test
    fun `onCharacteristicChanged bypasses queue and forwards notification`() {
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(
            any<BluetoothGattCharacteristic>(), any(), any(),
        ) } returns BluetoothGatt.GATT_SUCCESS

        // Put an op in flight to prove the notification doesn't disturb it
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true, null,
        ) { /* ignored */ }
        verify(exactly = 1) {
            mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any())
        }

        val notifValue = byteArrayOf(0x42, 0x43)
        capturedGattCallback!!.onCharacteristicChanged(mockGatt, char, notifValue)

        // The notification must be forwarded to the Flutter API without being
        // routed through the queue. The actual signature from Messages.g.kt is:
        //   fun onNotification(eventArg: NotificationEventDto, callback: (Result<Unit>) -> Unit)
        // We verify that onNotification was called with an event containing the
        // right deviceId, characteristicUuid, and value.
        verify {
            mockFlutterApi.onNotification(
                match { event ->
                    event.deviceId == deviceAddress &&
                        event.characteristicUuid.equals(testCharUuid.toString(), ignoreCase = true) &&
                        event.value.contentEquals(notifValue)
                },
                any(),
            )
        }

        // If the notification had been routed through the queue it would have
        // "completed" the current op, allowing a subsequent enqueue to execute.
        // Verify that is NOT what happened: submit a second write and confirm it
        // has NOT reached the OS yet — the queue is still busy with the first write.
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x99.toByte()), true, null,
        ) { /* ignored */ }
        verify(exactly = 1) {
            mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any())
        }
        // (Total OS writes still 1 — the second submission is queued, not executed.)

        // Now complete the first write normally; the second write should fire.
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)
        verify(exactly = 2) {
            mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any())
        }
    }
}
