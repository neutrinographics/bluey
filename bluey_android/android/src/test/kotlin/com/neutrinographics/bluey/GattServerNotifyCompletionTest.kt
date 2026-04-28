package com.neutrinographics.bluey

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
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
 * Completion-tracking tests for `GattServer.notifyCharacteristic` and
 * `notifyCharacteristicTo` (I012):
 *
 * The Dart-side `Future<void>` returned by `notify(...)` should NOT
 * resolve until the underlying `onNotificationSent` callback has fired
 * for every subscribed central (or any of them times out / fails).
 * Pre-fix the callback fired synchronously after the iteration, which
 * made the Future a meaningless yield point.
 *
 * Aggregation: success when every central reports
 * `BluetoothGatt.GATT_SUCCESS`; failure on the first non-success
 * `onNotificationSent` status, on a per-send timeout, or on a
 * `STATE_DISCONNECTED` for any in-flight central. The Pigeon contract
 * stays `Future<void>` — per-central observability is not exposed at
 * this layer.
 */
class GattServerNotifyCompletionTest {

    private lateinit var mockContext: Context
    private lateinit var mockBluetoothManager: BluetoothManager
    private lateinit var mockBluetoothGattServer: BluetoothGattServer
    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var gattServer: GattServer
    private var capturedCallback: BluetoothGattServerCallback? = null

    /**
     * Captured (runnable, delayMs) pairs from every Handler.postDelayed
     * call. Tests fire the relevant runnable manually to simulate a
     * per-send timeout expiring.
     */
    private val capturedPostDelayed = mutableListOf<Pair<Runnable, Long>>()

    /** Runnables passed to Handler.removeCallbacks, for cancellation assertions. */
    private val removedCallbacks = mutableListOf<Runnable>()

    private val testCharUuid = "00002a37-0000-1000-8000-00805f9b34fb"
    private val testServiceUuid = "0000180d-0000-1000-8000-00805f9b34fb"
    private val central1 = "AA:BB:CC:DD:EE:01"
    private val central2 = "AA:BB:CC:DD:EE:02"

