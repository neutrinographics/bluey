package com.neutrinographics.bluey

import android.bluetooth.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
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
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.v(any(), any()) } returns 0

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
        // Mock both the 4-arg form (API 23+) and the 3-arg form (below API 23).
        // Unit tests run with Build.VERSION.SDK_INT == 0, so the else-branch fires.
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
        val connectConfig = ConnectConfigDto()
        connectionManager.connect(deviceAddress, connectConfig) { /* ignored */ }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
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
            byteArrayOf(0x01), true,
        ) { results.add("first=$it") }

        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x02), true,
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
            byteArrayOf(0x01), true,
        ) { results.add(it) }
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x02), true,
        ) { results.add(it) }

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
            deviceAddress, testCharUuid.toString(), true,
        ) { captured = it }

        verify { mockGatt.setCharacteristicNotification(char, true) }
        verify(exactly = 1) { mockGatt.writeDescriptor(cccd, any()) }

        // Fire onDescriptorWrite to complete the CCCD write
        capturedGattCallback!!.onDescriptorWrite(mockGatt, cccd, BluetoothGatt.GATT_SUCCESS)

        assertNotNull(captured)
        assertTrue(captured!!.isSuccess)
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
            byteArrayOf(0x01), true,
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

        // Op in flight unaffected — complete it normally
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)
    }
}
