package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.mockk.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*

/**
 * Unit tests for GattOpQueue — the per-connection serial operation queue
 * that serializes GATT ops against BluetoothGatt's single-op constraint.
 *
 * Handler.postDelayed is captured (not executed) so tests can fire the
 * timeout Runnable manually. Handler.post runs synchronously so callback
 * delivery is observable in the same test body.
 */
class GattOpQueueTest {

    private lateinit var mockGatt: BluetoothGatt
    private lateinit var mockHandler: Handler

    /** Captured timeout Runnables, keyed by invocation order. */
    private val capturedTimeouts = mutableListOf<Runnable>()

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

        mockGatt = mockk(relaxed = true)
        mockHandler = mockk(relaxed = true)
        capturedTimeouts.clear()

        // Capture timeout Runnables without executing them
        every { mockHandler.postDelayed(any(), any()) } answers {
            capturedTimeouts.add(firstArg<Runnable>())
            true
        }
        every { mockHandler.removeCallbacks(any()) } just Runs
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
    }

    /** A test-only op that records outcomes. */
    private class TestOp(
        override val description: String = "Test op",
        override val timeoutMs: Long = 1000,
        private val executeReturns: Boolean = true,
    ) : GattOp() {
        var executedCount = 0
        var result: Result<Any?>? = null

        // Derive from description for test convenience; avoids duplicating
        // message strings in every test fixture. Production ops override
        // this explicitly to preserve hand-written log strings.
        override val syncFailureMessage = "Failed to ${description.replaceFirstChar { it.lowercase() }}"

        override fun execute(gatt: BluetoothGatt): Boolean {
            executedCount++
            return executeReturns
        }

        override fun complete(result: Result<Any?>) {
            this.result = result
        }
    }

    @Test
    fun `enqueue when idle starts op immediately`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val op = TestOp()

        queue.enqueue(op)

        assertEquals(1, op.executedCount)
        assertEquals(1, capturedTimeouts.size)
        assertNull(op.result)
    }

    @Test
    fun `second enqueue while busy waits for current to complete`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val first = TestOp(description = "First")
        val second = TestOp(description = "Second")

        queue.enqueue(first)
        queue.enqueue(second)

        assertEquals(1, first.executedCount)
        assertEquals(0, second.executedCount)
    }

    @Test
    fun `onComplete fires current callback and starts next op`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val first = TestOp(description = "First")
        val second = TestOp(description = "Second")
        queue.enqueue(first)
        queue.enqueue(second)

        queue.onComplete(Result.success("ok"))

        assertEquals(Result.success("ok"), first.result)
        assertEquals(1, second.executedCount)
        assertNull(second.result)
    }

    @Test
    fun `timeout fires callback with gatt-timeout FlutterError and advances`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val first = TestOp(description = "Write characteristic")
        val second = TestOp(description = "Second")
        queue.enqueue(first)
        queue.enqueue(second)

        capturedTimeouts[0].run()

        assertTrue(first.result!!.isFailure)
        val error = first.result!!.exceptionOrNull() as FlutterError
        assertEquals("gatt-timeout", error.code)
        assertTrue(error.message!!.contains("Write characteristic"))
        assertEquals(1, second.executedCount)
    }

    @Test
    fun `sync rejection fires callback with IllegalStateException and advances`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val failing = TestOp(description = "Read characteristic", executeReturns = false)
        val next = TestOp(description = "Next")
        queue.enqueue(failing)
        queue.enqueue(next)

        val err = failing.result!!.exceptionOrNull()
        assertTrue(err is IllegalStateException)
        assertTrue(err!!.message!!.contains("read characteristic"))
        assertEquals(1, next.executedCount)
    }

    @Test
    fun `drainAll fires all callbacks with reason and empties queue`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val first = TestOp(description = "First")
        val second = TestOp(description = "Second")
        val third = TestOp(description = "Third")
        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(third)

        val reason = FlutterError("gatt-disconnected", "link lost", null)
        queue.drainAll(reason)

        assertEquals(reason, first.result!!.exceptionOrNull())
        assertEquals(reason, second.result!!.exceptionOrNull())
        assertEquals(reason, third.result!!.exceptionOrNull())

        // After drain, a new enqueue should start immediately
        val recovery = TestOp(description = "Recovery")
        queue.enqueue(recovery)
        assertEquals(1, recovery.executedCount)
    }

    @Test
    fun `reentrant enqueue inside user callback preserves FIFO order`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val executionLog = mutableListOf<String>()

        val thirdSpy = object : GattOp() {
            override val description = "Third"
            override val syncFailureMessage = "Failed to third"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionLog.add("execute:Third")
                return true
            }
            override fun complete(result: Result<Any?>) {
                executionLog.add("complete:Third")
            }
        }
        val secondSpy = object : GattOp() {
            override val description = "Second"
            override val syncFailureMessage = "Failed to second"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionLog.add("execute:Second")
                return true
            }
            override fun complete(result: Result<Any?>) {
                executionLog.add("complete:Second")
            }
        }
        val first = object : GattOp() {
            override val description = "First"
            override val syncFailureMessage = "Failed to first"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionLog.add("execute:First")
                return true
            }
            override fun complete(result: Result<Any?>) {
                executionLog.add("complete:First")
                // Reentrant enqueue — should run AFTER secondSpy completes
                queue.enqueue(thirdSpy)
            }
        }

        queue.enqueue(first)
        queue.enqueue(secondSpy)

        // Complete first → its callback reentrantly enqueues thirdSpy.
        // After this, secondSpy is now current; thirdSpy is queued behind it.
        queue.onComplete(Result.success(Unit))

        assertEquals(
            listOf("execute:First", "complete:First", "execute:Second"),
            executionLog,
        )
        assertTrue("thirdSpy must not have run yet", executionLog.none { it.contains("Third") })

        // Complete secondSpy → thirdSpy runs now
        queue.onComplete(Result.success(Unit))
        assertEquals(
            listOf(
                "execute:First", "complete:First",
                "execute:Second", "complete:Second",
                "execute:Third",
            ),
            executionLog,
        )
    }

    @Test
    fun `stray onComplete on empty queue is a no-op`() {
        val queue = GattOpQueue(mockGatt, mockHandler)

        // Should not throw
        queue.onComplete(Result.success("stray"))
        queue.onComplete(Result.failure(RuntimeException("stray")))

        // Queue remains usable
        val op = TestOp()
        queue.enqueue(op)
        assertEquals(1, op.executedCount)
    }

    @Test
    fun `late timeout after completion is a no-op`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val first = TestOp(description = "First")
        val second = TestOp(description = "Second")
        queue.enqueue(first)
        queue.enqueue(second)

        val firstTimeout = capturedTimeouts[0]

        // first completes normally
        queue.onComplete(Result.success("ok"))
        assertEquals(Result.success("ok"), first.result)

        // Now second is in flight; fire the stale first-timeout Runnable
        firstTimeout.run()

        // first.result unchanged; second.result unchanged (still in flight)
        assertEquals(Result.success("ok"), first.result)
        assertNull(second.result)
    }

    @Test
    fun `execute throwing propagates the thrown exception to caller`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val permissionDenied = SecurityException("BLUETOOTH_CONNECT revoked")
        val throwingOp = object : GattOp() {
            override val description = "Write characteristic"
            override val syncFailureMessage = "Failed to write characteristic"
            override val timeoutMs = 1000L
            var result: Result<Any?>? = null
            override fun execute(gatt: BluetoothGatt): Boolean {
                throw permissionDenied
            }
            override fun complete(result: Result<Any?>) {
                this.result = result
            }
        }
        val next = TestOp(description = "Next")
        queue.enqueue(throwingOp)
        queue.enqueue(next)

        assertSame(
            "Caller must receive the original thrown exception, not a masking IllegalStateException",
            permissionDenied, throwingOp.result!!.exceptionOrNull(),
        )
        assertEquals(
            "Queue must still advance to next op after a throw",
            1, next.executedCount,
        )
    }

    @Test
    fun `multiple enqueues while busy preserve FIFO order`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val executionOrder = mutableListOf<String>()
        fun makeOp(name: String) = object : GattOp() {
            override val description = name
            override val syncFailureMessage = "Failed to $name"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionOrder.add(name)
                return true
            }
            override fun complete(result: Result<Any?>) {}
        }

        queue.enqueue(makeOp("A"))
        queue.enqueue(makeOp("B"))
        queue.enqueue(makeOp("C"))
        queue.enqueue(makeOp("D"))

        assertEquals(listOf("A"), executionOrder)
        queue.onComplete(Result.success(Unit))
        assertEquals(listOf("A", "B"), executionOrder)
        queue.onComplete(Result.success(Unit))
        assertEquals(listOf("A", "B", "C"), executionOrder)
        queue.onComplete(Result.success(Unit))
        assertEquals(listOf("A", "B", "C", "D"), executionOrder)
    }
}
