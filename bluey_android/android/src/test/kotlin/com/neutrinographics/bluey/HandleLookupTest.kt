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
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.UUID as JavaUUID

/**
 * I088 Task D.3 — handle-table population/clearing in [ConnectionManager].
 *
 * Asserts that the per-device handle lookup tables
 * (`characteristicByHandle`, `descriptorByHandle`, `nextDescriptorHandle`)
 * are populated when `onServicesDiscovered` fires, cleared on
 * `STATE_DISCONNECTED`, and cleared on `onServiceChanged` (before
 * the platform schedules a re-discovery).
 *
 * Characteristic handles use the public
 * `BluetoothGattCharacteristic.getInstanceId()`. Descriptor handles
 * are minted client-side from a per-device monotonic counter starting
 * at 1, because `BluetoothGattDescriptor.getInstanceId()` is `@hide`
 * in AOSP.
 */
class HandleLookupTest {

    private lateinit var mockContext: Context
    private lateinit var mockAdapter: BluetoothAdapter
    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var mockGatt: BluetoothGatt
    private lateinit var mockDevice: BluetoothDevice
    private lateinit var connectionManager: ConnectionManager
    private var capturedGattCallback: BluetoothGattCallback? = null

    private val deviceAddress = "AA:BB:CC:DD:EE:01"

    private val serviceAUuid = JavaUUID.fromString("0000aaaa-0000-1000-8000-00805f9b34fb")
    private val serviceBUuid = JavaUUID.fromString("0000bbbb-0000-1000-8000-00805f9b34fb")
    private val charA1Uuid = JavaUUID.fromString("0000a001-0000-1000-8000-00805f9b34fb")
    private val charA2Uuid = JavaUUID.fromString("0000a002-0000-1000-8000-00805f9b34fb")
    private val charB1Uuid = JavaUUID.fromString("0000b001-0000-1000-8000-00805f9b34fb")
    private val charB2Uuid = JavaUUID.fromString("0000b002-0000-1000-8000-00805f9b34fb")
    private val descUuid = JavaUUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    @Before
    fun setUp() {
        setSdkVersion(Build.VERSION_CODES.TIRAMISU)

        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.v(any(), any()) } returns 0

        mockkStatic(ContextCompat::class)
        every {
            ContextCompat.checkSelfPermission(any(), Manifest.permission.BLUETOOTH_CONNECT)
        } returns PackageManager.PERMISSION_GRANTED

        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns mockk(relaxed = true)

