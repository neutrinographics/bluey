# I020 + I021 Android GATT Server Dart-Mediated Responses — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Android's GATT server wait for the Dart-side handler to decide read-response values and write-response statuses, instead of auto-responding on the binder thread. Brings Android to parity with iOS's existing pending-request behavior.

**Architecture:** Introduce a pure-Kotlin `PendingRequestRegistry<T>` guarded by `synchronized`. Stash `PendingRead` / `PendingWrite` entries on binder-thread callbacks; pop + `sendResponse` on main thread when Dart calls `respondToRead` / `respondToWrite`. Drain per-central on disconnect, drain all on cleanup. No Pigeon, no platform-interface, no domain, no iOS change.

**Tech Stack:** Kotlin 1.9, Android BLE (`BluetoothGattServer`), JUnit 4.13 + mockk 1.13 for Kotlin tests, flutter_test + mocktail for Dart adapter tests.

**Spec:** [`docs/superpowers/specs/2026-04-23-i020-i021-android-server-respond-design.md`](../specs/2026-04-23-i020-i021-android-server-respond-design.md).

**Working directory for all commands below:** `/Users/joel/git/neutrinographics/bluey`.

---

## File Structure

| File | Role |
|---|---|
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt` | **New.** Registry class + `PendingRead` + `PendingWrite` + `GattStatusDto.toAndroidStatus()` extension |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` | **Modify.** Callbacks stash; respond methods pop + sendResponse; disconnect drains; cleanup clears |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt` | **Modify.** Add `NoPendingRequest` case |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt` | **Modify.** Extend `toServerFlutterError` arm |
| `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/PendingRequestRegistryTest.kt` | **New.** Registry unit tests (pure JUnit) |
| `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattStatusMappingTest.kt` | **New.** `toAndroidStatus` extension tests |
| `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt` | **Modify.** Add `NoPendingRequest` server-error test |
| `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt` | **Modify.** Add stash/pop/drain/status-mapping tests |
| `bluey_android/test/android_server_test.dart` | **Modify.** Add NoPendingRequest propagation test |
| `docs/backlog/I020-gatt-server-auto-respond-characteristic-write.md` | **Modify.** Mark fixed |
| `docs/backlog/I021-gatt-server-auto-respond-characteristic-read.md` | **Modify.** Mark fixed |

Decision: `GattStatusDto.toAndroidStatus()` goes in the same file as `PendingRequestRegistry`. Android has no `Messages.x.kt` convention — the mapping is tiny, internal to this subsystem, and shares its audience (the server response path). Bundling keeps the fix in one discoverable place.

---

## Task 1: Add `NoPendingRequest` error case + server-side error mapping

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt`
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`
- Test: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt`

- [ ] **Step 1: Write the failing test**

Append to `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt`, inside the `class ErrorsTest { ... }` body, near the existing `CentralNotFound` server test (around line 83):

```kotlin
    @Test
    fun `NoPendingRequest to gatt-status-failed 0x0A (server)`() {
        val e = BlueyAndroidError.NoPendingRequest(42L).toServerFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0A, e.details)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.ErrorsTest.NoPendingRequest to gatt-status-failed 0x0A (server)" 2>&1 | tail -20
```

Expected: compilation FAILS — `Unresolved reference: NoPendingRequest`.

- [ ] **Step 3: Add the error case**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt`, add under the existing `// --- Server-side request path → gatt-status-failed(0x0A) ---` section, after `CentralNotFound`:

```kotlin
    data class NoPendingRequest(val id: Long) :
        BlueyAndroidError("No pending request for id: $id")
```

- [ ] **Step 4: Extend the server-error mapping**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`, locate the existing `toServerFlutterError()` function and extend the `CharacteristicNotFound, CentralNotFound ->` arm (around line 49-51):

```kotlin
    is BlueyAndroidError.CharacteristicNotFound,
    is BlueyAndroidError.CentralNotFound,
    is BlueyAndroidError.NoPendingRequest ->
        FlutterError("gatt-status-failed", message, 0x0A)
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.ErrorsTest" 2>&1 | tail -10
```

Expected: all ErrorsTest tests PASS (including the new one).

- [ ] **Step 6: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt \
        bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt
git commit -m "$(cat <<'EOF'
feat(android): add NoPendingRequest error case for server response path

Maps to gatt-status-failed(0x0A) via toServerFlutterError, same
category as CharacteristicNotFound and CentralNotFound. Will be
raised by the upcoming pending-request scaffolding when Dart responds
to an id that has been drained, superseded, or never existed.

Part of I020 + I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `PendingRequestRegistry` + `PendingRead` + `PendingWrite` + `toAndroidStatus` extension

**Files:**
- Create: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt`
- Create: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/PendingRequestRegistryTest.kt`
- Create: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattStatusMappingTest.kt`

- [ ] **Step 1: Write failing registry tests**

Create `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/PendingRequestRegistryTest.kt`:

