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
 * Lifecycle and threading tests for ConnectionManager:
 *
 *   * I062 — `onConnectionStateChange` mutates state only inside
 *     `handler.post { ... }` (binder-thread → main-thread marshaling).
 *   * I098 item 5 — concurrent `connect(deviceId)` is rejected.
 *   * I060 — `disconnect()` awaits STATE_DISCONNECTED with a 5 s
 *     fallback that force-closes the gatt and synthesizes a
 *     `gatt-disconnected` failure.
 *   * I061 — `cleanup()` drains queues and fails pending connect
 *     callbacks (and succeeds pending disconnect callbacks) before
 *     clearing maps, so awaiting Futures don't hang past activity
 *     destroy / engine detach.
 *
 * Tests are added across multiple commits per the I098 design spec
 * (`docs/superpowers/specs/2026-04-27-android-connection-manager-rewrite-design.md`).
 */
class ConnectionManagerLifecycleTest {

    private lateinit var mockContext: Context
    private lateinit var mockAdapter: BluetoothAdapter
    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var mockGatt: BluetoothGatt
    private lateinit var mockDevice: BluetoothDevice
    private lateinit var connectionManager: ConnectionManager
    private var capturedGattCallback: BluetoothGattCallback? = null

    private val deviceAddress = "AA:BB:CC:DD:EE:01"
    private val testCharUuid = JavaUUID.fromString("12345678-1234-1234-1234-123456789abd")
    private val testServiceUuid = JavaUUID.fromString("12345678-1234-1234-1234-123456789abc")

    /**
     * Captured `(runnable, delayMs)` pairs from every `Handler.postDelayed`
     * call across the test. Tests that exercise scheduled timeouts (the
     * disconnect fallback in I060, the connect timeout) drive the
     * captured runnable manually to simulate the timer firing.
     */
    private val capturedPostDelayed = mutableListOf<Pair<Runnable, Long>>()

    /** Runnables passed to `Handler.removeCallbacks` (used for cancellation assertions). */
    private val removedCallbacks = mutableListOf<Runnable>()

    @Before
    fun setUp() {
        // Pin SDK_INT to TIRAMISU so production code takes the modern gatt API
        // branch (3-arg writeCharacteristic / 2-arg writeDescriptor) that the
        // mocks are wired to match.
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

        // Default: handler.post runs the runnable immediately. Tests that
        // need to assert "X happens INSIDE the post" can re-stub post to
        // capture instead of running, then drain manually.
        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run()
            true
        }
        // postDelayed: capture the runnable so tests can fire it manually
        // to simulate a timer expiring.
        every { anyConstructed<Handler>().postDelayed(any(), any()) } answers {
            capturedPostDelayed.add(firstArg<Runnable>() to secondArg<Long>())
            true
        }
        every { anyConstructed<Handler>().removeCallbacks(any()) } answers {
            removedCallbacks.add(firstArg<Runnable>())
        }

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

