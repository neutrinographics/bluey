# Phase 2a — Android GATT Operation Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serialize every GATT-layer operation per connection through an internal Kotlin queue so that Android's `BluetoothGatt` never sees concurrent ops, eliminating the sync-rejection race at its source.

**Architecture:** One `GattOpQueue` aggregate per connection inside `bluey_android`'s `ConnectionManager`. Strict-serial FIFO. All queue state mutation on the main thread (existing `handler.post` pattern from `ConnectionManager.kt`). Every GATT op (read/write char, read/write descriptor, discoverServices, requestMtu, readRssi, setNotification's CCCD write) routes through the queue. Per-op timeout via `handler.postDelayed`. Drain on disconnect with a new typed `GattOperationDisconnectedException` that `BlueyConnection` translates to the existing `DisconnectedException` from the `BlueyException` hierarchy.

**Tech Stack:** Kotlin (with `mockk` + JUnit for Kotlin tests), Dart (Flutter), Pigeon for type-safe platform channel bindings. Follows DDD (aggregate root, command objects, ubiquitous language) and strict TDD per CLAUDE.md.

---

## File Structure

**New files:**
- `bluey_platform_interface/lib/src/exceptions.dart` — modify to add `GattOperationDisconnectedException` alongside existing `GattOperationTimeoutException`
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOp.kt` — sealed class hierarchy for queue commands
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt` — per-connection serial queue
- `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattOpQueueTest.kt` — unit tests for the queue
- `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ConnectionManagerQueueTest.kt` — integration tests for `ConnectionManager`'s queue usage