```kotlin
package com.neutrinographics.bluey

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class PendingRequestRegistryTest {

    @Test
    fun `put then pop returns the entry`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "a")
        assertEquals("a", registry.pop(1L))
    }

    @Test
    fun `pop returns null for unknown id`() {
        val registry = PendingRequestRegistry<String>()
        assertNull(registry.pop(99L))
    }

    @Test
    fun `pop twice returns null the second time`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "a")
        assertEquals("a", registry.pop(1L))
        assertNull(registry.pop(1L))
    }

    @Test
    fun `put with duplicate id overwrites`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "first")
        registry.put(1L, "second")
        assertEquals("second", registry.pop(1L))
    }

    @Test
    fun `drainWhere removes and returns matching entries`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "keep")
        registry.put(2L, "drain")
        registry.put(3L, "drain")
        val drained = registry.drainWhere { it == "drain" }
        assertEquals(2, drained.size)
        assertTrue(drained.containsAll(listOf("drain", "drain")))
    }

    @Test
    fun `drainWhere leaves non-matching entries in place`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "keep")
        registry.put(2L, "drain")
        registry.drainWhere { it == "drain" }
        assertEquals("keep", registry.pop(1L))
        assertNull(registry.pop(2L))
    }

    @Test
    fun `clear returns all entries and empties the registry`() {
        val registry = PendingRequestRegistry<String>()
        registry.put(1L, "a")
        registry.put(2L, "b")
        val cleared = registry.clear()
        assertEquals(2, cleared.size)
        assertTrue(cleared.containsAll(listOf("a", "b")))
        assertEquals(0, registry.size)
    }

    @Test
    fun `size reflects live entries`() {
        val registry = PendingRequestRegistry<String>()
        assertEquals(0, registry.size)
        registry.put(1L, "a")
        assertEquals(1, registry.size)
        registry.put(2L, "b")
        assertEquals(2, registry.size)
        registry.pop(1L)
        assertEquals(1, registry.size)
    }

    @Test
    fun `concurrent put and pop across many threads does not corrupt state`() {
        val registry = PendingRequestRegistry<Int>()
        val threadCount = 16
        val opsPerThread = 500
        val executor = java.util.concurrent.Executors.newFixedThreadPool(threadCount)
        val startLatch = java.util.concurrent.CountDownLatch(1)
        val doneLatch = java.util.concurrent.CountDownLatch(threadCount)

        repeat(threadCount) { threadIdx ->
            executor.submit {
                startLatch.await()
                val base = threadIdx.toLong() * opsPerThread
                // Each thread puts and pops its own disjoint id range
                for (i in 0 until opsPerThread) {
                    registry.put(base + i, threadIdx * 1000 + i)
                }
                for (i in 0 until opsPerThread) {
                    val v = registry.pop(base + i)
                    assertEquals(threadIdx * 1000 + i, v)
                }
                doneLatch.countDown()
            }
        }

        startLatch.countDown()
        assertTrue(doneLatch.await(10, java.util.concurrent.TimeUnit.SECONDS))
        executor.shutdown()
        assertEquals(0, registry.size)
    }
}
```

- [ ] **Step 2: Run registry tests — verify they fail**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.PendingRequestRegistryTest" 2>&1 | tail -10
```

Expected: compilation FAILS — `Unresolved reference: PendingRequestRegistry`.

- [ ] **Step 3: Write failing status-mapping tests**

Create `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattStatusMappingTest.kt`:

```kotlin
package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import org.junit.Assert.assertEquals
import org.junit.Test

class GattStatusMappingTest {

    @Test
    fun `SUCCESS maps to GATT_SUCCESS`() {
        assertEquals(BluetoothGatt.GATT_SUCCESS, GattStatusDto.SUCCESS.toAndroidStatus())
    }

    @Test
    fun `READ_NOT_PERMITTED maps to GATT_READ_NOT_PERMITTED`() {
        assertEquals(
            BluetoothGatt.GATT_READ_NOT_PERMITTED,
            GattStatusDto.READ_NOT_PERMITTED.toAndroidStatus()
        )
    }

    @Test
    fun `WRITE_NOT_PERMITTED maps to GATT_WRITE_NOT_PERMITTED`() {
        assertEquals(
            BluetoothGatt.GATT_WRITE_NOT_PERMITTED,
            GattStatusDto.WRITE_NOT_PERMITTED.toAndroidStatus()
        )
    }

    @Test
    fun `INVALID_OFFSET maps to GATT_INVALID_OFFSET`() {
        assertEquals(
            BluetoothGatt.GATT_INVALID_OFFSET,
            GattStatusDto.INVALID_OFFSET.toAndroidStatus()
        )
    }

    @Test
    fun `INVALID_ATTRIBUTE_LENGTH maps to GATT_INVALID_ATTRIBUTE_LENGTH`() {
        assertEquals(
            BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH,
            GattStatusDto.INVALID_ATTRIBUTE_LENGTH.toAndroidStatus()
        )
    }

    @Test
    fun `INSUFFICIENT_AUTHENTICATION maps to GATT_INSUFFICIENT_AUTHENTICATION`() {
        assertEquals(
            BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION,
            GattStatusDto.INSUFFICIENT_AUTHENTICATION.toAndroidStatus()
        )
    }