    /**
     * Drives a successful connect to [deviceAddress]: registers the GATT
     * callback, then synthesizes STATE_CONNECTED so the queue is created
     * and the connection is recorded. Returns the synchronously-fired
     * connect callback's result (must be success).
     */
    private fun establishConnection() {
        var connectResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            connectResult = result
        }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
        assertTrue("setUp connect failed", connectResult!!.isSuccess)
    }

    /**
     * Switches `handler.post` to deferred mode: every subsequent post
     * captures the runnable into [deferredPosts] without executing it.
     * Tests can drain manually to inspect "before vs after post" state.
     */
    private fun deferHandlerPosts(deferredPosts: MutableList<Runnable>) {
        every { anyConstructed<Handler>().post(any()) } answers {
            deferredPosts.add(firstArg<Runnable>())
            true
        }
    }

    /**
     * Creates a mock characteristic and wires it into mockGatt.services so
     * ConnectionManager.findCharacteristic (which iterates service.characteristics)
     * can locate it. Used by tests that probe the connections/queues maps
     * by attempting a public GATT op.
     */
    private fun mockCharacteristic(
        charUuid: JavaUUID = testCharUuid,
    ): BluetoothGattCharacteristic {
        val char = mockk<BluetoothGattCharacteristic>(relaxed = true)
        every { char.uuid } returns charUuid
        val service = mockk<BluetoothGattService>(relaxed = true)
        every { service.uuid } returns testServiceUuid
        every { service.getCharacteristic(charUuid) } returns char
        every { service.characteristics } returns listOf(char)
        every { mockGatt.services } returns listOf(service)
        return char
    }

    // ============================================================
    // I062 — onConnectionStateChange threading
    // ============================================================

    @Test
    fun `I062 STATE_DISCONNECTED defers gatt close into handler post`() {
        establishConnection()

        val deferredPosts = mutableListOf<Runnable>()
        deferHandlerPosts(deferredPosts)

        // Fire STATE_DISCONNECTED on the (mocked) binder thread.
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        // gatt.close() must NOT have been invoked yet — it must run inside
        // the deferred main-thread post per the I062 threading invariant.
        verify(exactly = 0) { mockGatt.close() }

        // Drain the deferred posts.
        assertTrue(
            "STATE_DISCONNECTED must post at least one runnable",
            deferredPosts.isNotEmpty(),
        )
        deferredPosts.toList().forEach { it.run() }

        verify(exactly = 1) { mockGatt.close() }
    }

    @Test
    fun `I062 STATE_DISCONNECTED defers connections map mutation into handler post`() {
        establishConnection()
        mockCharacteristic()
        every { mockGatt.writeCharacteristic(
            any<BluetoothGattCharacteristic>(), any(), any(),
        ) } returns BluetoothGatt.GATT_SUCCESS

        val deferredPosts = mutableListOf<Runnable>()
        deferHandlerPosts(deferredPosts)

        // Fire binder-thread STATE_DISCONNECTED.
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        // Probe: a write call AFTER the binder STATE_DISCONNECTED but BEFORE
        // we drain the deferred posts. Under the I062 fix the connections
        // map mutation is deferred along with everything else, so the write
        // is enqueued (no synchronous callback yet — drain runs inside the
        // post and only then fails the queued write with gatt-disconnected).
        // Pre-fix, connections.remove() runs on the binder thread, so the
        // probe fails synchronously with DeviceNotConnected.
        var probeResult: Result<Unit>? = null
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true,
        ) { probeResult = it }

        assertNull(
            "writeCharacteristic between binder STATE_DISCONNECTED and post " +
            "drain must not see DeviceNotConnected — connections + queues map " +
            "mutations are deferred per I062",
            probeResult,
        )

        // Drain deferred posts → unified body runs, queue drains, probe fails.
        deferredPosts.toList().forEach { it.run() }

        assertNotNull(probeResult)
        assertTrue(probeResult!!.isFailure)
    }

    // ============================================================
    // I098 item 5 — concurrent connect mutex
    // ============================================================

    @Test
    fun `I098 connect succeeds normally on first call`() {
        var connectResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            connectResult = result
        }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
        assertNotNull(connectResult)
        assertTrue(connectResult!!.isSuccess)
        assertEquals(deviceAddress, connectResult!!.getOrNull())
    }

    @Test
    fun `I098 second connect to same deviceId while first in-flight returns ConnectInProgress`() {
        // First connect — do NOT fire STATE_CONNECTED, so the connect
        // remains in flight (registered in pendingConnections).
        var firstResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            firstResult = result
        }

        // Second connect to the same address.
        var secondResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            secondResult = result
        }

        // The second call must fire its callback synchronously with a
        // typed BlueyAndroidError.ConnectInProgress(deviceAddress) failure.
        assertNotNull(
            "second connect must invoke its callback synchronously when one " +
            "is already in flight (I098 item 5)",
            secondResult,
        )
        assertTrue(secondResult!!.isFailure)
        val error = secondResult!!.exceptionOrNull()
        assertTrue(
            "expected BlueyAndroidError.ConnectInProgress, got ${error?.javaClass?.simpleName}: $error",
            error is BlueyAndroidError.ConnectInProgress,
        )
        assertEquals(deviceAddress, (error as BlueyAndroidError.ConnectInProgress).deviceId)

        // The first connect's callback must NOT have been disturbed.
        assertNull("first connect callback must not yet have fired", firstResult)

        // Only one BluetoothDevice.connectGatt call must have been issued.
        verify(exactly = 1) {
            mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>(), any())
        }
    }

    @Test
    fun `I098 second connect after first established returns idempotent success`() {
        // First connect, then complete it.
        var firstResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            firstResult = result
        }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
        assertTrue(firstResult!!.isSuccess)

        // Second connect to the same address — already connected, no
        // in-flight connect. Idempotent success: callback fires
        // synchronously, no second connectGatt issued.
        var secondResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            secondResult = result
        }

        assertNotNull(secondResult)
        assertTrue(secondResult!!.isSuccess)
        assertEquals(deviceAddress, secondResult!!.getOrNull())

        // Still only one connectGatt — the established connection is reused.
        verify(exactly = 1) {
            mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>(), any())
        }
    }

    // ============================================================
    // I060 — disconnect lifecycle (await STATE_DISCONNECTED + 5s fallback)
    // ============================================================

    private val disconnectFallbackMs = 5_000L

    @Test
    fun `I060 disconnect does not invoke callback synchronously`() {
        establishConnection()

        var disconnectResult: Result<Unit>? = null
        connectionManager.disconnect(deviceAddress) { result ->
            disconnectResult = result
        }

        assertNull(
            "disconnect callback must NOT fire until STATE_DISCONNECTED arrives (I060)",
            disconnectResult,
        )

        // Fire STATE_DISCONNECTED.
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        assertNotNull(disconnectResult)
        assertTrue(
            "disconnect must succeed when STATE_DISCONNECTED arrives within window",
            disconnectResult!!.isSuccess,
        )
    }

    @Test
    fun `I060 disconnect with no connection invokes callback synchronously with success`() {
        // No establishConnection() — there is no entry in connections.
        var disconnectResult: Result<Unit>? = null
        connectionManager.disconnect(deviceAddress) { result ->
            disconnectResult = result
        }

        assertNotNull(
            "disconnect with no entry must complete synchronously with success (idempotent)",
            disconnectResult,
        )
        assertTrue(disconnectResult!!.isSuccess)
        // No gatt.disconnect() should have been issued.
        verify(exactly = 0) { mockGatt.disconnect() }
    }

    @Test
    fun `I060 disconnect fallback fires gatt-disconnected after 5s if STATE_DISCONNECTED never arrives`() {
        establishConnection()
        // Clear postDelayed history from setUp (e.g. connect timeouts) so
        // we can find the disconnect fallback unambiguously.
        capturedPostDelayed.clear()

        var disconnectResult: Result<Unit>? = null
        connectionManager.disconnect(deviceAddress) { result ->
            disconnectResult = result
        }

        // The 5 s fallback must have been scheduled.
        val fallback = capturedPostDelayed.firstOrNull { it.second == disconnectFallbackMs }
        assertNotNull(
            "disconnect must schedule a 5000ms fallback runnable (I060)",
            fallback,
        )

        assertNull(
            "callback must not fire before fallback runs or STATE_DISCONNECTED arrives",
            disconnectResult,
        )

        // Simulate timer expiry — STATE_DISCONNECTED never arrives.
        fallback!!.first.run()

        assertNotNull(disconnectResult)
        assertTrue(disconnectResult!!.isFailure)
        val err = disconnectResult!!.exceptionOrNull()
        assertTrue(
            "fallback must surface gatt-disconnected, got ${err?.javaClass?.simpleName}: $err",
            err is FlutterError && err.code == "gatt-disconnected",
        )

        // Force-close was called on the gatt.
        verify(atLeast = 1) { mockGatt.close() }
    }

    @Test
    fun `I060 late STATE_DISCONNECTED after fallback is a no-op`() {
        establishConnection()
        capturedPostDelayed.clear()

        var disconnectResult: Result<Unit>? = null
        var callbackInvocations = 0
        connectionManager.disconnect(deviceAddress) { result ->
            disconnectResult = result
            callbackInvocations++
        }

        val fallback = capturedPostDelayed.firstOrNull { it.second == disconnectFallbackMs }
        assertNotNull(fallback)

        // Fallback fires first.
        fallback!!.first.run()
        assertEquals(1, callbackInvocations)

        // STATE_DISCONNECTED arrives late.
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        assertEquals(
            "callback must fire exactly once even when STATE_DISCONNECTED arrives after fallback",
            1, callbackInvocations,
        )
    }

    @Test
    fun `I060 STATE_DISCONNECTED cancels the disconnect fallback timer`() {
        establishConnection()
        capturedPostDelayed.clear()
        removedCallbacks.clear()

        connectionManager.disconnect(deviceAddress) { /* ignored */ }

        val fallback = capturedPostDelayed.firstOrNull { it.second == disconnectFallbackMs }
        assertNotNull(fallback)

        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )

        assertTrue(
            "STATE_DISCONNECTED must cancel the disconnect fallback runnable via removeCallbacks (I060)",
            removedCallbacks.any { it === fallback!!.first },
        )
    }

    @Test
    fun `I098 connect to a different deviceId while first in-flight succeeds independently`() {
        val secondAddress = "AA:BB:CC:DD:EE:02"
        val secondMockDevice = mockk<BluetoothDevice>(relaxed = true)
        val secondMockGatt = mockk<BluetoothGatt>(relaxed = true)
        var secondCapturedCallback: BluetoothGattCallback? = null

        every { secondMockDevice.address } returns secondAddress
        every { mockAdapter.getRemoteDevice(secondAddress) } returns secondMockDevice
        every {
            secondMockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>(), any())
        } answers {
            secondCapturedCallback = thirdArg()
            secondMockGatt
        }

        // First connect to deviceAddress — leave in flight.
        var firstResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            firstResult = result
        }

        // Connect to a different address — must NOT be blocked by the
        // first connect's mutex (mutex is per-deviceId).
        var secondResult: Result<String>? = null
        connectionManager.connect(secondAddress, ConnectConfigDto()) { result ->
            secondResult = result
        }
        assertNull(
            "second connect to a different address must NOT fail synchronously",
            secondResult,
        )

        secondCapturedCallback!!.onConnectionStateChange(
            secondMockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )

        assertNotNull(secondResult)
        assertTrue(secondResult!!.isSuccess)
        assertNull("first connect callback must remain in flight", firstResult)
    }

    // ============================================================
    // I061 — cleanup() drains + fails-or-succeeds pending callbacks
    // ============================================================

    @Test
    fun `I061 cleanup fails pending connect callbacks with a typed error`() {
        // Start a connect; do NOT fire STATE_CONNECTED.
        var connectResult: Result<String>? = null
        connectionManager.connect(deviceAddress, ConnectConfigDto()) { result ->
            connectResult = result
        }

        connectionManager.cleanup()

        assertNotNull(
            "cleanup must fire pending connect callbacks (I061)",
            connectResult,
        )
        assertTrue(connectResult!!.isFailure)
        // The exact error type is internal-spec; we only require it to be
        // a non-null failure that callers can observe.
        assertNotNull(connectResult!!.exceptionOrNull())
    }

    @Test
    fun `I061 cleanup completes pending disconnect callbacks with success`() {
        establishConnection()

        // Start a disconnect; do NOT fire STATE_DISCONNECTED.
        var disconnectResult: Result<Unit>? = null
        connectionManager.disconnect(deviceAddress) { result ->
            disconnectResult = result
        }
        assertNull("disconnect callback must NOT have fired pre-cleanup", disconnectResult)

        connectionManager.cleanup()

        assertNotNull(
            "cleanup must fire pending disconnect callbacks (I061)",
            disconnectResult,
        )
        assertTrue(
            "pending disconnect must complete with success on cleanup — the user " +
            "asked for the link to come down, cleanup made that happen (spec Decision 2)",
            disconnectResult!!.isSuccess,
        )
    }

    @Test
    fun `I061 cleanup drains in-flight queue ops with gatt-disconnected`() {
        establishConnection()
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(
            any<BluetoothGattCharacteristic>(), any(), any(),
        ) } returns BluetoothGatt.GATT_SUCCESS

        var writeResult: Result<Unit>? = null
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true,
        ) { writeResult = it }

        // Write is in flight (no callback yet — onCharacteristicWrite hasn't fired).
        assertNull(writeResult)

        connectionManager.cleanup()

        assertNotNull(
            "in-flight queue op callback must fire on cleanup (I061)",
            writeResult,
        )
        assertTrue(writeResult!!.isFailure)
        val err = writeResult!!.exceptionOrNull()
        assertTrue(
            "expected FlutterError(gatt-disconnected, ...), got ${err?.javaClass?.simpleName}: $err",
            err is FlutterError && err.code == "gatt-disconnected",
        )
    }

    @Test
    fun `I061 cleanup cancels pending connection and disconnect timeout runnables`() {
        // Establish a connection and start a disconnect to populate
        // pendingDisconnectTimeouts. The connect-timeout map only holds
        // entries when ConnectConfigDto carries a timeoutMs; use one.
        var connectResult: Result<String>? = null
        connectionManager.connect(
            deviceAddress, ConnectConfigDto(timeoutMs = 30_000L),
        ) { connectResult = it }
        capturedGattCallback!!.onConnectionStateChange(
            mockGatt, BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_CONNECTED,
        )
        assertTrue(connectResult!!.isSuccess)

        connectionManager.disconnect(deviceAddress) { /* ignored */ }
        val fallback = capturedPostDelayed.firstOrNull { it.second == disconnectFallbackMs }
        assertNotNull(
            "disconnect must have scheduled a 5s fallback for this test to be meaningful",
            fallback,
        )

        removedCallbacks.clear()
        connectionManager.cleanup()

        assertTrue(
            "cleanup must cancel the disconnect fallback runnable via removeCallbacks (I061)",
            removedCallbacks.any { it === fallback!!.first },
        )
    }
}