**Modified files:**
- `bluey_platform_interface/test/exceptions_test.dart` — add `GattOperationDisconnectedException` test group
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt` — route ops through the queue, drain on disconnect, stop using `pendingX` maps
- `bluey_android/lib/src/android_connection_manager.dart` — rename translation helper + add `gatt-disconnected` branch
- `bluey_android/test/android_connection_manager_test.dart` — update to the renamed helper, add `gatt-disconnected` translation tests
- `bluey_ios/lib/src/ios_connection_manager.dart` — same rename + disconnect branch (iOS won't emit `gatt-disconnected` but handles it for symmetry)
- `bluey_ios/test/ios_connection_manager_test.dart` — mirror of Android test updates
- `bluey/lib/src/connection/bluey_connection.dart` — rename helper, add `DisconnectedException` translation, thread `deviceId` into `BlueyRemoteCharacteristic`/`BlueyRemoteDescriptor` for helper access
- `bluey/test/fakes/fake_platform.dart` — add `simulateWriteDisconnected` sibling to `simulateWriteTimeout`
- `bluey/test/connection/bluey_connection_timeout_test.dart` — add disconnect-surfacing tests
- `bluey_android/ANDROID_BLE_NOTES.md` — document the single-op constraint and queue semantics

**Unchanged but referenced:**
- `bluey/lib/src/shared/exceptions.dart` — existing `DisconnectedException` and `DisconnectReason.linkLoss` are reused as-is
- `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt` — template for the mockk+JUnit test pattern (copy its `setUp`/`tearDown` scaffolding)

**Worktree preparation (before starting):** Create a feature worktree for this work. The execution harness (subagent-driven-development) invokes `superpowers:using-git-worktrees` to set up `.worktrees/phase-2a-gatt-queue` on branch `feature/phase-2a-gatt-queue`. Every shell command in this plan assumes the working directory is inside that worktree. No global state changes outside the worktree.

---

## Task 1: Add `GattOperationDisconnectedException` to platform interface

**Files:**
- Modify: `bluey_platform_interface/lib/src/exceptions.dart`
- Modify: `bluey_platform_interface/test/exceptions_test.dart`

Mirror of Phase 1's `GattOperationTimeoutException` exactly: typed internal exception that the platform pass-through will throw when `PlatformException(code: 'gatt-disconnected')` comes across the Pigeon boundary. Used by `BlueyConnection` at the public API boundary to construct a `DisconnectedException`.

- [ ] **Step 1: Write the failing test**

In `bluey_platform_interface/test/exceptions_test.dart`, add a new group immediately after the existing `GattOperationTimeoutException` group (search for that group to find the insertion point). Keep indentation and style consistent with the existing group:

```dart
  group('GattOperationDisconnectedException', () {
    test('exposes the operation name and a default message', () {
      const e = GattOperationDisconnectedException('writeCharacteristic');

      expect(e.operation, equals('writeCharacteristic'));
      expect(
        e.toString(),
        contains('writeCharacteristic'),
        reason: 'toString should mention the operation for log readability',
      );
    });

    test('is an Exception so it can be caught with on Exception', () {
      const e = GattOperationDisconnectedException('readCharacteristic');
      expect(e, isA<Exception>());
    });

    test('two instances with the same operation are equal', () {
      const a = GattOperationDisconnectedException('readCharacteristic');
      const b = GattOperationDisconnectedException('readCharacteristic');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

```
cd bluey_platform_interface && flutter test test/exceptions_test.dart
```

Expected: FAIL with "Undefined name 'GattOperationDisconnectedException'" or similar.

- [ ] **Step 3: Add the class**

In `bluey_platform_interface/lib/src/exceptions.dart`, add this class directly below the existing `GattOperationTimeoutException`:

```dart
/// A GATT operation (read, write, etc.) could not complete because the
/// underlying connection was torn down before the operation's response
/// was received.
///
/// Distinct from [GattOperationTimeoutException]: the peer didn't just stop
/// responding — the link itself is gone. Consumers that monitor liveness
/// (e.g. `LifecycleClient`) can use the presence of this exception to
/// distinguish "timeout" from "connection loss" when deciding how to react.
class GattOperationDisconnectedException implements Exception {
  /// Name of the platform interface method whose operation was aborted,
  /// e.g. `'writeCharacteristic'`. Used for diagnostics; not parsed by
  /// callers.
  final String operation;

  const GattOperationDisconnectedException(this.operation);

  @override
  String toString() =>
      'GattOperationDisconnectedException: $operation aborted due to disconnect';

  @override
  bool operator ==(Object other) =>
      other is GattOperationDisconnectedException && other.operation == operation;

  @override
  int get hashCode => operation.hashCode;
}
```

- [ ] **Step 4: Run test to verify it passes**

```
cd bluey_platform_interface && flutter test test/exceptions_test.dart
```

Expected: all tests PASS (the existing 4 `GattOperationTimeoutException` tests + 3 new `GattOperationDisconnectedException` tests).

- [ ] **Step 5: Commit**

```bash
git add bluey_platform_interface/lib/src/exceptions.dart \
        bluey_platform_interface/test/exceptions_test.dart
git commit -m "$(cat <<'EOF'
feat(platform-interface): add GattOperationDisconnectedException

Typed internal exception that Phase 2a's Kotlin queue will produce
(via PlatformException(code: 'gatt-disconnected')) when the link
drops while a GATT op is pending. BlueyConnection will translate
this into the public DisconnectedException at the API boundary.

Mirror shape of GattOperationTimeoutException: value-equality,
const constructor, Exception conformance.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add failing `GattOpQueue` unit tests

**Files:**
- Create: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattOpQueueTest.kt`

This task writes the red-phase tests. The queue itself lands in Task 3.

Copy `GattServerTest.kt`'s mockk+JUnit scaffolding (mocking `Log`, `Looper`, `Handler`). For the queue tests, mock `Handler.postDelayed` to **capture** the timeout Runnable without executing it — tests fire it manually to simulate a timeout. Mock `Handler.post` to execute immediately so callback delivery is synchronous in tests.

- [ ] **Step 1: Create the test file**

Create `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattOpQueueTest.kt`:

```kotlin
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
        // removeCallbacks is a no-op in tests (we drop references manually)
        every { mockHandler.removeCallbacks(any()) } just Runs
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
    }

    /** A test-only op that records its outcomes and exposes its callback. */
    private class TestOp(
        override val description: String = "Test op",
        override val timeoutMs: Long = 1000,
        private val executeReturns: Boolean = true,
    ) : GattOp() {
        var executedCount = 0
        var result: Result<Any?>? = null

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
        assertNull(op.result)  // async completion pending
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

        // Fire the captured timeout Runnable for `first`
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

        // After drain, enqueueing a new op should start it immediately
        val recovery = TestOp(description = "Recovery")
        queue.enqueue(recovery)
        assertEquals(1, recovery.executedCount)
    }

    @Test
    fun `reentrant enqueue inside user callback preserves FIFO order`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val executionLog = mutableListOf<String>()

        val third = TestOp(description = "Third").apply {
            /* plain op */
        }
        val second = TestOp(description = "Second")
        val first = object : GattOp() {
            override val description = "First"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionLog.add("execute:First")
                return true
            }
            override fun complete(result: Result<Any?>) {
                executionLog.add("complete:First")
                // Reentrantly enqueue a new op — should run AFTER already-pending `second`
                queue.enqueue(third)
            }
        }

        // Wrap `second` and `third` to record execution order
        val secondSpy = object : GattOp() {
            override val description = "Second"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionLog.add("execute:Second")
                return true
            }
            override fun complete(result: Result<Any?>) {
                executionLog.add("complete:Second")
            }
        }
        val thirdSpy = object : GattOp() {
            override val description = "Third"
            override val timeoutMs = 1000L
            override fun execute(gatt: BluetoothGatt): Boolean {
                executionLog.add("execute:Third")
                return true
            }
            override fun complete(result: Result<Any?>) {
                executionLog.add("complete:Third")
            }
        }

        queue.enqueue(first)
        queue.enqueue(secondSpy)

        // Complete `first` → its callback enqueues `thirdSpy`
        // Expected order after first completion: secondSpy executes, then thirdSpy
        queue.onComplete(Result.success(Unit))

        // Need to rebind the reentrant closure to target thirdSpy, not `third`.
        // Fix the test by making first.complete enqueue thirdSpy instead:
        // (see adjustment note below)

        // Actually the check: secondSpy must execute before thirdSpy is even enqueued
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

        // Capture the timeout BEFORE completing first
        val firstTimeout = capturedTimeouts[0]

        // first completes normally
        queue.onComplete(Result.success("ok"))
        assertEquals(Result.success("ok"), first.result)

        // Now second is executing; fire the stale timeout for first
        firstTimeout.run()

        // first.result unchanged; second.result unchanged (still running)
        assertEquals(Result.success("ok"), first.result)
        assertNull(second.result)
    }

    @Test
    fun `multiple enqueues while busy preserve FIFO order`() {
        val queue = GattOpQueue(mockGatt, mockHandler)
        val executionOrder = mutableListOf<String>()
        fun makeOp(name: String) = object : GattOp() {
            override val description = name
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
```

**Note on the reentrant test body:** the inline comment flags a bug in the test logic (the `first` callback's `queue.enqueue(third)` references a non-spy op). Before committing, rewrite `first.complete` so it enqueues `thirdSpy` directly — i.e. declare `thirdSpy` above `first`, then reference it in `first.complete`. The corrected shape:

```kotlin
val thirdSpy = object : GattOp() { /* ...as above... */ }
val secondSpy = object : GattOp() { /* ...as above... */ }
val first = object : GattOp() {
    override val description = "First"
    override val timeoutMs = 1000L
    override fun execute(gatt: BluetoothGatt): Boolean {
        executionLog.add("execute:First")
        return true
    }
    override fun complete(result: Result<Any?>) {
        executionLog.add("complete:First")
        queue.enqueue(thirdSpy)
    }
}
queue.enqueue(first)
queue.enqueue(secondSpy)
// ...assertions as above...
```

- [ ] **Step 2: Run tests to verify they all fail**

```
cd bluey_android && flutter test
```

Expected: FAIL. The Kotlin tests should fail at compilation because `GattOpQueue` and `GattOp` don't exist yet. If `flutter test` doesn't compile the Kotlin side, try the fuller invocation:

```
cd bluey_android/android && ./gradlew test
```

Expected: compilation errors referencing `GattOpQueue` and `GattOp`.

- [ ] **Step 3: Commit (red commit, intentional)**

```bash
git add bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattOpQueueTest.kt
git commit -m "$(cat <<'EOF'
test(bluey_android): add failing GattOpQueue unit tests

Covers the queue's core invariants: enqueue-when-idle starts op,
enqueue-while-busy waits, onComplete fires callback + advances,
timeout fires, sync rejection fires + advances, drainAll empties,
FIFO order, stray/late callback resilience, reentrant enqueue
preserves order.

Fails at this commit by design — Task 3 implements GattOpQueue
and GattOp to turn them green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Implement `GattOpQueue` and `GattOp` sealed hierarchy

**Files:**
- Create: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOp.kt`
- Create: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt`

- [ ] **Step 1: Create `GattOp.kt`**

```kotlin
package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.os.Build

/**
 * A serialized GATT command. Each subclass knows how to initiate itself on a
 * [BluetoothGatt] handle and how to deliver the result to its caller.
 *
 * Instances are Command objects (Command pattern) — they carry a user
 * callback executed exactly once. Configuration fields are immutable after
 * construction.
 */
internal sealed class GattOp {
    /** Human-readable description for error messages, e.g. "Write characteristic". */
    abstract val description: String

    /** Timeout in milliseconds. Sourced from ConnectionManager configuration. */
    abstract val timeoutMs: Long

    /**
     * Initiates the op on the provided GATT handle.
     *
     * @return `true` if the OS accepted the request (async completion pending),
     *         `false` if synchronously rejected. On `false`, the queue fails
     *         the callback with an [IllegalStateException] and advances.
     */
    abstract fun execute(gatt: BluetoothGatt): Boolean

    /**
     * Delivers the op's outcome to the caller. Called on successful
     * [android.bluetooth.BluetoothGattCallback] completion, timeout,
     * synchronous rejection, or queue drain on disconnect.
     */
    abstract fun complete(result: Result<Any?>)
}

internal class ReadCharacteristicOp(
    private val characteristic: BluetoothGattCharacteristic,
    private val callback: (Result<ByteArray>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Read characteristic"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.readCharacteristic(characteristic)
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as ByteArray } as Result<ByteArray>)
    }
}

internal class WriteCharacteristicOp(
    private val characteristic: BluetoothGattCharacteristic,
    private val value: ByteArray,
    private val writeType: Int,
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Write characteristic"
    override fun execute(gatt: BluetoothGatt): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, value, writeType) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = writeType
            @Suppress("DEPRECATION")
            characteristic.value = value
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
    }
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { Unit } as Result<Unit>)
    }
}