    @Test
    fun `INSUFFICIENT_ENCRYPTION maps to GATT_INSUFFICIENT_ENCRYPTION`() {
        assertEquals(
            BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION,
            GattStatusDto.INSUFFICIENT_ENCRYPTION.toAndroidStatus()
        )
    }

    @Test
    fun `REQUEST_NOT_SUPPORTED maps to GATT_REQUEST_NOT_SUPPORTED`() {
        assertEquals(
            BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
            GattStatusDto.REQUEST_NOT_SUPPORTED.toAndroidStatus()
        )
    }
}
```

- [ ] **Step 4: Run status-mapping tests — verify they fail**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattStatusMappingTest" 2>&1 | tail -10
```

Expected: compilation FAILS — `Unresolved reference: toAndroidStatus`.

- [ ] **Step 5: Create the registry + data classes + extension**

Create `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt`:

```kotlin
package com.neutrinographics.bluey

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt

/**
 * Thread-safe map of outstanding ATT requests awaiting a Dart-side response.
 *
 * Binder-thread callbacks [put] entries; main-thread Pigeon handlers [pop]
 * them when Dart calls respondTo{Read,Write}. [drainWhere] is called on
 * central disconnect; [clear] is called on server cleanup.
 *
 * All operations are guarded by [lock]. Collections returned by
 * [drainWhere] and [clear] are snapshots detached from internal state;
 * no live views escape the lock. See the thread-safety argument in the
 * design spec for the full invariant set.
 *
 * Predicates passed to [drainWhere] run under the lock — they MUST be
 * O(1) and non-reentrant (no calls back into this registry).
 */
internal class PendingRequestRegistry<T> {
    private val lock = Any()
    private val entries = HashMap<Long, T>()

    fun put(id: Long, entry: T) = synchronized(lock) {
        entries[id] = entry
    }

    fun pop(id: Long): T? = synchronized(lock) {
        entries.remove(id)
    }

    fun drainWhere(predicate: (T) -> Boolean): List<T> = synchronized(lock) {
        val matched = entries.filterValues(predicate)
        matched.keys.forEach { entries.remove(it) }
        matched.values.toList()
    }

    fun clear(): List<T> = synchronized(lock) {
        val all = entries.values.toList()
        entries.clear()
        all
    }

    val size: Int get() = synchronized(lock) { entries.size }
}

internal data class PendingRead(
    val device: BluetoothDevice,
    val requestId: Int,
    val offset: Int,
)

internal data class PendingWrite(
    val device: BluetoothDevice,
    val requestId: Int,
    val offset: Int,
    /**
     * Reserved for prepared-write flow (I050); unused in the current
     * response path since ATT write responses carry no payload.
     * MUST NOT be mutated after construction — the registry's
     * thread-safety argument assumes immutability of stored entries.
     */
    val value: ByteArray,
)

internal fun GattStatusDto.toAndroidStatus(): Int = when (this) {
    GattStatusDto.SUCCESS -> BluetoothGatt.GATT_SUCCESS
    GattStatusDto.READ_NOT_PERMITTED -> BluetoothGatt.GATT_READ_NOT_PERMITTED
    GattStatusDto.WRITE_NOT_PERMITTED -> BluetoothGatt.GATT_WRITE_NOT_PERMITTED
    GattStatusDto.INVALID_OFFSET -> BluetoothGatt.GATT_INVALID_OFFSET
    GattStatusDto.INVALID_ATTRIBUTE_LENGTH -> BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH
    GattStatusDto.INSUFFICIENT_AUTHENTICATION -> BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION
    GattStatusDto.INSUFFICIENT_ENCRYPTION -> BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION
    GattStatusDto.REQUEST_NOT_SUPPORTED -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.PendingRequestRegistryTest" --tests "com.neutrinographics.bluey.GattStatusMappingTest" 2>&1 | tail -15
```

Expected: all 17 tests PASS (9 registry + 8 status mapping).

- [ ] **Step 7: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/PendingRequestRegistryTest.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattStatusMappingTest.kt
git commit -m "$(cat <<'EOF'
feat(android): add PendingRequestRegistry + GattStatus mapping

Introduces the scaffolding for Dart-mediated GATT server responses:
- PendingRequestRegistry<T>: thread-safe, filter-then-remove atomic
- PendingRead / PendingWrite value objects
- GattStatusDto.toAndroidStatus() extension

No caller yet — GattServer wiring comes in the next commits.

Part of I020 + I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Rewire `onCharacteristicReadRequest` to stash instead of auto-responding

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:404-435`
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

- [ ] **Step 1: Write the failing test**

Append to the `class GattServerTest { ... }` body in `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`:

```kotlin
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest.onCharacteristicReadRequest does not call sendResponse" 2>&1 | tail -20
```

Expected: FAIL — `sendResponse` is called once (existing auto-respond behavior).

- [ ] **Step 3: Add the registry field and rewire the callback**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt`, add a new field in the private-fields block (near line 48-51, after the `subscriptions` map):

