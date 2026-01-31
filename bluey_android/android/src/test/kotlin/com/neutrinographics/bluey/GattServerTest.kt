package com.neutrinographics.bluey

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.mockk.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*

/**
 * Unit tests for GattServer.
 *
 * These tests verify that the GattServer correctly handles Bluetooth callbacks
 * and forwards them to the Flutter API.
 */
class GattServerTest {

    private lateinit var mockContext: Context
    private lateinit var mockBluetoothManager: BluetoothManager
    private lateinit var mockBluetoothGattServer: BluetoothGattServer
    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var gattServer: GattServer

    // Capture the callback passed to openGattServer
    private var capturedCallback: BluetoothGattServerCallback? = null

    @Before
    fun setUp() {
        // Mock Android Log class
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.v(any(), any()) } returns 0

        // Mock the Looper and Handler
        mockkStatic(Looper::class)
        val mockLooper = mockk<Looper>(relaxed = true)
        every { Looper.getMainLooper() } returns mockLooper

        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            // Execute the runnable immediately for testing
            firstArg<Runnable>().run()
            true
        }

        mockContext = mockk(relaxed = true)
        mockBluetoothManager = mockk(relaxed = true)
        mockBluetoothGattServer = mockk(relaxed = true)
        mockFlutterApi = mockk(relaxed = true)

        // Capture the callback when openGattServer is called
        every {
            mockBluetoothManager.openGattServer(any(), any())
        } answers {
            capturedCallback = secondArg()
            mockBluetoothGattServer
        }

        // Mock addService to return true
        every { mockBluetoothGattServer.addService(any()) } returns true

        gattServer = GattServer(mockContext, mockBluetoothManager, mockFlutterApi)
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
    }

    @Test
    fun `addService opens GATT server and adds service`() {
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )

        gattServer.addService(service) {}

        // Verify openGattServer was called
        verify { mockBluetoothManager.openGattServer(mockContext, any()) }

        // Verify addService was called on the BluetoothGattServer
        verify { mockBluetoothGattServer.addService(any()) }
    }

    @Test
    fun `onConnectionStateChange notifies Flutter when central connects`() {
        // First, open the server by adding a service
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        // Start advertising (required for connections to be reported to Flutter)
        gattServer.onAdvertisingStarted()

        // Ensure callback was captured
        assertNotNull("Callback should be captured", capturedCallback)

        // Create a mock BluetoothDevice
        val mockDevice = mockk<BluetoothDevice>(relaxed = true)
        every { mockDevice.address } returns "AA:BB:CC:DD:EE:FF"

        // Capture the CentralDto passed to onCentralConnected
        val centralSlot = slot<CentralDto>()
        every { mockFlutterApi.onCentralConnected(capture(centralSlot), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        // Simulate a connection state change
        capturedCallback!!.onConnectionStateChange(
            mockDevice,
            0, // status = GATT_SUCCESS
            BluetoothProfile.STATE_CONNECTED
        )

        // Verify onCentralConnected was called with correct data
        verify { mockFlutterApi.onCentralConnected(any(), any()) }
        assertEquals("AA:BB:CC:DD:EE:FF", centralSlot.captured.id)
        assertEquals(23L, centralSlot.captured.mtu) // DEFAULT_MTU
    }

    @Test
    fun `onConnectionStateChange notifies Flutter when central disconnects`() {
        // First, open the server
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        // Start advertising (required for connections to be reported to Flutter)
        gattServer.onAdvertisingStarted()

        val mockDevice = mockk<BluetoothDevice>(relaxed = true)
        every { mockDevice.address } returns "AA:BB:CC:DD:EE:FF"

        // First connect
        capturedCallback!!.onConnectionStateChange(
            mockDevice,
            0,
            BluetoothProfile.STATE_CONNECTED
        )

        // Then disconnect
        capturedCallback!!.onConnectionStateChange(
            mockDevice,
            0,
            BluetoothProfile.STATE_DISCONNECTED
        )

        // Verify onCentralDisconnected was called
        verify { mockFlutterApi.onCentralDisconnected("AA:BB:CC:DD:EE:FF", any()) }
    }

    @Test
    fun `callback is captured when GATT server opens`() {
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        // The captured callback should not be null
        assertNotNull(capturedCallback)
    }

    @Test
    fun `multiple addService calls reuse same GATT server`() {
        val service1 = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        val service2 = LocalServiceDto(
            uuid = "87654321-4321-4321-4321-cba987654321",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )

        gattServer.addService(service1) {}
        gattServer.addService(service2) {}

        // openGattServer should only be called once
        verify(exactly = 1) { mockBluetoothManager.openGattServer(any(), any()) }

        // addService should be called twice
        verify(exactly = 2) { mockBluetoothGattServer.addService(any()) }
    }

    @Test
    fun `onCharacteristicReadRequest notifies Flutter`() {
        // Use a service without characteristics to avoid BluetoothGattService.addCharacteristic
        // being called (which isn't mocked). The callback itself doesn't depend on service setup.
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        val mockDevice = mockk<BluetoothDevice>(relaxed = true)
        every { mockDevice.address } returns "AA:BB:CC:DD:EE:FF"

        val mockCharacteristic = mockk<android.bluetooth.BluetoothGattCharacteristic>(relaxed = true)
        every { mockCharacteristic.uuid } returns java.util.UUID.fromString("abcd1234-1234-1234-1234-123456789abc")

        // Capture the read request
        val requestSlot = slot<ReadRequestDto>()
        every { mockFlutterApi.onReadRequest(capture(requestSlot), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicReadRequest(
            mockDevice,
            1, // requestId
            0, // offset
            mockCharacteristic
        )

        verify { mockFlutterApi.onReadRequest(any(), any()) }
        assertEquals("AA:BB:CC:DD:EE:FF", requestSlot.captured.centralId)
        assertEquals(1L, requestSlot.captured.requestId)
    }

    @Test
    fun `connected central is tracked in internal map`() {
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        val mockDevice = mockk<BluetoothDevice>(relaxed = true)
        every { mockDevice.address } returns "AA:BB:CC:DD:EE:FF"

        // Connect
        capturedCallback!!.onConnectionStateChange(
            mockDevice,
            0,
            BluetoothProfile.STATE_CONNECTED
        )

        // Try to disconnect the central - this should work if it's tracked
        gattServer.disconnectCentral("AA:BB:CC:DD:EE:FF") {}

        // Verify cancelConnection was called on the correct device
        verify { mockBluetoothGattServer.cancelConnection(mockDevice) }
    }
}