internal class ReadDescriptorOp(
    private val descriptor: BluetoothGattDescriptor,
    private val callback: (Result<ByteArray>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Read descriptor"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.readDescriptor(descriptor)
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as ByteArray } as Result<ByteArray>)
    }
}

internal class WriteDescriptorOp(
    private val descriptor: BluetoothGattDescriptor,
    private val value: ByteArray,
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Write descriptor"
    override fun execute(gatt: BluetoothGatt): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = value
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { Unit } as Result<Unit>)
    }
}

internal class EnableNotifyCccdOp(
    descriptor: BluetoothGattDescriptor,
    value: ByteArray,
    callback: (Result<Unit>) -> Unit,
    timeoutMs: Long,
) : GattOp() {
    // Reuses WriteDescriptorOp semantics but carries its own description so
    // timeout/sync-failure messages read as "Enable notify CCCD timed out".
    private val delegate = WriteDescriptorOp(descriptor, value, callback, timeoutMs)
    override val description = "Enable notify CCCD"
    override val timeoutMs: Long = timeoutMs
    override fun execute(gatt: BluetoothGatt): Boolean = delegate.execute(gatt)
    override fun complete(result: Result<Any?>) = delegate.complete(result)
}

internal class DiscoverServicesOp(
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Service discovery"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.discoverServices()
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        // Caller unboxes to List<ServiceDto> from BluetoothGatt.services inside
        // the callback registered at enqueue time — see ConnectionManager's
        // onServicesDiscovered override. The op itself returns Unit on success.
        callback(result.map { Unit } as Result<Unit>)
    }
}

internal class RequestMtuOp(
    private val mtu: Int,
    private val callback: (Result<Long>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "MTU request"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.requestMtu(mtu)
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as Long } as Result<Long>)
    }
}

internal class ReadRssiOp(
    private val callback: (Result<Long>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "RSSI read"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.readRemoteRssi()
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as Long } as Result<Long>)
    }
}
```

- [ ] **Step 2: Create `GattOpQueue.kt`**

```kotlin
package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import android.os.Handler
import android.util.Log

/**
 * Per-connection serial GATT operation queue.
 *
 * Aggregate root for "work-in-flight on a single [BluetoothGatt] handle."
 * Enforces Android's single-op-in-flight constraint by serializing every
 * GATT operation through a FIFO queue with per-op timeouts.
 *
 * Thread safety: this class is NOT thread-safe. All public methods must be
 * called on the main thread (the same thread the supplied [Handler]
 * dispatches on). The existing [ConnectionManager.createGattCallback]
 * pattern marshals [android.bluetooth.BluetoothGattCallback] events via
 * `handler.post { queue.onComplete(...) }` before touching the queue.
 */
internal class GattOpQueue(
    private val gatt: BluetoothGatt,
    private val handler: Handler,
) {
    private val pending = ArrayDeque<GattOp>()
    private var current: GattOp? = null
    private var currentTimeout: Runnable? = null

    /**
     * Adds [op] to the queue. If the queue is idle, the op is started
     * immediately. Otherwise it runs after all previously-enqueued ops
     * complete (FIFO).
     */
    fun enqueue(op: GattOp) {
        pending.addLast(op)
        if (current == null) startNext()
    }

    /**
     * Signals that the currently-in-flight op has completed (successfully
     * or with a status-based failure). Fires the op's callback, advances
     * the queue.
     *
     * No-op if there is no current op (stray callback from the BLE stack,
     * e.g. the native layer firing a delayed callback after we've already
     * timed out or drained).
     */
    fun onComplete(result: Result<Any?>) {
        val op = current ?: return
        currentTimeout?.let { handler.removeCallbacks(it) }
        currentTimeout = null
        current = null  // clear BEFORE firing callback (reentrancy)
        try {
            op.complete(result)
        } catch (e: Throwable) {
            Log.e(TAG, "GattOp.complete threw: $e", e)
        }
        if (pending.isNotEmpty()) startNext()
    }

    /**
     * Fails the currently-in-flight op and every queued op with [reason],
     * then resets the queue. Called when the connection is torn down.
     */
    fun drainAll(reason: Throwable) {
        currentTimeout?.let { handler.removeCallbacks(it) }
        currentTimeout = null
        val inFlight = current
        val queued = pending.toList()
        current = null
        pending.clear()
        inFlight?.let {
            try { it.complete(Result.failure(reason)) }
            catch (e: Throwable) { Log.e(TAG, "GattOp.complete threw during drain: $e", e) }
        }
        for (op in queued) {
            try { op.complete(Result.failure(reason)) }
            catch (e: Throwable) { Log.e(TAG, "GattOp.complete threw during drain: $e", e) }
        }
    }

    private fun startNext() {
        val op = pending.removeFirst()
        current = op

        val timeout = Runnable {
            // Defensive: fire only if this op is still current
            if (current !== op) return@Runnable
            currentTimeout = null
            current = null
            try {
                op.complete(
                    Result.failure(
                        FlutterError(
                            "gatt-timeout",
                            "${op.description} timed out",
                            null,
                        )
                    )
                )
            } catch (e: Throwable) {
                Log.e(TAG, "GattOp.complete threw during timeout: $e", e)
            }
            if (pending.isNotEmpty()) startNext()
        }
        currentTimeout = timeout
        handler.postDelayed(timeout, op.timeoutMs)

        val accepted = try {
            op.execute(gatt)
        } catch (e: Throwable) {
            Log.e(TAG, "GattOp.execute threw: $e", e)
            false
        }

        if (!accepted) {
            // Sync rejection — fail immediately, advance
            currentTimeout?.let { handler.removeCallbacks(it) }
            currentTimeout = null
            current = null
            val lowerFirst = op.description.replaceFirstChar { it.lowercase() }
            try {
                op.complete(
                    Result.failure(
                        IllegalStateException("Failed to $lowerFirst")
                    )
                )
            } catch (e: Throwable) {
                Log.e(TAG, "GattOp.complete threw during sync-failure: $e", e)
            }
            if (pending.isNotEmpty()) startNext()
        }
    }

    companion object {
        private const val TAG = "GattOpQueue"
    }
}
```

- [ ] **Step 3: Run the queue unit tests — they should now pass**

```
cd bluey_android && flutter test
```

Or if the Kotlin tests aren't picked up via `flutter test`:

```
cd bluey_android/android && ./gradlew test
```

Expected: all 10 `GattOpQueueTest` tests PASS.

- [ ] **Step 4: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOp.kt \
        bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt
git commit -m "$(cat <<'EOF'
feat(bluey_android): add GattOpQueue and GattOp sealed hierarchy

Per-connection serial queue that enforces Android's single-op-in-flight
constraint for BluetoothGatt. Command objects (Command pattern) per op
type: Read/WriteCharacteristicOp, Read/WriteDescriptorOp,
EnableNotifyCccdOp, DiscoverServicesOp, RequestMtuOp, ReadRssiOp.

Thread-unsafe by design — ConnectionManager must marshal
BluetoothGattCallback events to the main thread via handler.post
before touching the queue (Task 5).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add failing `ConnectionManager` integration tests

**Files:**
- Create: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ConnectionManagerQueueTest.kt`