        // handler.post: run synchronously so we can probe state immediately.
        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run()
            true
        }
        every { anyConstructed<Handler>().postDelayed(any(), any()) } returns true
        every { anyConstructed<Handler>().removeCallbacks(any()) } returns Unit

        mockContext = mockk(relaxed = true)
        mockAdapter = mockk(relaxed = true)
        mockFlutterApi = mockk(relaxed = true)
        mockGatt = mockk(relaxed = true)
        mockDevice = mockk(relaxed = true)

        every { mockDevice.address } returns deviceAddress
        every { mockAdapter.getRemoteDevice(deviceAddress) } returns mockDevice
        every { mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>(), any()) } answers {
            capturedGattCallback = thirdArg()
            mockGatt
        }
        every { mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>()) } answers {
            capturedGattCallback = thirdArg()
            mockGatt
        }

        connectionManager = ConnectionManager(mockContext, mockAdapter, mockFlutterApi)
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
        setSdkVersion(0)
    }

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

    private fun establishConnection() {
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { /* ignored */ }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
    }

    /**
     * Build a topology of two services, each with two characteristics, each with one
     * CCCD descriptor. Returns the four characteristic mocks (in iteration order:
     * A1, A2, B1, B2) so the test can assert handle → characteristic mapping.
     */
    private data class Topology(
        val a1: BluetoothGattCharacteristic,
        val a2: BluetoothGattCharacteristic,
        val b1: BluetoothGattCharacteristic,
        val b2: BluetoothGattCharacteristic,
        val descA1: BluetoothGattDescriptor,
        val descA2: BluetoothGattDescriptor,
        val descB1: BluetoothGattDescriptor,
        val descB2: BluetoothGattDescriptor,
    )

    private fun buildTopology(): Topology {
        fun mkChar(uuid: JavaUUID, instanceId: Int, desc: BluetoothGattDescriptor): BluetoothGattCharacteristic {
            val c = mockk<BluetoothGattCharacteristic>(relaxed = true)
            every { c.uuid } returns uuid
            every { c.instanceId } returns instanceId
            every { c.descriptors } returns listOf(desc)
            return c
        }
        fun mkDesc(): BluetoothGattDescriptor {
            val d = mockk<BluetoothGattDescriptor>(relaxed = true)
            every { d.uuid } returns descUuid
            return d
        }

        val descA1 = mkDesc()
        val descA2 = mkDesc()
        val descB1 = mkDesc()
        val descB2 = mkDesc()
        val a1 = mkChar(charA1Uuid, 100, descA1)
        val a2 = mkChar(charA2Uuid, 101, descA2)
        val b1 = mkChar(charB1Uuid, 200, descB1)
        val b2 = mkChar(charB2Uuid, 201, descB2)

        val serviceA = mockk<BluetoothGattService>(relaxed = true)
        every { serviceA.uuid } returns serviceAUuid
        every { serviceA.characteristics } returns listOf(a1, a2)

        val serviceB = mockk<BluetoothGattService>(relaxed = true)
        every { serviceB.uuid } returns serviceBUuid
        every { serviceB.characteristics } returns listOf(b1, b2)

        every { mockGatt.services } returns listOf(serviceA, serviceB)

        return Topology(a1, a2, b1, b2, descA1, descA2, descB1, descB2)
    }

    @Suppress("UNCHECKED_CAST")
    private fun characteristicByHandle(): Map<String, Map<Int, BluetoothGattCharacteristic>> {
        val f = ConnectionManager::class.java.getDeclaredField("characteristicByHandle")
        f.isAccessible = true
        return f.get(connectionManager) as Map<String, Map<Int, BluetoothGattCharacteristic>>
    }

    @Suppress("UNCHECKED_CAST")
    private fun descriptorByHandle(): Map<String, Map<Int, BluetoothGattDescriptor>> {
        val f = ConnectionManager::class.java.getDeclaredField("descriptorByHandle")
        f.isAccessible = true
        return f.get(connectionManager) as Map<String, Map<Int, BluetoothGattDescriptor>>
    }

    @Suppress("UNCHECKED_CAST")
    private fun nextDescriptorHandle(): Map<String, Int> {
        val f = ConnectionManager::class.java.getDeclaredField("nextDescriptorHandle")
        f.isAccessible = true
        return f.get(connectionManager) as Map<String, Int>
    }

    @Test
    fun `populates handle table at onServicesDiscovered`() {
        establishConnection()
        val topo = buildTopology()

        capturedGattCallback!!.onServicesDiscovered(mockGatt, BluetoothGatt.GATT_SUCCESS)

        val charMap = characteristicByHandle()[deviceAddress]
        assertNotNull("characteristicByHandle must have an entry for the device", charMap)
        assertEquals(4, charMap!!.size)
        assertEquals(topo.a1, charMap[100])
        assertEquals(topo.a2, charMap[101])
        assertEquals(topo.b1, charMap[200])
        assertEquals(topo.b2, charMap[201])

        val descMap = descriptorByHandle()[deviceAddress]
        assertNotNull("descriptorByHandle must have an entry for the device", descMap)
        assertEquals(4, descMap!!.size)
        // All four minted handles 1..4 must be present and map to distinct
        // descriptors (iteration order across mocked maps isn't a guarantee
        // we want to bake into the assertion).
        assertEquals(setOf(1, 2, 3, 4), descMap.keys)
        assertEquals(
            "each minted handle must map to a distinct descriptor",
            4, descMap.values.toSet().size,
        )
        val expectedDescriptors = setOf(topo.descA1, topo.descA2, topo.descB1, topo.descB2)
        assertEquals(expectedDescriptors, descMap.values.toSet())

        assertEquals(
            "next-handle counter must be the handle that would be minted next",
            5, nextDescriptorHandle()[deviceAddress],
        )
    }

    @Test
    fun `clears handle table on STATE_DISCONNECTED`() {
        establishConnection()
        buildTopology()
        capturedGattCallback!!.onServicesDiscovered(mockGatt, BluetoothGatt.GATT_SUCCESS)
        // Sanity: populated.
        assertNotNull(characteristicByHandle()[deviceAddress])

        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        assertFalse(
            "characteristicByHandle must drop the device on STATE_DISCONNECTED",
            characteristicByHandle().containsKey(deviceAddress),
        )
        assertFalse(
            "descriptorByHandle must drop the device on STATE_DISCONNECTED",
            descriptorByHandle().containsKey(deviceAddress),
        )
        assertFalse(
            "nextDescriptorHandle must drop the device on STATE_DISCONNECTED",
            nextDescriptorHandle().containsKey(deviceAddress),
        )
    }

    @Test
    fun `clears handle table on onServiceChanged before re-discovery`() {
        establishConnection()
        buildTopology()
        capturedGattCallback!!.onServicesDiscovered(mockGatt, BluetoothGatt.GATT_SUCCESS)
        assertNotNull(characteristicByHandle()[deviceAddress])

        capturedGattCallback!!.onServiceChanged(mockGatt)

        assertFalse(
            "characteristicByHandle must clear on onServiceChanged so stale handles can't leak past re-discovery",
            characteristicByHandle().containsKey(deviceAddress),
        )
        assertFalse(
            "descriptorByHandle must clear on onServiceChanged",
            descriptorByHandle().containsKey(deviceAddress),
        )
        assertFalse(
            "nextDescriptorHandle must clear on onServiceChanged",
            nextDescriptorHandle().containsKey(deviceAddress),
        )
    }
}
