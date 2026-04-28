package com.neutrinographics.bluey

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
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
 * Concurrency-hardening tests for `GattServer.notifyCharacteristic`:
 *
 *   * I082 — `notifyCharacteristic` iterates `subscriptions[uuid]`
 *     without synchronization. A central disconnecting on the binder
 *     thread (which mutates the same set via STATE_DISCONNECTED) or
 *     unsubscribing via CCCD mid-iteration can throw
 *     `ConcurrentModificationException` or silently skip centrals.
 *   * I086 — `removeService` runs concurrently with notify fanout. The
 *     I082 fix's defensive snapshot covers this incidentally because
 *     a removed service's centrals fall out of the snapshot if removal
 *     completed before fanout started, and the existing
 *     `findCharacteristic` null check already guards the
 *     characteristic-was-removed path.
 */
class GattServerNotifyConcurrencyTest {

    private lateinit var mockContext: Context
    private lateinit var mockBluetoothManager: BluetoothManager
    private lateinit var mockBluetoothGattServer: BluetoothGattServer
    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var gattServer: GattServer
    private var capturedCallback: BluetoothGattServerCallback? = null

    private val testCharUuid = "00002a37-0000-1000-8000-00805f9b34fb"
    private val testServiceUuid = "0000180d-0000-1000-8000-00805f9b34fb"
    private val central1 = "AA:BB:CC:DD:EE:01"
    private val central2 = "AA:BB:CC:DD:EE:02"

    @Before
    fun setUp() {
        // Pin SDK_INT to TIRAMISU so production code takes the 4-arg
        // `notifyCharacteristicChanged` branch that the mocks are wired
        // to match.
        setSdkVersion(Build.VERSION_CODES.TIRAMISU)

        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.v(any(), any()) } returns 0