Red-phase tests that exercise `ConnectionManager`'s use of the queue end-to-end. Mock `BluetoothGatt` and `BluetoothAdapter`; use the real `GattOpQueue` (not mocked). Verify that two simultaneous writes don't collide at the `BluetoothGatt` level.

- [ ] **Step 1: Create the test file**

```kotlin
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

        // Execute handler.post immediately; capture handler.postDelayed
        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run(); true
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
        every { mockDevice.connectGatt(any(), any(), any<BluetoothGattCallback>(), any()) } answers {
            capturedGattCallback = thirdArg()
            mockGatt
        }

        connectionManager = ConnectionManager(mockContext, mockAdapter, mockFlutterApi)

        // Simulate a completed connection so internal `connections[deviceId]` is populated
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

    private fun mockCharacteristic(charUuid: JavaUUID = testCharUuid): BluetoothGattCharacteristic {
        val char = mockk<BluetoothGattCharacteristic>(relaxed = true)
        every { char.uuid } returns charUuid
        val service = mockk<BluetoothGattService>(relaxed = true)
        every { service.uuid } returns testServiceUuid
        every { service.getCharacteristic(charUuid) } returns char
        every { mockGatt.services } returns listOf(service)
        return char
    }

    @Test
    fun `two writes back-to-back execute in submission order`() {
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any()) } returns BluetoothGatt.GATT_SUCCESS
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
        verify(exactly = 1) { mockGatt.writeCharacteristic(char, byteArrayOf(0x01), any()) }
        verify(exactly = 0) { mockGatt.writeCharacteristic(char, byteArrayOf(0x02), any()) }

        // Fire onCharacteristicWrite for the first op
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)

        // Now the second write is in flight
        verify(exactly = 1) { mockGatt.writeCharacteristic(char, byteArrayOf(0x02), any()) }

        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)

        assertEquals(2, results.size)
    }

    @Test
    fun `onConnectionStateChange DISCONNECTED drains pending callbacks with gatt-disconnected`() {
        val char = mockCharacteristic()
        every { mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any()) } returns BluetoothGatt.GATT_SUCCESS
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
        every { mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any()) } returns BluetoothGatt.GATT_SUCCESS

        // Put an op in flight to prove the notification doesn't disturb it
        connectionManager.writeCharacteristic(
            deviceAddress, testCharUuid.toString(),
            byteArrayOf(0x01), true,
        ) { /* ignored */ }
        verify(exactly = 1) { mockGatt.writeCharacteristic(any<BluetoothGattCharacteristic>(), any(), any()) }

        val notifValue = byteArrayOf(0x42, 0x43)
        capturedGattCallback!!.onCharacteristicChanged(mockGatt, char, notifValue)

        verify {
            mockFlutterApi.onNotification(
                deviceAddress, testCharUuid.toString().lowercase(), notifValue,
                any(),
            )
        }
        // Op in flight unaffected
        capturedGattCallback!!.onCharacteristicWrite(mockGatt, char, BluetoothGatt.GATT_SUCCESS)
    }
}
```

**Note on API signatures:** the `mockFlutterApi.onNotification(...)` call in the last test references the Pigeon-generated signature. If the actual signature differs (check `Messages.g.kt`'s `BlueyFlutterApi` class), adjust the matcher accordingly. The test's intent is "the queue does not intercept notifications; they flow to the Flutter side as before."

- [ ] **Step 2: Run tests to verify they fail**

```
cd bluey_android/android && ./gradlew test
```

Expected: FAIL — `ConnectionManager` doesn't route through `GattOpQueue` yet. The tests reference behavior that Task 5 implements.

- [ ] **Step 3: Commit (red commit, intentional)**

```bash
git add bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ConnectionManagerQueueTest.kt
git commit -m "$(cat <<'EOF'
test(bluey_android): add failing ConnectionManager queue integration tests

Pins down the observable contract once Task 5 routes GATT ops through
GattOpQueue: two writes serialize at the BluetoothGatt layer, drain on
disconnect fires pending callbacks with gatt-disconnected,
setNotification's CCCD write routes through the queue, incoming
notifications bypass the queue.

Fails at this commit by design — Task 5 is the GREEN step.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Route `ConnectionManager` GATT ops through the queue

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`

This is the core behavioral change. `ConnectionManager`'s public GATT methods (`readCharacteristic`, `writeCharacteristic`, `setNotification`, `readDescriptor`, `writeDescriptor`, `discoverServices`, `requestMtu`, `readRssi`) now enqueue a `GattOp` instead of firing `gatt.X()` directly. Each `BluetoothGattCallback` override delegates to the queue via `handler.post { queue.onComplete(...) }`. The `pendingX` maps and `cancelAllTimeouts` helper stop being called (declarations remain for Phase 2b to remove).

- [ ] **Step 1: Add queues field and helpers**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`, add a new private field right after the existing `connections` field (around line 34):

```kotlin
    private val queues = mutableMapOf<String, GattOpQueue>()
```

Add a small helper to resolve the queue for a device address (paste just before `createGattCallback`, around line 611):

```kotlin
    /** Resolves the [GattOpQueue] for [deviceId], or null if no connection exists. */
    private fun queueFor(deviceId: String): GattOpQueue? = queues[deviceId]
```

- [ ] **Step 2: Replace `readCharacteristic` body**

Find `fun readCharacteristic(...)` (around line 229). Replace its body with:

```kotlin
    fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        queue.enqueue(ReadCharacteristicOp(characteristic, callback, readCharacteristicTimeoutMs))
    }
```

- [ ] **Step 3: Replace `writeCharacteristic` body**

Find `fun writeCharacteristic(...)` (around line 270). Replace its body with:

```kotlin
    fun writeCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        value: ByteArray,
        withResponse: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        val writeType = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        queue.enqueue(
            WriteCharacteristicOp(
                characteristic, value, writeType, callback, writeCharacteristicTimeoutMs,
            )
        )
    }