    /** Matches the spec's per-central send timeout. */
    private val notificationSendTimeoutMs = 5_000L

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
            ContextCompat.checkSelfPermission(any<Context>(), any<String>())
        } returns PackageManager.PERMISSION_GRANTED

        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns mockk(relaxed = true)

        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run()
            true
        }
        every { anyConstructed<Handler>().postDelayed(any(), any()) } answers {
            capturedPostDelayed.add(firstArg<Runnable>() to secondArg<Long>())
            true
        }
        every { anyConstructed<Handler>().removeCallbacks(any()) } answers {
            removedCallbacks.add(firstArg<Runnable>())
        }

        mockContext = mockk(relaxed = true)
        mockBluetoothManager = mockk(relaxed = true)
        mockBluetoothGattServer = mockk(relaxed = true)
        mockFlutterApi = mockk(relaxed = true)

        every { mockBluetoothManager.openGattServer(any(), any()) } answers {
            capturedCallback = secondArg()
            mockBluetoothGattServer
        }
        every { mockBluetoothGattServer.addService(any()) } returns true
        // 4-arg notifyCharacteristicChanged returns int (BluetoothStatusCodes.SUCCESS = 0).
        every {
            mockBluetoothGattServer.notifyCharacteristicChanged(
                any<BluetoothDevice>(), any<BluetoothGattCharacteristic>(),
                any<Boolean>(), any<ByteArray>(),
            )
        } returns 0

        gattServer = GattServer(mockContext, mockBluetoothManager, mockFlutterApi)
        gattServer.addService(
            LocalServiceDto(
                uuid = testServiceUuid,
                isPrimary = true,
                characteristics = emptyList(),
                includedServices = emptyList(),
            ),
        ) {}
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

    private fun addSubscriptionDirect(charUuid: String, centralId: String) {
        val field = GattServer::class.java.getDeclaredField("subscriptions")
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val subs = field.get(gattServer) as MutableMap<String, MutableSet<String>>
        subs.getOrPut(charUuid) { mutableSetOf() }.add(centralId)
    }

    private fun mockCharacteristicOnServer(): BluetoothGattCharacteristic {
        val char = mockk<BluetoothGattCharacteristic>(relaxed = true)
        every { char.uuid } returns JavaUUID.fromString(testCharUuid)
        val service = mockk<BluetoothGattService>(relaxed = true)
        every { service.uuid } returns JavaUUID.fromString(testServiceUuid)
        every { service.characteristics } returns listOf(char)
        every { mockBluetoothGattServer.services } returns listOf(service)
        // I088 D.13 — register the char under handle 1 so
        // GattServer.notifyCharacteristic can resolve it without going
        // through addService.
        val field = GattServer::class.java.getDeclaredField("characteristicByHandle")
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val table = field.get(gattServer) as MutableMap<Long, BluetoothGattCharacteristic>
        table[1L] = char
        return char
    }

    private fun connectCentral(deviceId: String): BluetoothDevice {
        val device = mockk<BluetoothDevice>(relaxed = true)
        every { device.address } returns deviceId
        capturedCallback!!.onConnectionStateChange(
            device, 0, BluetoothProfile.STATE_CONNECTED,
        )
        return device
    }

    @Test
    fun `I012 notifyCharacteristic completes only after onNotificationSent for all subscribers`() {
        val device1 = connectCentral(central1)
        val device2 = connectCentral(central2)
        addSubscriptionDirect(testCharUuid, central1)
        addSubscriptionDirect(testCharUuid, central2)
        mockCharacteristicOnServer()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { notifyResult = it }

        // notifyCharacteristicChanged was invoked for both centrals;
        // but onNotificationSent has not yet fired. The Dart-facing
        // callback must wait.
        verify(exactly = 2) {
            mockBluetoothGattServer.notifyCharacteristicChanged(
                any<BluetoothDevice>(), any<BluetoothGattCharacteristic>(),
                any<Boolean>(), any<ByteArray>(),
            )
        }
        assertNull(
            "notify callback must NOT fire until onNotificationSent has " +
            "been received for every subscribed central (I012)",
            notifyResult,
        )

        // Fire onNotificationSent for the first central. Still pending the second.
        capturedCallback!!.onNotificationSent(device1, BluetoothGatt.GATT_SUCCESS)
        assertNull(
            "callback must wait until ALL subscribers have acked",
            notifyResult,
        )

        // Fire onNotificationSent for the second central. Aggregate complete.
        capturedCallback!!.onNotificationSent(device2, BluetoothGatt.GATT_SUCCESS)
        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isSuccess)
    }

    @Test
    fun `I012 notifyCharacteristic surfaces gatt-status-failed when any central reports non-success`() {
        val device1 = connectCentral(central1)
        val device2 = connectCentral(central2)
        addSubscriptionDirect(testCharUuid, central1)
        addSubscriptionDirect(testCharUuid, central2)
        mockCharacteristicOnServer()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { notifyResult = it }

        capturedCallback!!.onNotificationSent(device1, BluetoothGatt.GATT_SUCCESS)
        capturedCallback!!.onNotificationSent(device2, 0x85) // GATT_ERROR

        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isFailure)
        val err = notifyResult!!.exceptionOrNull()
        assertTrue(
            "expected FlutterError(gatt-status-failed), got " +
            "${err?.javaClass?.simpleName}: $err",
            err is FlutterError && err.code == "gatt-status-failed",
        )
    }

    @Test
    fun `I012 notifyCharacteristic times out per central if onNotificationSent never fires`() {
        connectCentral(central1)
        addSubscriptionDirect(testCharUuid, central1)
        mockCharacteristicOnServer()

        capturedPostDelayed.clear()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { notifyResult = it }

        // A timeout runnable for the per-send window must have been scheduled.
        val timeout = capturedPostDelayed.firstOrNull {
            it.second == notificationSendTimeoutMs
        }
        assertNotNull(
            "notifyCharacteristic must schedule a per-send timeout (I012)",
            timeout,
        )

        assertNull(notifyResult)

        // Simulate the timer firing.
        timeout!!.first.run()

        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isFailure)
        val err = notifyResult!!.exceptionOrNull()
        assertTrue(
            "expected FlutterError(gatt-timeout), got " +
            "${err?.javaClass?.simpleName}: $err",
            err is FlutterError && err.code == "gatt-timeout",
        )
    }

    @Test
    fun `I012 onNotificationSent cancels its per-central timeout`() {
        val device = connectCentral(central1)
        addSubscriptionDirect(testCharUuid, central1)
        mockCharacteristicOnServer()
        capturedPostDelayed.clear()
        removedCallbacks.clear()

        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { /* ignored */ }

        val timeout = capturedPostDelayed.firstOrNull {
            it.second == notificationSendTimeoutMs
        }
        assertNotNull(timeout)

        capturedCallback!!.onNotificationSent(device, BluetoothGatt.GATT_SUCCESS)

        assertTrue(
            "onNotificationSent must cancel the per-send timeout via " +
            "removeCallbacks",
            removedCallbacks.any { it === timeout!!.first },
        )
    }

    @Test
    fun `I012 two notifyCharacteristic calls FIFO their per-central completions`() {
        // Same central, two notifies in flight. Android's onNotificationSent
        // doesn't carry the characteristic UUID, so per-central completions
        // are FIFO. The first onNotificationSent must complete the first
        // notify; the second onNotificationSent the second.
        val device = connectCentral(central1)
        addSubscriptionDirect(testCharUuid, central1)
        mockCharacteristicOnServer()

        var first: Result<Unit>? = null
        var second: Result<Unit>? = null
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { first = it }
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x02)) { second = it }

        // Neither has fired yet.
        assertNull(first)
        assertNull(second)

        // First onNotificationSent → completes the first notify only.
        capturedCallback!!.onNotificationSent(device, BluetoothGatt.GATT_SUCCESS)
        assertNotNull("first notify must complete on its own onNotificationSent", first)
        assertTrue(first!!.isSuccess)
        assertNull("second notify must wait for the next onNotificationSent", second)

        // Second onNotificationSent → completes the second notify.
        capturedCallback!!.onNotificationSent(device, BluetoothGatt.GATT_SUCCESS)
        assertNotNull(second)
        assertTrue(second!!.isSuccess)
    }

    @Test
    fun `I012 STATE_DISCONNECTED drains pending notifications for that central with gatt-disconnected`() {
        val device = connectCentral(central1)
        addSubscriptionDirect(testCharUuid, central1)
        mockCharacteristicOnServer()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { notifyResult = it }
        assertNull(notifyResult)

        // Central disconnects before onNotificationSent arrives.
        capturedCallback!!.onConnectionStateChange(
            device, 0, BluetoothProfile.STATE_DISCONNECTED,
        )

        assertNotNull(
            "in-flight notify callback must fire when its central " +
            "disconnects (I012)",
            notifyResult,
        )
        assertTrue(notifyResult!!.isFailure)
        val err = notifyResult!!.exceptionOrNull()
        assertTrue(
            "expected FlutterError(gatt-disconnected), got " +
            "${err?.javaClass?.simpleName}: $err",
            err is FlutterError && err.code == "gatt-disconnected",
        )
    }

    @Test
    fun `I012 notifyCharacteristicTo waits for onNotificationSent (single-central)`() {
        val device = connectCentral(central1)
        mockCharacteristicOnServer()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristicTo(central1, 1L, byteArrayOf(0x01)) { notifyResult = it }

        verify(exactly = 1) {
            mockBluetoothGattServer.notifyCharacteristicChanged(
                any<BluetoothDevice>(), any<BluetoothGattCharacteristic>(),
                any<Boolean>(), any<ByteArray>(),
            )
        }
        assertNull(
            "notifyCharacteristicTo callback must wait for onNotificationSent (I012)",
            notifyResult,
        )

        capturedCallback!!.onNotificationSent(device, BluetoothGatt.GATT_SUCCESS)
        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isSuccess)
    }

    @Test
    fun `I012 notifyCharacteristic with no subscribers fires success synchronously (regression)`() {
        // No subscribers configured. Callback fires success immediately;
        // no notifyCharacteristicChanged or postDelayed.
        mockCharacteristicOnServer()
        capturedPostDelayed.clear()

        var notifyResult: Result<Unit>? = null
        gattServer.notifyCharacteristic(1L, byteArrayOf(0x01)) { notifyResult = it }

        assertNotNull(notifyResult)
        assertTrue(notifyResult!!.isSuccess)
        verify(exactly = 0) {
            mockBluetoothGattServer.notifyCharacteristicChanged(
                any<BluetoothDevice>(), any<BluetoothGattCharacteristic>(),
                any<Boolean>(), any<ByteArray>(),
            )
        }
        assertTrue(
            "no per-send timeout should be scheduled when there are no subscribers",
            capturedPostDelayed.none { it.second == notificationSendTimeoutMs },
        )
    }
}