        // SDK_INT == TIRAMISU triggers the BLUETOOTH_CONNECT permission
        // check in hasRequiredPermissions(). Grant it. Match any args to
        // avoid String-constant nullability surprises in the stubbed
        // Android JAR (Manifest.permission.* may be null at JVM runtime).
        mockkStatic(ContextCompat::class)
        every {
            ContextCompat.checkSelfPermission(any<Context>(), any<String>())
        } returns PackageManager.PERMISSION_GRANTED

        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns mockk(relaxed = true)

        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run()
            true
        }
        // I012 added per-send timeouts via postDelayed; capture them so
        // tests that exercise notifyCharacteristic don't crash on the
        // unmocked method, and the GattServer's queue stays consistent.
        every { anyConstructed<Handler>().postDelayed(any(), any()) } returns true
        every { anyConstructed<Handler>().removeCallbacks(any()) } just Runs

        mockContext = mockk(relaxed = true)
        mockBluetoothManager = mockk(relaxed = true)
        mockBluetoothGattServer = mockk(relaxed = true)
        mockFlutterApi = mockk(relaxed = true)

        every { mockBluetoothManager.openGattServer(any(), any()) } answers {
            capturedCallback = secondArg()
            mockBluetoothGattServer
        }
        every { mockBluetoothGattServer.addService(any()) } returns true

        gattServer = GattServer(mockContext, mockBluetoothManager, mockFlutterApi)

        // Open the server by adding a service.
        gattServer.addService(
            LocalServiceDto(
                uuid = testServiceUuid,
                isPrimary = true,
                characteristics = emptyList(),
                includedServices = emptyList(),
            ),
        ) { _ -> }
        assertNotNull("setUp must capture the BluetoothGattServerCallback", capturedCallback)
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
        val staticFieldBase = unsafeClass.getMethod(
            "staticFieldBase", java.lang.reflect.Field::class.java,
        )
        val staticFieldOffset = unsafeClass.getMethod(
            "staticFieldOffset", java.lang.reflect.Field::class.java,
        )
        val putInt = unsafeClass.getMethod(
            "putInt",
            Any::class.java,
            Long::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
        )
        putInt.invoke(
            unsafe,
            staticFieldBase.invoke(unsafe, sdkIntField),
            staticFieldOffset.invoke(unsafe, sdkIntField) as Long,
            version,
        )
    }

    /**
     * Reflectively appends [centralId] to `GattServer.subscriptions[charUuid]`.
     * Lets the test set up subscriptions without going through the CCCD
     * binder callback (which is blocked in the JVM stub environment by
     * `BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE` being null —
     * see I085).
     */
    private fun addSubscriptionDirect(charUuid: String, centralId: String) {
        val field = GattServer::class.java.getDeclaredField("subscriptions")
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val subs = field.get(gattServer) as MutableMap<String, MutableSet<String>>
        subs.getOrPut(charUuid) { mutableSetOf() }.add(centralId)
    }

    /**
     * Wires `mockBluetoothGattServer.services` so it surfaces a single
     * characteristic, and reflectively registers that char in the
     * GattServer's `characteristicByHandle` table under [testCharHandle]
     * so [GattServer.notifyCharacteristic]'s handle lookup succeeds.
     */
    private fun mockCharacteristicOnServer(): BluetoothGattCharacteristic {
        val char = mockk<BluetoothGattCharacteristic>(relaxed = true)
        every { char.uuid } returns JavaUUID.fromString(testCharUuid)
        val service = mockk<BluetoothGattService>(relaxed = true)
        every { service.uuid } returns JavaUUID.fromString(testServiceUuid)
        every { service.characteristics } returns listOf(char)
        every { mockBluetoothGattServer.services } returns listOf(service)
        // I088 D.13 — inject into the local handle table so notify can
        // resolve testCharHandle -> char without a full addService roundtrip.
        val field = GattServer::class.java.getDeclaredField("characteristicByHandle")
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val table = field.get(gattServer) as MutableMap<Long, BluetoothGattCharacteristic>
        table[testCharHandle] = char
        return char
    }

    private val testCharHandle: Long = 1L

    private fun connectCentral(deviceId: String): BluetoothDevice {
        val device = mockk<BluetoothDevice>(relaxed = true)
        every { device.address } returns deviceId
        capturedCallback!!.onConnectionStateChange(
            device, 0, BluetoothProfile.STATE_CONNECTED,
        )
        return device
    }

    @Test
    fun `I082 notifyCharacteristic survives concurrent central disconnect mid-fanout`() {
        // Two centrals subscribed to the same characteristic.
        val device1 = connectCentral(central1)
        val device2 = connectCentral(central2)
        addSubscriptionDirect(testCharUuid, central1)
        addSubscriptionDirect(testCharUuid, central2)

        val char = mockCharacteristicOnServer()

        // notifyCharacteristicChanged for device1 fires the binder-thread
        // STATE_DISCONNECTED for device2, which mutates `subscriptions` —
        // the same set the outer iteration is walking. With the I082 fix
        // (defensive snapshot at iteration entry), this is harmless. Pre-fix
        // it throws ConcurrentModificationException.
        val notifiedDevices = mutableListOf<String>()
        every {
            mockBluetoothGattServer.notifyCharacteristicChanged(
                any<BluetoothDevice>(), any<BluetoothGattCharacteristic>(),
                any<Boolean>(), any<ByteArray>(),
            )
        } answers {
            val target = firstArg<BluetoothDevice>()
            notifiedDevices.add(target.address)
            if (target.address == central1) {
                // Simulate concurrent binder-thread disconnect of central2.
                capturedCallback!!.onConnectionStateChange(
                    device2, 0, BluetoothProfile.STATE_DISCONNECTED,
                )
            }
            0 // BluetoothStatusCodes.SUCCESS — int
        }

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(
            testCharHandle,
            byteArrayOf(0x01),
        ) { notifyResult = it }

        // Under I012, notify waits for onNotificationSent per central.
        // central2's pending entry was drained with gatt-disconnected by
        // the disconnect handler; central1's still in flight.
        assertNull(
            "notify must still be waiting for central1's onNotificationSent",
            notifyResult,
        )

        // Fire central1's onNotificationSent → aggregate completes.
        capturedCallback!!.onNotificationSent(device1, 0)

        assertNotNull(notifyResult)
        // No ConcurrentModificationException was thrown — the iteration
        // walked the snapshot safely. The aggregate surfaces a failure
        // because central2 was disconnected mid-fanout (I012 semantics).
        assertTrue(
            "aggregate result reflects central2's disconnect failure",
            notifyResult!!.isFailure,
        )
        assertTrue(
            "central1 was notified before the disconnect of central2 fired",
            notifiedDevices.contains(central1),
        )
    }

    @Test
    fun `I086 removeService followed by notifyCharacteristic returns HandleInvalidated`() {
        // After removeService, the local handle table no longer
        // resolves the characteristic's handle (D.13). The public op
        // surfaces a typed HandleInvalidated rather than crashing.
        addSubscriptionDirect(testCharUuid, central1)
        connectCentral(central1)

        // No mock characteristic registered → handle table is empty.
        every { mockBluetoothGattServer.services } returns emptyList()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(
            testCharHandle,
            byteArrayOf(0x01),
        ) { notifyResult = it }

        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isFailure)
        val err = notifyResult!!.exceptionOrNull()
        assertTrue(
            "expected BlueyAndroidError.HandleInvalidated, got " +
            "${err?.javaClass?.simpleName}: $err",
            err is BlueyAndroidError.HandleInvalidated,
        )
    }

    @Test
    fun `I082 notifyCharacteristic with no subscribers is a success no-op`() {
        // Regression guard: notifyCharacteristic with an empty subscriber
        // set must complete with success synchronously and never call the
        // server's notifyCharacteristicChanged.
        mockCharacteristicOnServer()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(
            testCharHandle,
            byteArrayOf(0x01),
        ) { notifyResult = it }

        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isSuccess)
        verify(exactly = 0) {
            mockBluetoothGattServer.notifyCharacteristicChanged(
                any<BluetoothDevice>(), any<BluetoothGattCharacteristic>(),
                any<Boolean>(), any<ByteArray>(),
            )
        }
    }
}
