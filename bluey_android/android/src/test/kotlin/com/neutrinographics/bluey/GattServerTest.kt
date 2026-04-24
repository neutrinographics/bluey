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

    @Test
    fun `onCharacteristicReadRequest does not call sendResponse`() {
        // Open the server.
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

        every { mockFlutterApi.onReadRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicReadRequest(
            mockDevice,
            42, // requestId
            0,  // offset
            mockCharacteristic
        )

        // Flutter is notified.
        verify { mockFlutterApi.onReadRequest(any(), any()) }

        // BUT: sendResponse is NOT called from the binder thread.
        verify(exactly = 0) {
            mockBluetoothGattServer.sendResponse(any(), any(), any(), any(), any())
        }
    }

    @Test
    fun `respondToReadRequest with known id calls sendResponse with Dart-supplied value and status`() {
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

        every { mockFlutterApi.onReadRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        // Stash a pending read.
        capturedCallback!!.onCharacteristicReadRequest(mockDevice, 42, 3, mockCharacteristic)

        // Dart responds.
        val value = byteArrayOf(0x01, 0x02, 0x03)
        var resultSeen: Result<Unit>? = null
        gattServer.respondToReadRequest(42L, GattStatusDto.SUCCESS, value) {
            resultSeen = it
        }

        // sendResponse called with the stashed device + offset, Dart-supplied status + value.
        verify(exactly = 1) {
            mockBluetoothGattServer.sendResponse(
                mockDevice,
                42,
                android.bluetooth.BluetoothGatt.GATT_SUCCESS,
                3,
                value
            )
        }
        assertTrue("respond callback should succeed", resultSeen?.isSuccess == true)
    }

    @Test
    fun `respondToReadRequest with unknown id fails with NoPendingRequest`() {
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        var resultSeen: Result<Unit>? = null
        gattServer.respondToReadRequest(999L, GattStatusDto.SUCCESS, byteArrayOf()) {
            resultSeen = it
        }

        assertTrue("result should be failure", resultSeen?.isFailure == true)
        val exc = resultSeen?.exceptionOrNull()
        assertTrue(
            "expected NoPendingRequest, got $exc",
            exc is BlueyAndroidError.NoPendingRequest
        )
        assertEquals(999L, (exc as BlueyAndroidError.NoPendingRequest).id)

        verify(exactly = 0) {
            mockBluetoothGattServer.sendResponse(any(), any(), any(), any(), any())
        }
    }

    @Test
    fun `respondToReadRequest with null value sends empty ByteArray`() {
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
        every { mockFlutterApi.onReadRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicReadRequest(mockDevice, 10, 0, mockCharacteristic)

        gattServer.respondToReadRequest(10L, GattStatusDto.SUCCESS, null) {}

        // sendResponse must receive an empty ByteArray, not null.
        val valueSlot = slot<ByteArray>()
        verify {
            mockBluetoothGattServer.sendResponse(
                mockDevice,
                10,
                android.bluetooth.BluetoothGatt.GATT_SUCCESS,
                0,
                capture(valueSlot)
            )
        }
        assertEquals(0, valueSlot.captured.size)
    }

    @Test
    fun `respondToReadRequest maps each GattStatusDto to the correct BluetoothGatt constant`() {
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
        every { mockFlutterApi.onReadRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        val cases = listOf(
            GattStatusDto.SUCCESS to android.bluetooth.BluetoothGatt.GATT_SUCCESS,
            GattStatusDto.READ_NOT_PERMITTED to android.bluetooth.BluetoothGatt.GATT_READ_NOT_PERMITTED,
            GattStatusDto.WRITE_NOT_PERMITTED to android.bluetooth.BluetoothGatt.GATT_WRITE_NOT_PERMITTED,
            GattStatusDto.INVALID_OFFSET to android.bluetooth.BluetoothGatt.GATT_INVALID_OFFSET,
            GattStatusDto.INVALID_ATTRIBUTE_LENGTH to android.bluetooth.BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH,
            GattStatusDto.INSUFFICIENT_AUTHENTICATION to android.bluetooth.BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION,
            GattStatusDto.INSUFFICIENT_ENCRYPTION to android.bluetooth.BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION,
            GattStatusDto.REQUEST_NOT_SUPPORTED to android.bluetooth.BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
        )

        for ((idx, case) in cases.withIndex()) {
            val (dto, expected) = case
            val reqId = (100 + idx)
            capturedCallback!!.onCharacteristicReadRequest(mockDevice, reqId, 0, mockCharacteristic)
            gattServer.respondToReadRequest(reqId.toLong(), dto, byteArrayOf()) {}

            verify {
                mockBluetoothGattServer.sendResponse(
                    mockDevice,
                    reqId,
                    expected,
                    0,
                    any()
                )
            }
        }
    }

    @Test
    fun `onCharacteristicWriteRequest (responseNeeded, not prepared) stashes and does not call sendResponse`() {
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
        every { mockFlutterApi.onWriteRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicWriteRequest(
            mockDevice,
            55,    // requestId
            mockCharacteristic,
            false, // preparedWrite
            true,  // responseNeeded
            0,     // offset
            byteArrayOf(0x0A)
        )

        verify { mockFlutterApi.onWriteRequest(any(), any()) }

        // No binder-thread sendResponse.
        verify(exactly = 0) {
            mockBluetoothGattServer.sendResponse(any(), any(), any(), any(), any())
        }
    }

    @Test
    fun `respondToWriteRequest with known id calls sendResponse with null payload`() {
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
        every { mockFlutterApi.onWriteRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicWriteRequest(
            mockDevice, 77, mockCharacteristic, false, true, 5, byteArrayOf(0xFF.toByte())
        )

        var resultSeen: Result<Unit>? = null
        gattServer.respondToWriteRequest(77L, GattStatusDto.SUCCESS) {
            resultSeen = it
        }

        // sendResponse called with stashed device + requestId + offset, Dart's status, and null value.
        verify(exactly = 1) {
            mockBluetoothGattServer.sendResponse(
                mockDevice,
                77,
                android.bluetooth.BluetoothGatt.GATT_SUCCESS,
                5,
                null
            )
        }
        assertTrue("respond callback should succeed", resultSeen?.isSuccess == true)
    }

    @Test
    fun `respondToWriteRequest with unknown id fails with NoPendingRequest`() {
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        var resultSeen: Result<Unit>? = null
        gattServer.respondToWriteRequest(888L, GattStatusDto.SUCCESS) {
            resultSeen = it
        }

        val exc = resultSeen?.exceptionOrNull()
        assertTrue(
            "expected NoPendingRequest, got $exc",
            exc is BlueyAndroidError.NoPendingRequest
        )
        assertEquals(888L, (exc as BlueyAndroidError.NoPendingRequest).id)

        verify(exactly = 0) {
            mockBluetoothGattServer.sendResponse(any(), any(), any(), any(), any())
        }
    }

    @Test
    fun `onCharacteristicWriteRequest with responseNeeded=false does not stash and does not call sendResponse`() {
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
        every { mockFlutterApi.onWriteRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicWriteRequest(
            mockDevice, 30, mockCharacteristic,
            false, // preparedWrite
            false, // responseNeeded
            0,
            byteArrayOf(0x42)
        )

        // Flutter is still notified — the write is visible to Dart.
        verify { mockFlutterApi.onWriteRequest(any(), any()) }

        // No sendResponse from binder thread.
        verify(exactly = 0) {
            mockBluetoothGattServer.sendResponse(any(), any(), any(), any(), any())
        }

        // The id must NOT be in the registry — respondToWrite would fail.
        var resultSeen: Result<Unit>? = null
        gattServer.respondToWriteRequest(30L, GattStatusDto.SUCCESS) { resultSeen = it }
        assertTrue(resultSeen?.isFailure == true)
        assertTrue(resultSeen?.exceptionOrNull() is BlueyAndroidError.NoPendingRequest)
    }

    @Test
    fun `onCharacteristicWriteRequest with preparedWrite=true preserves auto-respond echo`() {
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
        every { mockFlutterApi.onWriteRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        val value = byteArrayOf(0xAA.toByte(), 0xBB.toByte())
        capturedCallback!!.onCharacteristicWriteRequest(
            mockDevice, 40, mockCharacteristic,
            true,  // preparedWrite
            true,  // responseNeeded
            7,
            value
        )

        // Existing auto-respond behavior preserved for prepared writes (I050 owns this path).
        verify(exactly = 1) {
            mockBluetoothGattServer.sendResponse(
                mockDevice,
                40,
                android.bluetooth.BluetoothGatt.GATT_SUCCESS,
                7,
                value
            )
        }

        // The id must NOT be in the registry — prepared writes bypass the Dart-mediated path.
        var resultSeen: Result<Unit>? = null
        gattServer.respondToWriteRequest(40L, GattStatusDto.SUCCESS) { resultSeen = it }
        assertTrue(resultSeen?.exceptionOrNull() is BlueyAndroidError.NoPendingRequest)
    }

    @Test
    fun `onConnectionStateChange(DISCONNECTED) drains pending requests for that central only`() {
        val service = LocalServiceDto(
            uuid = "12345678-1234-1234-1234-123456789abc",
            isPrimary = true,
            characteristics = emptyList(),
            includedServices = emptyList()
        )
        gattServer.addService(service) {}

        val deviceA = mockk<BluetoothDevice>(relaxed = true)
        every { deviceA.address } returns "AA:AA:AA:AA:AA:AA"
        val deviceB = mockk<BluetoothDevice>(relaxed = true)
        every { deviceB.address } returns "BB:BB:BB:BB:BB:BB"

        val mockCharacteristic = mockk<android.bluetooth.BluetoothGattCharacteristic>(relaxed = true)
        every { mockCharacteristic.uuid } returns java.util.UUID.fromString("abcd1234-1234-1234-1234-123456789abc")
        every { mockFlutterApi.onReadRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }
        every { mockFlutterApi.onWriteRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }
        every { mockFlutterApi.onCentralConnected(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }
        every { mockFlutterApi.onCentralDisconnected(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        // Connect both centrals and stash one read + one write for each.
        capturedCallback!!.onConnectionStateChange(deviceA, 0, BluetoothProfile.STATE_CONNECTED)
        capturedCallback!!.onConnectionStateChange(deviceB, 0, BluetoothProfile.STATE_CONNECTED)
        capturedCallback!!.onCharacteristicReadRequest(deviceA, 1, 0, mockCharacteristic)
        capturedCallback!!.onCharacteristicWriteRequest(deviceA, 2, mockCharacteristic, false, true, 0, byteArrayOf(0x01))
        capturedCallback!!.onCharacteristicReadRequest(deviceB, 3, 0, mockCharacteristic)
        capturedCallback!!.onCharacteristicWriteRequest(deviceB, 4, mockCharacteristic, false, true, 0, byteArrayOf(0x02))

        // Disconnect only A.
        capturedCallback!!.onConnectionStateChange(deviceA, 0, BluetoothProfile.STATE_DISCONNECTED)

        // A's pending entries are drained — respond fails.
        var aReadResult: Result<Unit>? = null
        gattServer.respondToReadRequest(1L, GattStatusDto.SUCCESS, byteArrayOf()) { aReadResult = it }
        assertTrue(aReadResult?.exceptionOrNull() is BlueyAndroidError.NoPendingRequest)

        var aWriteResult: Result<Unit>? = null
        gattServer.respondToWriteRequest(2L, GattStatusDto.SUCCESS) { aWriteResult = it }
        assertTrue(aWriteResult?.exceptionOrNull() is BlueyAndroidError.NoPendingRequest)

        // B's pending entries survive — respond succeeds.
        var bReadResult: Result<Unit>? = null
        gattServer.respondToReadRequest(3L, GattStatusDto.SUCCESS, byteArrayOf()) { bReadResult = it }
        assertTrue("B's read should succeed", bReadResult?.isSuccess == true)

        var bWriteResult: Result<Unit>? = null
        gattServer.respondToWriteRequest(4L, GattStatusDto.SUCCESS) { bWriteResult = it }
        assertTrue("B's write should succeed", bWriteResult?.isSuccess == true)
    }
}