```kotlin
    // Pending ATT requests keyed by native Android requestId (cast to Long).
    // Populated on binder thread in onCharacteristic{Read,Write}Request;
    // drained on main thread in respondTo{Read,Write}Request, on central
    // disconnect, and on cleanup(). See PendingRequestRegistry for the
    // thread-safety argument.
    private val pendingReadRequests = PendingRequestRegistry<PendingRead>()
    private val pendingWriteRequests = PendingRequestRegistry<PendingWrite>()
```

Replace the existing `onCharacteristicReadRequest` body (currently `GattServer.kt:404-435`) with:

```kotlin
        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            Log.d("GattServer", "onCharacteristicReadRequest: device=${device.address} char=${characteristic.uuid} requestId=$requestId")

            // Stash pending entry BEFORE posting to Flutter so the main
            // thread can never see a respondToRead before the put has
            // happened. synchronized in the registry establishes
            // happens-before with the main-thread pop.
            pendingReadRequests.put(
                requestId.toLong(),
                PendingRead(device, requestId, offset)
            )

            val request = ReadRequestDto(
                requestId = requestId.toLong(),
                centralId = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                offset = offset.toLong()
            )
            // Must dispatch to main thread for Flutter platform channel.
            handler.post {
                flutterApi.onReadRequest(request) {}
            }
            // Intentionally NO sendResponse here — Dart's respondToRead
            // is the only code path that sends the response.
        }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS (the new test PLUS the existing `onCharacteristicReadRequest notifies Flutter` test should both pass; the pre-existing one doesn't assert anything about `sendResponse`).

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
feat(android): stash read requests instead of auto-responding

onCharacteristicReadRequest now stores the device + offset in the
pendingReadRequests registry before posting to Flutter, and no longer
calls sendResponse from the binder thread. Dart's respondToRead will
wire up in the next commit.

Part of I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Implement `respondToReadRequest` — happy path

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:188-205`
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

- [ ] **Step 1: Write the failing test**

Append to the `class GattServerTest { ... }` body:

```kotlin
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest.respondToReadRequest with known id calls sendResponse with Dart-supplied value and status" 2>&1 | tail -20
```

Expected: FAIL — `sendResponse` is never called because `respondToReadRequest` is a no-op today.

- [ ] **Step 3: Implement `respondToReadRequest`**

Replace the existing `respondToReadRequest` body (currently `GattServer.kt:188-205`) with:

```kotlin
    fun respondToReadRequest(
        requestId: Long,
        status: GattStatusDto,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(BlueyAndroidError.NotInitialized("GattServer")))
            return
        }

        val pending = pendingReadRequests.pop(requestId)
        if (pending == null) {
            callback(Result.failure(BlueyAndroidError.NoPendingRequest(requestId)))
            return
        }

        try {
            server.sendResponse(
                pending.device,
                pending.requestId,
                status.toAndroidStatus(),
                pending.offset,
                value ?: ByteArray(0)
            )
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
feat(android): implement respondToReadRequest happy path

Pops the pending PendingRead, calls BluetoothGattServer.sendResponse
with the stashed device + offset and the Dart-supplied status + value.
Error paths (unknown id, status mapping coverage, null value) in
following commits.

Part of I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Cover `respondToReadRequest` edge cases — unknown id, null value, status mapping

**Files:**
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

All tests here exercise code already written in Task 4. No implementation changes — this task is pure test coverage.

- [ ] **Step 1: Add edge-case tests**

Append to the `class GattServerTest { ... }` body:

```kotlin
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
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
test(android): cover respondToReadRequest edge cases

Adds tests for: unknown requestId → NoPendingRequest; null value →
empty ByteArray on the wire; every GattStatusDto value maps to the
correct BluetoothGatt.GATT_* constant.

Part of I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Rewire `onCharacteristicWriteRequest` (responseNeeded=true, preparedWrite=false)

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:437-474`
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

- [ ] **Step 1: Write the failing test**

Append to the `class GattServerTest { ... }` body:

```kotlin
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest.onCharacteristicWriteRequest (responseNeeded, not prepared) stashes and does not call sendResponse" 2>&1 | tail -20
```

Expected: FAIL — `sendResponse` is still called by today's auto-respond.

- [ ] **Step 3: Rewire `onCharacteristicWriteRequest`**

Replace the existing `onCharacteristicWriteRequest` body (currently `GattServer.kt:437-474`) with:

```kotlin
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            Log.d("GattServer", "onCharacteristicWriteRequest: device=${device.address} char=${characteristic.uuid} requestId=$requestId preparedWrite=$preparedWrite responseNeeded=$responseNeeded")

            val request = WriteRequestDto(
                requestId = requestId.toLong(),
                centralId = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                value = value,
                offset = offset.toLong(),
                responseNeeded = responseNeeded
            )

            // Stash only for the "simple write with response" path. The
            // responseNeeded=false path has no response to send, and the
            // preparedWrite=true path keeps its existing auto-respond echo
            // behavior (owned by I050).
            if (responseNeeded && !preparedWrite) {
                pendingWriteRequests.put(
                    requestId.toLong(),
                    PendingWrite(device, requestId, offset, value)
                )
            }

            handler.post {
                flutterApi.onWriteRequest(request) {}
            }

            // Preserved auto-respond path for prepared writes (I050).
            if (responseNeeded && preparedWrite) {
                try {
                    gattServer?.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value
                    )
                } catch (e: SecurityException) {
                    // Permission revoked.
                }
            }
        }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