```

- [ ] **Step 4: Replace `setNotification` body**

Find `fun setNotification(...)` (around line 330). Replace its body with:

```kotlin
    fun setNotification(
        deviceId: String,
        characteristicUuid: String,
        enable: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }

        // Step 1 (inline, synchronous): enable local notifications
        if (!gatt.setCharacteristicNotification(characteristic, enable)) {
            callback(Result.failure(IllegalStateException("Failed to set notification")))
            return
        }

        // Step 2: if the characteristic exposes a CCCD, queue its write
        val cccd = characteristic.getDescriptor(CCCD_UUID)
        if (cccd == null) {
            callback(Result.success(Unit))
            return
        }
        val cccdValue = when {
            !enable -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0 ->
                BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            else -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        queue.enqueue(
            EnableNotifyCccdOp(cccd, cccdValue, callback, writeDescriptorTimeoutMs),
        )
    }
```

- [ ] **Step 5: Replace `readDescriptor` body**

Find `fun readDescriptor(...)` (around line 393). Replace body with:

```kotlin
    fun readDescriptor(
        deviceId: String,
        descriptorUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val descriptor = findDescriptor(gatt, descriptorUuid)
        if (descriptor == null) {
            callback(Result.failure(IllegalStateException("Descriptor not found: $descriptorUuid")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        queue.enqueue(ReadDescriptorOp(descriptor, callback, readDescriptorTimeoutMs))
    }
```

- [ ] **Step 6: Replace `writeDescriptor` body**

Find `fun writeDescriptor(...)` (around line 433). Replace body with:

```kotlin
    fun writeDescriptor(
        deviceId: String,
        descriptorUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val descriptor = findDescriptor(gatt, descriptorUuid)
        if (descriptor == null) {
            callback(Result.failure(IllegalStateException("Descriptor not found: $descriptorUuid")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        queue.enqueue(WriteDescriptorOp(descriptor, value, callback, writeDescriptorTimeoutMs))
    }
```

- [ ] **Step 7: Replace `discoverServices` body**

Find `fun discoverServices(...)` (around line 193). Replace body with:

```kotlin
    fun discoverServices(deviceId: String, callback: (Result<List<ServiceDto>>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        // The DiscoverServicesOp only signals success/failure to the caller;
        // the actual service list is read from gatt.services inside
        // onServicesDiscovered below. To route through the queue while still
        // returning List<ServiceDto>, we unbox inside this wrapper callback:
        queue.enqueue(
            DiscoverServicesOp(
                callback = { result ->
                    val mapped = result.map { mapServices(gatt.services) }
                    callback(mapped)
                },
                timeoutMs = discoverServicesTimeoutMs,
            )
        )
    }
```

- [ ] **Step 8: Replace `requestMtu` body**

Find `fun requestMtu(...)` (around line 483). Replace body with:

```kotlin
    fun requestMtu(deviceId: String, mtu: Long, callback: (Result<Long>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        queue.enqueue(RequestMtuOp(mtu.toInt(), callback, requestMtuTimeoutMs))
    }
```

- [ ] **Step 9: Replace `readRssi` body**

Find `fun readRssi(...)` (around line 513). Replace body with:

```kotlin
    fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(IllegalStateException("No queue for connection: $deviceId")))
            return
        }
        queue.enqueue(ReadRssiOp(callback, readRssiTimeoutMs))
    }
```

- [ ] **Step 10: Update `onConnectionStateChange` to create / destroy queue**

Find `override fun onConnectionStateChange(...)` (around line 613). Update the `STATE_CONNECTED` and `STATE_DISCONNECTED` branches so they manage the per-connection queue alongside the existing connection bookkeeping:

```kotlin
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTING)
                    }

                    BluetoothProfile.STATE_CONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTED)
                        pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
                        // Create the per-connection queue NOW that gatt is usable
                        queues[deviceId] = GattOpQueue(gatt, handler)
                        val pendingCallback = pendingConnections.remove(deviceId)
                        if (pendingCallback != null) {
                            handler.post {
                                pendingCallback.invoke(Result.success(deviceId))
                            }
                        }
                    }

                    BluetoothProfile.STATE_DISCONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                        // Drain any pending queue operations with gatt-disconnected
                        queues.remove(deviceId)?.let { queue ->
                            handler.post {
                                queue.drainAll(
                                    FlutterError("gatt-disconnected",
                                        "connection lost with pending GATT op", null)
                                )
                            }
                        }
                        // Legacy map cleanup (these should be unused after Task 5,
                        // but the declarations remain for 2b to remove — clearing
                        // them defensively here is cheap and avoids cross-connection
                        // pollution if any stale entries linger).
                        cancelAllTimeouts(deviceId)
                        val pendingCallback = pendingConnections.remove(deviceId)
                        if (pendingCallback != null) {
                            val errorMessage = if (status != BluetoothGatt.GATT_SUCCESS) {
                                "Connection failed with status: $status"
                            } else {
                                "Connection failed"
                            }
                            handler.post {
                                pendingCallback.invoke(Result.failure(IllegalStateException(errorMessage)))
                            }
                        }
                        connections.remove(deviceId)
                        try { gatt.close() } catch (e: Exception) { /* ignore */ }
                    }
                }
            }