feat(android): stash write requests instead of auto-responding

onCharacteristicWriteRequest now stashes PendingWrite entries for the
simple (responseNeeded && !preparedWrite) path and no longer calls
sendResponse from the binder thread for those. The responseNeeded=false
and preparedWrite=true paths are preserved exactly.

Part of I020.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Implement `respondToWriteRequest` — happy path + unknown id

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:207-219`
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

- [ ] **Step 1: Write the failing tests**

Append to the `class GattServerTest { ... }` body:

```kotlin
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest.respondToWriteRequest with known id calls sendResponse with null payload" --tests "com.neutrinographics.bluey.GattServerTest.respondToWriteRequest with unknown id fails with NoPendingRequest" 2>&1 | tail -20
```

Expected: FAIL — `respondToWriteRequest` is a no-op today.

- [ ] **Step 3: Implement `respondToWriteRequest`**

Replace the existing `respondToWriteRequest` body (currently `GattServer.kt:207-219`) with:

```kotlin
    fun respondToWriteRequest(
        requestId: Long,
        status: GattStatusDto,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(BlueyAndroidError.NotInitialized("GattServer")))
            return
        }

        val pending = pendingWriteRequests.pop(requestId)
        if (pending == null) {
            callback(Result.failure(BlueyAndroidError.NoPendingRequest(requestId)))
            return
        }

        try {
            // ATT Write Response PDU carries no payload — pass null.
            server.sendResponse(
                pending.device,
                pending.requestId,
                status.toAndroidStatus(),
                pending.offset,
                null
            )
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
feat(android): implement respondToWriteRequest

Pops the pending PendingWrite, calls BluetoothGattServer.sendResponse
with null value (write responses carry no payload per ATT spec), and
fails with NoPendingRequest for unknown ids.

Part of I020.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Verify preservation of `responseNeeded=false` and `preparedWrite=true` paths

**Files:**
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

These tests lock in the non-regression guarantee for the two paths we explicitly preserved. No code change expected.

- [ ] **Step 1: Write the tests**

Append to the `class GattServerTest { ... }` body:

```kotlin
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
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS (no implementation change needed — Task 6's changes already handle both paths correctly).

- [ ] **Step 3: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
test(android): lock in responseNeeded=false + preparedWrite=true paths

Non-regression tests for the two write paths we explicitly preserved:
- responseNeeded=false: no stash, no sendResponse, Flutter still notified
- preparedWrite=true: auto-respond echo preserved for I050

Part of I020.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Disconnect drain — remove pending requests for the disconnected central

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:374-387`
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

- [ ] **Step 1: Write the failing test**

Append to the `class GattServerTest { ... }` body:

```kotlin
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest.onConnectionStateChange(DISCONNECTED) drains pending requests for that central only" 2>&1 | tail -20
```

Expected: FAIL — A's entries are still in the registry, so `respondToReadRequest(1L)` / `respondToWriteRequest(2L)` succeed when they should fail.

- [ ] **Step 3: Add the drain**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt`, locate the `BluetoothProfile.STATE_DISCONNECTED ->` branch inside `onConnectionStateChange` (currently around `GattServer.kt:374-386`) and insert the drain *before* the `handler.post`:

```kotlin
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d("GattServer", "Central disconnected: $deviceId")
                    connectedCentrals.remove(deviceId)
                    centralMtus.remove(deviceId)

                    // Remove from all subscriptions.
                    subscriptions.values.forEach { it.remove(deviceId) }

                    // Drain pending ATT requests for this central — no point
                    // keeping them; sendResponse would fail once the device is gone.
                    // Runs synchronously inside the binder callback so the main
                    // thread cannot observe a partial disconnect state.
                    val drainedReads = pendingReadRequests.drainWhere { it.device.address == deviceId }
                    val drainedWrites = pendingWriteRequests.drainWhere { it.device.address == deviceId }
                    if (drainedReads.isNotEmpty() || drainedWrites.isNotEmpty()) {
                        Log.d(
                            "GattServer",
                            "Drained ${drainedReads.size} read(s) and ${drainedWrites.size} write(s) on disconnect of $deviceId"
                        )
                    }

                    // Must dispatch to main thread for Flutter platform channel.
                    handler.post {
                        flutterApi.onCentralDisconnected(deviceId) {}
                    }
                }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
feat(android): drain pending server requests on central disconnect

When a central disconnects, drain its pending read and write requests
synchronously inside the binder callback (before posting to Flutter).
A subsequent Dart respondToRead/Write for the drained id now correctly
fails with NoPendingRequest. Other centrals' pending entries survive.

Part of I020 + I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Cleanup drain — empty both registries on `cleanup()`

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:242-274`
- Modify: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt`

- [ ] **Step 1: Write the failing test**

Append to the `class GattServerTest { ... }` body:

```kotlin
    @Test
    fun `cleanup() clears all pending requests`() {
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
        every { mockFlutterApi.onWriteRequest(any(), any()) } answers {
            secondArg<(Result<Unit>) -> Unit>().invoke(Result.success(Unit))
        }

        capturedCallback!!.onCharacteristicReadRequest(mockDevice, 1, 0, mockCharacteristic)
        capturedCallback!!.onCharacteristicWriteRequest(mockDevice, 2, mockCharacteristic, false, true, 0, byteArrayOf(0x01))

        gattServer.cleanup()

        // After cleanup the server ref is null — respond hits the NotInitialized check
        // BEFORE reaching the registry. Re-open the server to exercise the registry state.
        // Calling addService again re-opens the server via ensureServerOpen.
        gattServer.addService(service) {}

        var readResult: Result<Unit>? = null
        gattServer.respondToReadRequest(1L, GattStatusDto.SUCCESS, byteArrayOf()) { readResult = it }
        assertTrue(readResult?.exceptionOrNull() is BlueyAndroidError.NoPendingRequest)

        var writeResult: Result<Unit>? = null
        gattServer.respondToWriteRequest(2L, GattStatusDto.SUCCESS) { writeResult = it }
        assertTrue(writeResult?.exceptionOrNull() is BlueyAndroidError.NoPendingRequest)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest.cleanup() clears all pending requests" 2>&1 | tail -20
```