```

- [ ] **Step 11: Route `BluetoothGattCallback` completions into the queue**

Update every GATT-completion override so it delegates to `queueFor(deviceId)?.onComplete(...)` via `handler.post`. Replace the existing bodies of `onServicesDiscovered`, both `onCharacteristicRead` overloads, `onCharacteristicWrite`, both `onDescriptorRead` overloads, `onDescriptorWrite`, `onMtuChanged`, `onReadRemoteRssi`.

Pattern (apply the same shape to each callback, using the op-appropriate `Result` value):

```kotlin
            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                handler.post {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(IllegalStateException(
                            "Service discovery failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int,
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(value)
                    } else {
                        Result.failure(IllegalStateException(
                            "Read failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(characteristic.value ?: ByteArray(0))
                    } else {
                        Result.failure(IllegalStateException(
                            "Read failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(IllegalStateException(
                            "Write failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
                value: ByteArray,
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(value)
                    } else {
                        Result.failure(IllegalStateException(
                            "Descriptor read failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(descriptor.value ?: ByteArray(0))
                    } else {
                        Result.failure(IllegalStateException(
                            "Descriptor read failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(IllegalStateException(
                            "Descriptor write failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(mtu.toLong())
                    } else {
                        Result.failure(IllegalStateException(
                            "MTU request failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(rssi.toLong())
                    } else {
                        Result.failure(IllegalStateException(
                            "RSSI read failed with status: $status"))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }
```

**Do NOT change:** `onCharacteristicChanged` (notifications). It remains as-is, forwarding to `mockFlutterApi.onNotification(...)` / the real `flutterApi` without touching the queue.

- [ ] **Step 12: Run all bluey_android tests**

```
cd bluey_android/android && ./gradlew test
```

Expected: all `GattOpQueueTest` (Task 3) and `ConnectionManagerQueueTest` (Task 4) tests PASS. Any existing Kotlin tests also pass.

Then run the Dart-side tests too to confirm no regression:

```
cd bluey_android && flutter test
```

Expected: existing 59 Dart-side tests PASS.

- [ ] **Step 13: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt
git commit -m "$(cat <<'EOF'
refactor(bluey_android): route GATT ops through GattOpQueue

Every GATT op now enqueues on the per-connection queue; every
BluetoothGattCallback override delegates to queue.onComplete via
handler.post. The queue enforces Android's single-op-in-flight
constraint; concurrent callers no longer get "Failed to <op>" errors
because another op is pending.

Drain-on-disconnect emits FlutterError(code: "gatt-disconnected")
for all in-flight and queued callbacks, replacing the dangling-
callback behavior that cancelAllTimeouts left behind.

The legacy pendingX maps and cancelAllTimeouts helper are no longer
populated or called from the queue-managed paths. Their declarations
remain in ConnectionManager for Phase 2b to remove; this keeps the
diff focused on the behavioral change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Drain queue on disconnect with `gatt-disconnected` code — verification

**Files:** no new changes (Task 5 already included the drain logic in `onConnectionStateChange`).

This task exists only to verify the drain test from Task 4 passes and to run the broader Kotlin suite before moving to the Dart layer. It produces no commit of its own.

- [ ] **Step 1: Run the drain integration test**

```
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.ConnectionManagerQueueTest.onConnectionStateChange*drains*"
```

Expected: PASS.

- [ ] **Step 2: Run the full Kotlin suite**

```
cd bluey_android/android && ./gradlew test
```

Expected: all Kotlin tests PASS. No new commit for this task.

---

## Task 7: Dart pass-through — rename helper and add `gatt-disconnected` branch

**Files:**
- Modify: `bluey_android/lib/src/android_connection_manager.dart`
- Modify: `bluey_android/test/android_connection_manager_test.dart`
- Modify: `bluey_ios/lib/src/ios_connection_manager.dart`
- Modify: `bluey_ios/test/ios_connection_manager_test.dart`

Rename `_translateGattTimeout` → `_translateGattPlatformError` in both platform packages (iOS handles `gatt-disconnected` for symmetry even though Kotlin is the only emitter today). Update all call sites.

- [ ] **Step 1: Write failing tests in `bluey_android/test/android_connection_manager_test.dart`**

Find the existing `group('error translation', ...)` (around line 398). Add three new tests inside it, immediately before the closing `});`:

```dart
      test(
        'writeCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException',
        () async {
          when(() => mockHostApi.writeCharacteristic(
                any(), any(), any(), any(),
              )).thenThrow(
            PlatformException(code: 'gatt-disconnected', message: 'link lost'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'writeCharacteristic')),
          );
        },
      );

      test(
        'readCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException',
        () async {
          when(() => mockHostApi.readCharacteristic(any(), any())).thenThrow(
            PlatformException(code: 'gatt-disconnected', message: 'link lost'),
          );

          expect(
            () => connectionManager.readCharacteristic('device-1', 'char-uuid'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'readCharacteristic')),
          );
        },
      );

      test(
        'all wrapped methods translate gatt-disconnected with correct operation name',
        () async {
          final disconnect = PlatformException(
            code: 'gatt-disconnected',
            message: 'link lost',
          );

          when(() => mockHostApi.setNotification(any(), any(), any()))
              .thenThrow(disconnect);
          await expectLater(
            () => connectionManager.setNotification('d', 'c', true),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'setNotification')),
          );

          when(() => mockHostApi.readDescriptor(any(), any()))
              .thenThrow(disconnect);
          await expectLater(
            () => connectionManager.readDescriptor('d', 'desc'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'readDescriptor')),
          );

          when(() => mockHostApi.writeDescriptor(any(), any(), any()))
              .thenThrow(disconnect);
          await expectLater(
            () => connectionManager.writeDescriptor(
              'd', 'desc', Uint8List.fromList([0x01]),
            ),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'writeDescriptor')),
          );

          when(() => mockHostApi.requestMtu(any(), any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.requestMtu('d', 200),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'requestMtu')),
          );

          when(() => mockHostApi.readRssi(any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.readRssi('d'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'readRssi')),
          );

          when(() => mockHostApi.discoverServices(any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.discoverServices('d'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'discoverServices')),
          );
        },
      );
```

- [ ] **Step 2: Run the new tests — they fail**

```
cd bluey_android && flutter test test/android_connection_manager_test.dart \
  --name "translates PlatformException(gatt-disconnected)"
```

Expected: FAIL. The helper doesn't recognize `gatt-disconnected` yet.

- [ ] **Step 3: Update `bluey_android/lib/src/android_connection_manager.dart`**

Find the `_translateGattTimeout` top-level function (around line 14). Rename it to `_translateGattPlatformError` and add the disconnect branch:

```dart
/// Catches a [PlatformException] thrown by Pigeon and re-throws it as the
/// matching typed platform-interface exception: `'gatt-timeout'` →
/// [GattOperationTimeoutException], `'gatt-disconnected'` →
/// [GattOperationDisconnectedException]. Other errors propagate unchanged.
///
/// Kept package-private so the same wrapper can be used by every GATT
/// operation in this file without leaking translation logic into the
/// platform interface contract.
Future<T> _translateGattPlatformError<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-timeout') {
      throw GattOperationTimeoutException(operation);
    }
    if (e.code == 'gatt-disconnected') {
      throw GattOperationDisconnectedException(operation);
    }
    rethrow;
  }
}
```

Then find every `_translateGattTimeout(...)` call site in the same file (there are 8 of them) and rename to `_translateGattPlatformError(...)`. The operation-name string arguments stay unchanged.

- [ ] **Step 4: Run all bluey_android tests — verify green**

```
cd bluey_android && flutter test
```

Expected: all 62+ tests PASS (59 existing + 3 new disconnect-translation tests). No regression on the Phase 1 timeout tests.

- [ ] **Step 5: Apply the same update to `bluey_ios/lib/src/ios_connection_manager.dart`**

Same rename, same pattern. Find the helper (around line 17), rename to `_translateGattPlatformError`, add the disconnect branch. Update all `_translateGattPlatformError(...)` call sites (there are 7 on iOS).

- [ ] **Step 6: Add matching tests to `bluey_ios/test/ios_connection_manager_test.dart`**

Inside the existing `group('error translation', ...)`, add three tests mirroring Step 1 (but use `code: 'gatt-disconnected'` and assert `GattOperationDisconnectedException`). Drop the `requestMtu` case since iOS has no `requestMtu`.

- [ ] **Step 7: Run all bluey_ios tests — verify green**

```
cd bluey_ios && flutter test
```

Expected: all 81+ tests PASS (78 existing + 3 new disconnect-translation tests).

- [ ] **Step 8: Verify branch and commit**

```
cd /Users/joel/git/neutrinographics/bluey/.worktrees/phase-2a-gatt-queue && git rev-parse --abbrev-ref HEAD
```

Expect `feature/phase-2a-gatt-queue`. Then:

```bash
git add bluey_android/lib/src/android_connection_manager.dart \
        bluey_android/test/android_connection_manager_test.dart \
        bluey_ios/lib/src/ios_connection_manager.dart \
        bluey_ios/test/ios_connection_manager_test.dart
git commit -m "$(cat <<'EOF'
refactor(bluey_android,bluey_ios): rename helper and add gatt-disconnected branch

_translateGattTimeout → _translateGattPlatformError. Adds the second
branch handling PlatformException(code: 'gatt-disconnected') →
GattOperationDisconnectedException, mirroring the existing Phase 1
timeout translation.

iOS handles the code for symmetry even though its native side doesn't
emit it today; keeps the pass-through behavior consistent across
platforms if iOS ever gains a connection-drain equivalent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Surface `DisconnectedException` from `BlueyConnection`

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`

Rename the local helper `_translateGattTimeout` → `_translateGattPlatformError` and add the `GattOperationDisconnectedException` → `DisconnectedException(deviceId, DisconnectReason.linkLoss)` branch. The helper must have access to the `BlueyConnection.deviceId`, so it becomes an instance method (or a free function taking `deviceId`) — resolve whichever reads cleaner. `BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor` need the same access; plumb `deviceId` into them at construction time.

- [ ] **Step 1: Inspect the current helper shape**

Read `bluey/lib/src/connection/bluey_connection.dart` to locate:
- The top-level `_translateGattTimeout<T>` function (just after imports).
- Every call site in `BlueyConnection`, `BlueyRemoteCharacteristic`, `BlueyRemoteDescriptor` (9 sites, as cataloged in the Phase 1 plan at `docs/superpowers/plans/2026-04-20-lifecycle-timeout-detection.md`).
- The constructors for `BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor`. Note: today they take `connectionId` (String) but NOT `deviceId` (UUID).

- [ ] **Step 2: Update helpers and call sites**

Replace the existing `_translateGattTimeout` top-level function with a version that accepts `deviceId` and handles both typed platform exceptions. The simplest shape is to keep it top-level but take `deviceId` as the first parameter:

```dart
/// Translates internal platform-interface typed exceptions into the
/// public-facing [BlueyException] hierarchy:
///   * [platform.GattOperationTimeoutException] → [GattTimeoutException]
///   * [platform.GattOperationDisconnectedException] →
///     [DisconnectedException] with [DisconnectReason.linkLoss]
///
/// The platform-interface types stay internal to [LifecycleClient] (which
/// catches them directly for liveness-counter logic). Every other caller
/// sees a [BlueyException] so pattern-matching against the sealed
/// hierarchy is exhaustive.
Future<T> _translateGattPlatformError<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on platform.GattOperationTimeoutException {
    throw GattTimeoutException(operation);
  } on platform.GattOperationDisconnectedException {
    throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
  }
}
```

Thread `deviceId` through to the remote subclasses. Modify the `BlueyRemoteCharacteristic` constructor to accept and store `UUID deviceId`:

```dart
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final UUID _deviceId;
  // ...existing fields...

  BlueyRemoteCharacteristic({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
    required this.properties,
    required this.descriptors,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId;
```

Same treatment for `BlueyRemoteDescriptor`.

Update `_mapCharacteristic` / `_mapDescriptor` (the DTO mappers in `BlueyConnection`) to pass `deviceId` when constructing these subclasses. Replace the existing calls with the `deviceId: deviceId,` extra field.

Update every call site in `BlueyConnection`, `BlueyRemoteCharacteristic`, `BlueyRemoteDescriptor`:
- `_translateGattTimeout(operation, fn)` → `_translateGattPlatformError(deviceId, operation, fn)` (inside `BlueyConnection` — `deviceId` is the field)
- Inside `BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor`, use `_deviceId`:
  `_translateGattPlatformError(_deviceId, operation, fn)`

- [ ] **Step 3: Run all bluey tests — expect some existing tests to fail if they construct these subclasses without `deviceId`**

```
cd bluey && flutter test
```

If existing tests fail at construction, update them to pass `deviceId: testDeviceId` (use an arbitrary UUID or the existing connection's `deviceId`). Most tests that use `BlueyConnection` directly should not need changes because the mapping happens inside `BlueyConnection._mapCharacteristic`.

Expected after fixes: all 552 existing tests PASS.

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart
git commit -m "$(cat <<'EOF'
refactor(bluey): translate GattOperationDisconnectedException to DisconnectedException

BlueyConnection's translation helper (renamed
_translateGattTimeout → _translateGattPlatformError) now handles the
second typed platform exception, mapping it to the existing sealed
DisconnectedException with DisconnectReason.linkLoss.

BlueyRemoteCharacteristic and BlueyRemoteDescriptor now carry the
connection's deviceId so they can construct the right DisconnectedException
when the platform layer reports a mid-op link loss.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Add `simulateWriteDisconnected` to fake + behavioral tests

**Files:**
- Modify: `bluey/test/fakes/fake_platform.dart`
- Modify: `bluey/test/connection/bluey_connection_timeout_test.dart`

- [ ] **Step 1: Write failing behavioral tests**

Append three new tests inside the existing `group('BlueyConnection timeout translation', ...)` block in `bluey/test/connection/bluey_connection_timeout_test.dart`. Find the closing `});` of that group and insert immediately before:

```dart
    test(
      'writeCharacteristic rewraps platform disconnect into DisconnectedException',
      () async {
        fakePlatform.simulateWriteDisconnected = true;

        final char = connection.service(TestUuids.serviceA)
            .characteristic(TestUuids.charA);

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<DisconnectedException>()),
        );

        // Verify the platform-interface type does NOT leak
        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isNot(isA<platform.GattOperationDisconnectedException>())),
        );

        fakePlatform.simulateWriteDisconnected = false;
      },
    );

    test(
      'DisconnectedException is also a BlueyException (sealed-hierarchy match)',
      () async {
        fakePlatform.simulateWriteDisconnected = true;

        final char = connection.service(TestUuids.serviceA)
            .characteristic(TestUuids.charA);

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<BlueyException>()),
        );

        fakePlatform.simulateWriteDisconnected = false;
      },
    );

    test(
      'DisconnectedException carries deviceId and DisconnectReason.linkLoss',
      () async {
        fakePlatform.simulateWriteDisconnected = true;

        final char = connection.service(TestUuids.serviceA)
            .characteristic(TestUuids.charA);

        try {
          await char.write(Uint8List.fromList([0x01]));
          fail('Expected DisconnectedException');
        } on DisconnectedException catch (e) {
          expect(e.deviceId, equals(TestDeviceIds.server));
          expect(e.reason, equals(DisconnectReason.linkLoss));
        }

        fakePlatform.simulateWriteDisconnected = false;
      },
    );
```

Make sure the file imports include `platform` as the alias for `bluey_platform_interface`; if not present, add the import. Verify `TestDeviceIds.server` and `TestUuids.serviceA`/`charA` exist (they're used in the existing tests in this file — reuse whatever constants those tests use).

- [ ] **Step 2: Run tests to confirm they fail**

```
cd bluey && flutter test test/connection/bluey_connection_timeout_test.dart \
  --name "rewraps platform disconnect"