Expected: FAIL — after re-opening, ids 1 and 2 are still in the registry (cleanup doesn't touch it today).

- [ ] **Step 3: Add the clear calls to `cleanup()`**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt`, locate `cleanup()` (currently `GattServer.kt:242-274`) and add the clear calls alongside the existing clears, just before the `pendingServiceCallback = null` line:

```kotlin
        gattServer = null
        connectedCentrals.clear()
        centralMtus.clear()
        subscriptions.clear()
        pendingReadRequests.clear()
        pendingWriteRequests.clear()
        pendingServiceCallback = null
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey_android/android && ./gradlew test --tests "com.neutrinographics.bluey.GattServerTest" 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "$(cat <<'EOF'
feat(android): clear pending request registries in GattServer.cleanup

Ensures that any ATT requests stashed before teardown don't survive
across a server re-open. Completes the drain surface for I020 + I021
alongside the per-central disconnect drain.

Part of I020 + I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Dart adapter — confirm `NoPendingRequest` surfaces as `GattStatusFailedException`

**Files:**
- Modify: `bluey_android/test/android_server_test.dart`

Context: when Kotlin throws `BlueyAndroidError.NoPendingRequest`, `toServerFlutterError` maps it to a `PlatformException` with code `gatt-status-failed` and details `0x0A`. The Dart adapter's existing error-translation path (`android_server.dart`) should already convert `PlatformException("gatt-status-failed")` to `GattStatusFailedException`. This task adds a regression test.

- [ ] **Step 1: Identify the existing error-translation path**

Read `bluey_android/lib/src/android_server.dart` to confirm which method performs `PlatformException → domain exception` translation. Expected: either a shared `_translateError` helper, or `try/catch` blocks on each host-API call.

```bash
cd /Users/joel/git/neutrinographics/bluey
grep -n "gatt-status-failed\|PlatformException\|GattStatusFailedException" bluey_android/lib/src/android_server.dart | head -20
```

Expected output: references to either `GattStatusFailedException` (if translation is explicit in `android_server.dart`) or an import of a shared translator from `bluey_platform_interface`.

If translation lives in `bluey_platform_interface`, the test still belongs in `bluey_android` since we're confirming the end-to-end translation *through* `AndroidServer.respondToReadRequest`.

- [ ] **Step 2: Write the failing test**

Append to the `group('respondToReadRequest', ...)` block in `bluey_android/test/android_server_test.dart`:

```dart
      test('propagates gatt-status-failed PlatformException as GattStatusFailedException',
          () async {
        when(() => mockHostApi.respondToReadRequest(any(), any(), any()))
            .thenThrow(PlatformException(
          code: 'gatt-status-failed',
          message: 'No pending request for id: 999',
          details: 0x0A,
        ));

        expect(
          () => server.respondToReadRequest(
              999, PlatformGattStatus.success, null),
          throwsA(isA<GattStatusFailedException>()),
        );
      });
```

Add required imports at the top of the file if not already present:

```dart
import 'package:flutter/services.dart' show PlatformException;
```

Check whether `GattStatusFailedException` is exported by `bluey_platform_interface.dart`:

```bash
grep -n "GattStatusFailedException" /Users/joel/git/neutrinographics/bluey/bluey_platform_interface/lib/bluey_platform_interface.dart /Users/joel/git/neutrinographics/bluey/bluey_platform_interface/lib/src/*.dart | head -5
```

Expected: the class exists in the platform-interface package and is already imported in `android_server_test.dart` via the existing `import 'package:bluey_platform_interface/bluey_platform_interface.dart';`. If not exported, add the import accordingly.

- [ ] **Step 3: Run the test**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test test/android_server_test.dart -p 2>&1 | tail -15
```

Expected outcomes (either is acceptable):

- **If translation is already in place:** test PASSES — no code change needed, this task becomes pure coverage. Proceed to Step 5.
- **If translation is NOT in place:** test FAILS because a raw `PlatformException` escapes. In that case, implement translation in `bluey_android/lib/src/android_server.dart`'s `respondToReadRequest` (and symmetrically `respondToWriteRequest`) by wrapping the host-API call in a `try/catch (PlatformException e)` that matches `e.code == 'gatt-status-failed'` and rethrows as `GattStatusFailedException(e.details as int? ?? 0)`. Re-run and expect PASS.

- [ ] **Step 4: If translation was missing, commit the adapter change**

Only if Step 3 required a code change in `android_server.dart`:

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/lib/src/android_server.dart
git commit -m "$(cat <<'EOF'
fix(android): translate gatt-status-failed PlatformException in server

respondToReadRequest and respondToWriteRequest now translate the
Pigeon gatt-status-failed code (raised by the new NoPendingRequest
error path) into the domain-level GattStatusFailedException.

Part of I020 + I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Commit the test**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/test/android_server_test.dart
git commit -m "$(cat <<'EOF'
test(android): confirm NoPendingRequest surfaces as domain exception

Regression test that a gatt-status-failed PlatformException from the
native layer reaches Dart callers as GattStatusFailedException.

Part of I020 + I021.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Full regression suite

**Files:** none (verification only).

- [ ] **Step 1: Run the full Android Kotlin test suite**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_android/android && ./gradlew test 2>&1 | tail -30
```

Expected: all tests PASS (all pre-existing + all new).

- [ ] **Step 2: Run the full Dart test suite across packages**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test 2>&1 | tail -20
cd /Users/joel/git/neutrinographics/bluey/bluey_platform_interface && flutter test 2>&1 | tail -20
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test 2>&1 | tail -20
```

Expected: all packages PASS — no regressions. Note in particular: the 543 domain-layer tests must keep passing (the domain contract is unchanged).

- [ ] **Step 3: Run the static analyzer**

```bash
cd /Users/joel/git/neutrinographics/bluey && flutter analyze 2>&1 | tail -20
```

Expected: no new warnings or errors in any of the modified files.

- [ ] **Step 4: No commit**

Verification task only — any failures here indicate a bug in an earlier task that must be fixed before proceeding.

---

## Task 13: Manual example-app verification

**Files:** none (manual verification per CLAUDE.md's UI-verification directive).

This task cannot be automated; it must be run by a developer with physical hardware or Android/iOS simulators+physical peer.

- [ ] **Step 1: Launch the example app on an Android device**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey/example && flutter run -d <android-device-id>
```

- [ ] **Step 2: Exercise the server-role flow with an iOS device as client**

On Android, start the server role. On a separate iOS device (or two different Android devices), run the example app in client mode and connect.

Using the in-app controls:
- Issue a read request from the client, observe Dart-side handler emitting a value, confirm the client receives that value (not an empty or stale value).
- Issue a write request with response required; observe Dart handler receiving the write and its `respondToWrite(success)` being accepted by the peer.
- Issue a write with explicit rejection from Dart (`respondToWrite(writeNotPermitted)`); confirm peer observes the rejection.

- [ ] **Step 3: Confirm the lifecycle heartbeat still functions**

With the client connected, leave the apps idle for 30+ seconds. Confirm the heartbeat/lifecycle reads and writes continue to flow (check the debug log for the lifecycle service's periodic activity and confirm the connection remains healthy).

- [ ] **Step 4: Run one stress-test probe**

If the stress test harness (see docs for `DelayAckCommand` / `DropNextCommand`) is available from the example app, run at least one `DelayAckCommand` probe to confirm Dart-mediated delay now actually delays the response on the wire (the test that was blocked on this fix).

- [ ] **Step 5: Document findings**

If all three scenarios pass, no action. If any scenario fails, file a new backlog entry describing the failure and do not proceed to Task 14 until the root cause is identified and this task is re-verified.

---

## Task 14: Mark I020 and I021 fixed in the backlog

**Files:**
- Modify: `docs/backlog/I020-gatt-server-auto-respond-characteristic-write.md`
- Modify: `docs/backlog/I021-gatt-server-auto-respond-characteristic-read.md`

- [ ] **Step 1: Capture the fix commit SHA**

```bash
cd /Users/joel/git/neutrinographics/bluey
git log --oneline -20 | head
```

Note the most recent `feat(android)` SHAs from Tasks 1-10. Use the *final* relevant commit SHA (Task 10's cleanup commit or the latest one) as the `fixed_in` value — or, if desired, the merge commit SHA after this branch lands on `main`. The placeholder `<fix-sha>` below should be replaced with that value.

- [ ] **Step 2: Update the I020 frontmatter**

In `docs/backlog/I020-gatt-server-auto-respond-characteristic-write.md`, change the YAML frontmatter:

```yaml
---
id: I020
title: GATT server auto-respond on characteristic write
category: no-op
severity: critical
platform: android
status: fixed
last_verified: 2026-04-23
fixed_in: <fix-sha>
historical_ref: BUGS-ANALYSIS-#7, BUGS-ANALYSIS-ANDROID-A4
---
```

- [ ] **Step 3: Update the I021 frontmatter**

In `docs/backlog/I021-gatt-server-auto-respond-characteristic-read.md`:

```yaml
---
id: I021
title: GATT server auto-respond on characteristic read
category: no-op
severity: critical
platform: android
status: fixed
last_verified: 2026-04-23
fixed_in: <fix-sha>
historical_ref: BUGS-ANALYSIS-#7
related: [I020]
---
```

- [ ] **Step 4: Move I020 and I021 entries to the "Fixed — verified in HEAD" table in the index**

In `docs/backlog/README.md`:

Remove the I020 and I021 rows from the "Open — Android GATT server stubs / no-ops" table (currently around lines 125-126).

Add two new rows to the "Fixed — verified in HEAD" table (currently around lines 170-175), preserving ID order:

```markdown
| [I020](I020-gatt-server-auto-respond-characteristic-write.md) | GATT server auto-respond on characteristic write | `<fix-sha>` |
| [I021](I021-gatt-server-auto-respond-characteristic-read.md) | GATT server auto-respond on characteristic read | `<fix-sha>` |
```

- [ ] **Step 5: Update the "Suggested order of attack" recommendation**

In `docs/backlog/README.md`, under "Suggested order of attack", strike through or remove the `1. **I020 + I021**` bullet (currently around line 63) since it's no longer the top-priority item. Promote the next entries up accordingly — or leave the list intact with a note that I020+I021 have been completed. Choose whichever fits the project's existing editorial convention for the file (the existing pattern is to remove, based on earlier backlog edits).

- [ ] **Step 6: Commit the backlog update**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add docs/backlog/I020-gatt-server-auto-respond-characteristic-write.md \
        docs/backlog/I021-gatt-server-auto-respond-characteristic-read.md \
        docs/backlog/README.md
git commit -m "$(cat <<'EOF'
doc(backlog): mark I020 + I021 fixed

Android GATT server now waits for Dart-side handlers to supply read
values and write responses via the new PendingRequestRegistry, matching
iOS behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Results

**Spec coverage audit:**

| Spec requirement | Plan task(s) |
|---|---|
| New `PendingRequestRegistry<T>` class with `put`/`pop`/`drainWhere`/`clear`/`size` | Task 2 |
| `PendingRead` / `PendingWrite` data classes | Task 2 |
| `GattStatusDto.toAndroidStatus()` extension mapping all 8 enum values | Task 2 (impl) + Task 5 (status-mapping table test) |
| `BlueyAndroidError.NoPendingRequest` case | Task 1 |
| `Errors.kt` server-error mapping extended | Task 1 |
| `onCharacteristicReadRequest` stashes, no `sendResponse` | Task 3 |
| `onCharacteristicWriteRequest` (responseNeeded, !preparedWrite) stashes | Task 6 |
| `responseNeeded=false` path preserved | Task 8 |
| `preparedWrite=true` path preserved (auto-respond echo) | Task 6 (impl) + Task 8 (regression test) |
| `respondToReadRequest` happy path with Dart-supplied value + status | Task 4 |
| `respondToReadRequest` with null value → empty ByteArray | Task 5 |
| `respondToReadRequest` with unknown id → `NoPendingRequest` | Task 5 |
| `respondToWriteRequest` with null value on wire | Task 7 |
| `respondToWriteRequest` with unknown id → `NoPendingRequest` | Task 7 |
| Disconnect drain per-central before posting to Flutter | Task 9 |
| `cleanup()` clears both registries | Task 10 |
| Registry concurrency stress test | Task 2 |
| Dart-side `NoPendingRequest` surfaces as `GattStatusFailedException` | Task 11 |
| Full regression + static analysis | Task 12 |
| Example-app manual verification | Task 13 |
| Backlog entries marked fixed | Task 14 |

Every spec requirement has a task. No gaps.

**Placeholder scan:** no TBD/TODO/"fill in details" markers. Every code block is complete. The `<fix-sha>` token in Task 14 is an explicit instruction to replace with the final SHA at the time of the backlog update, not a placeholder in the plan's content.

**Type consistency:** `PendingRequestRegistry`, `PendingRead`, `PendingWrite`, `NoPendingRequest`, `toAndroidStatus`, `pendingReadRequests`, `pendingWriteRequests` all consistently named across every task. Signatures match: `put(Long, T)`, `pop(Long): T?`, `drainWhere((T) -> Boolean): List<T>`, `clear(): List<T>`, `size: Int`. `BlueyAndroidError.NoPendingRequest(val id: Long)` — `id` field name and type consistent across definition (Task 1), test assertions (Tasks 5, 7, 8, 9, 10), and production use (Tasks 4, 7).

**Scope check:** the plan is focused on I020 + I021 only. No I022/I023/I012 work. Each task is a single TDD cycle of ≤5 file changes and a single commit.