```

Expected: FAIL — `FakeBlueyPlatform` doesn't have `simulateWriteDisconnected` yet.

- [ ] **Step 3: Add `simulateWriteDisconnected` to the fake**

Open `bluey/test/fakes/fake_platform.dart`. Find the `simulateWriteTimeout` field (added in Phase 1) and add the sibling directly below:

```dart
  /// When true, writeCharacteristic calls throw a
  /// [GattOperationTimeoutException] to simulate a remote peer that stopped
  /// acknowledging writes.
  bool simulateWriteTimeout = false;

  /// When true, writeCharacteristic calls throw a
  /// [GattOperationDisconnectedException] to simulate a mid-op link loss.
  /// Distinct from [simulateWriteTimeout] and [simulateWriteFailure].
  bool simulateWriteDisconnected = false;
```

Find the `writeCharacteristic` override. The timeout branch is already at the top of the body. Add the disconnect branch between it and the generic failure branch:

```dart
  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    if (simulateWriteTimeout) {
      throw const GattOperationTimeoutException('writeCharacteristic');
    }
    if (simulateWriteDisconnected) {
      throw const GattOperationDisconnectedException('writeCharacteristic');
    }
    if (simulateWriteFailure) {
      throw Exception('Write failed: server unreachable');
    }
    // ...existing tail unchanged...
```

- [ ] **Step 4: Run the tests — expect pass**

```
cd bluey && flutter test test/connection/bluey_connection_timeout_test.dart
```

Expected: all tests PASS (including 3 new disconnect tests).

- [ ] **Step 5: Run the whole bluey suite**

```
cd bluey && flutter test
```

Expected: all 555+ tests PASS (was 552, +3 new).

- [ ] **Step 6: Commit**

```bash
git add bluey/test/fakes/fake_platform.dart \
        bluey/test/connection/bluey_connection_timeout_test.dart
git commit -m "$(cat <<'EOF'
test(bluey): simulate disconnect mid-write + public API rewrap tests

FakeBlueyPlatform.simulateWriteDisconnected throws the typed platform
exception when provoked. New BlueyConnection tests verify that
RemoteCharacteristic.write() rewraps it into DisconnectedException
with deviceId + DisconnectReason.linkLoss, that the platform-interface
type does not leak to public callers, and that the sealed-hierarchy
pattern-match works.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Document the operation queue in ANDROID_BLE_NOTES.md

**Files:**
- Modify: `bluey_android/ANDROID_BLE_NOTES.md`

- [ ] **Step 1: Append a new section**

Open `bluey_android/ANDROID_BLE_NOTES.md`. Append to the end of the file (after the existing sections):

```markdown

## GATT Operation Queue

Android's `BluetoothGatt` API enforces a strict **one-operation-in-flight** rule per connection. Calling `gatt.writeCharacteristic()` while another op is outstanding returns `false` synchronously and no `BluetoothGattCallback` fires for the rejected call. Concurrent GATT ops from application code (e.g. user write + lifecycle heartbeat + iOS Service Changed re-discovery) race unless the plugin serializes them.

**Solution (Phase 2a, 2026-04-21):** `ConnectionManager` owns one `GattOpQueue` instance per connection, keyed by `connectionId`. Every GATT op — read/write characteristic, read/write descriptor, discoverServices, requestMtu, readRssi, setNotification's CCCD write — is constructed as a `GattOp` (sealed class, Command pattern) and enqueued. The queue:

- Executes ops in strict FIFO order; at most one op in flight at a time per connection
- Per-op timeout via `handler.postDelayed` (values sourced from `ConnectionManager`'s existing timeout config)
- Drain-on-disconnect: `onConnectionStateChange(STATE_DISCONNECTED)` fires `queue.drainAll(FlutterError("gatt-disconnected", ...))` so pending callbacks resolve promptly instead of dangling until `cleanup()`

### Threading model

The queue is **not thread-safe**. All state mutation happens on the main thread. `BluetoothGattCallback` methods fire on Binder IPC threads; every callback override in `ConnectionManager` posts its `queue.onComplete(...)` / `queue.drainAll(...)` invocation via `handler.post { ... }` before touching the queue. User-initiated `enqueue` calls arrive on the Pigeon dispatcher thread (main). Timeout Runnables fire on the Handler's looper (main). Net result: the queue sees a single-threaded access pattern and needs no locks.

### What is NOT queued

- **Incoming notifications (`onCharacteristicChanged`).** Pure arrivals; they don't occupy the single-op slot at the GATT layer and must not be delayed behind user-initiated ops.
- **Connect / disconnect (`BluetoothDevice.connectGatt`, `BluetoothGatt.disconnect`).** Connection-level, not GATT.
- **Bonding (`BluetoothDevice.createBond`).** Separate Android API; does not go through `BluetoothGatt`.
- **The synchronous `gatt.setCharacteristicNotification()` call inside `setNotification`.** Purely local; doesn't hit the wire. Runs inline in `ConnectionManager.setNotification` before the CCCD descriptor write is enqueued.
- **Unsolicited `BluetoothGattCallback` events (`onConnectionStateChange`, `onServiceChanged`, `onMtuChanged` when initiated by the peer).** Not responses to our ops.

### Cross-connection concurrency

The single-op rule is **per `BluetoothGatt` instance**, not global. Two connections may process GATT ops concurrently at the HCI / link-layer level. `ConnectionManager.queues: Map<String, GattOpQueue>` assigns one queue per connection; concurrent connections' queues do not share state or interfere.

### Limitations (Phase 2a)

- **Write-without-response is serialized.** The link layer actually permits many write-without-response packets back-to-back via the credit flow-control system. Phase 2a serializes them anyway for simplicity; Phase 2c revisits this for burst-throughput workloads.
- **Discovery / MTU are queued as regular ops.** On some Android versions the OS briefly serializes these across connections at a lower level; our per-connection queue does not coordinate with the OS-level serialization, which is fine because the OS handles it transparently via the callbacks we're already awaiting.
```

- [ ] **Step 2: Commit**

```bash
git add bluey_android/ANDROID_BLE_NOTES.md
git commit -m "$(cat <<'EOF'
docs(bluey_android): document GATT operation queue (Phase 2a)

Records the single-op-in-flight constraint, our serialization
strategy, threading model, what's NOT queued, and Phase 2a's
deferred items (write-without-response pipelining).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Post-plan verification

After Task 10, the feature branch should have 10 commits (one per task except Task 6, which produced none). Run the full test matrix + `flutter analyze` to confirm nothing regressed:

```
cd bluey_platform_interface && flutter test      # Expect: all pass
cd bluey && flutter test                          # Expect: all pass (555+)
cd bluey_android && flutter test                  # Expect: all pass (62+)
cd bluey_android/android && ./gradlew test        # Expect: all pass (new queue + integration tests)
cd bluey_ios && flutter test                      # Expect: all pass (81+)
flutter analyze                                    # Expect: only pre-existing warnings
```

Then on-device manual verification (same repro as Phase 1):
1. iOS advertising as server, Android as client.
2. Android scan + connect + subscribe + receive notifications + read.
3. Confirm: no "Failed to read from characteristic" / "Failed to write characteristic" messages in Android logs. If any appear, the queue is being bypassed somewhere and Task 5 needs revisit.
