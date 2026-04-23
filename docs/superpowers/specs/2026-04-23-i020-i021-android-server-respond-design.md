# Android GATT Server: Dart-Mediated Read/Write Responses (I020 + I021)

**Status:** proposed
**Date:** 2026-04-23
**Scope:** `bluey_android` package only. No Pigeon schema change, no platform-interface change, no domain change, no iOS change.
**Backlog entries:** [I020](../../backlog/I020-gatt-server-auto-respond-characteristic-write.md), [I021](../../backlog/I021-gatt-server-auto-respond-characteristic-read.md).

## Problem

The Android GATT server (`GattServer.kt`) auto-responds to remote-central read and write requests on the binder thread, inside `onCharacteristicReadRequest` / `onCharacteristicWriteRequest`, before Flutter has a chance to see the request. The Dart-side `respondToReadRequest` / `respondToWriteRequest` are no-ops. Consequences:

- Dart-side `onReadRequest` handlers cannot supply a value — the central sees Android's cached `characteristic.value` (usually stale or empty).
- Dart-side `onWriteRequest` handlers cannot reject writes — every write gets `GATT_SUCCESS` regardless of what Dart decides.
- The stress-test `DelayAckCommand` and `DropNextCommand` probes cannot function on Android.
- The write response incorrectly appears to "echo" the value (cosmetic — Android discards the `value` param on write responses, but it implies wire behavior that doesn't exist).

iOS already does this correctly via `pendingReadRequests` / `pendingWriteRequests` maps in `PeripheralManagerImpl.swift`. This spec brings Android to parity.

## Non-goals

- **Descriptor-read responses (I022).** Adding a Dart API for descriptor reads is a separate design decision. Out of scope.
- **Notification-sent completion tracking (I023, I012).** Unrelated scaffolding.
- **Prepared writes / long writes (I050).** The `preparedWrite=true` path keeps its current auto-respond echo behavior. Prepared-write semantics are owned by I050.
- **Adding a `value` parameter to `respondToWrite`.** The ATT Write Response PDU (opcode `0x13`) carries *zero bytes of payload*. iOS's `peripheralManager.respond(to:withResult:)` doesn't even accept one. Android's `sendResponse` `value` parameter is silently discarded on the write-response path. Apps needing to return data after a write should use a notification or a follow-up read.
- **Internal server-side response timeout.** If Dart never responds, the request hangs until the central's ATT_TIMEOUT (~30s). Matches iOS.

## Decisions locked during brainstorming

1. **Scope:** I020 + I021 only. (I022 needs its own spec for a new Dart API.)
2. **Request-id key:** use the Android framework's native `requestId: Int` directly, cast to `Long` for the Pigeon boundary. No internal counter. (iOS needs one because `CBATTRequest` is a non-serializable pointer; Android doesn't.)
3. **Missing-id behavior:** `respondTo{Read,Write}Request` called with an unknown id fails with a new `BlueyAndroidError.NoPendingRequest(id)`, mapping to `gatt-status-failed(0x0A)` via `toServerFlutterError`. Matches iOS's `BlueyError.notFound.toServerPigeonError()`.
4. **Implementation shape:** extract a `PendingRequestRegistry<T>` helper class rather than inline the two maps in `GattServer`. Registry is pure Kotlin, thread-safe via `synchronized`, unit-testable without mockk.

## Architecture

All changes inside `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/`.

### New: `PendingRequestRegistry.kt`

```kotlin
internal class PendingRequestRegistry<T> {
    private val lock = Any()
    private val entries = HashMap<Long, T>()

    fun put(id: Long, entry: T) = synchronized(lock) {
        entries[id] = entry  // overwrite on duplicate; log warning
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
    /** Reserved for prepared-write flow (I050); unused in the current response path. MUST NOT be mutated. */
    val value: ByteArray,
)
```

### Modified: `GattServer.kt`

- Holds two registries: `private val pendingReadRequests = PendingRequestRegistry<PendingRead>()` and `private val pendingWriteRequests = PendingRequestRegistry<PendingWrite>()`.
- `onCharacteristicReadRequest`: `put` into registry → `handler.post { flutterApi.onReadRequest(...) }` → return. No `sendResponse` call on the binder thread.
- `onCharacteristicWriteRequest`: if `responseNeeded && !preparedWrite`, `put` into registry → `handler.post { ... }` → return. Other paths preserved.
- `respondToReadRequest(requestId, status, value, callback)`:
  - `gattServer == null` → `BlueyAndroidError.NotInitialized("GattServer")` (existing check).
  - `pendingReadRequests.pop(requestId)` returns null → `BlueyAndroidError.NoPendingRequest(requestId)`.
  - Else `gattServer.sendResponse(entry.device, entry.requestId, status.toAndroidStatus(), entry.offset, value ?: ByteArray(0))` → `callback(Result.success(Unit))`.
- `respondToWriteRequest(requestId, status, callback)`:
  - Same preconditions.
  - `gattServer.sendResponse(entry.device, entry.requestId, status.toAndroidStatus(), entry.offset, null)` — **explicitly null**, fixing the misleading-echo aspect of I020.
- `onConnectionStateChange(STATE_DISCONNECTED)`: drain *before* posting the disconnect notification to Flutter:
  ```kotlin
  pendingReadRequests.drainWhere { it.device.address == deviceId }
  pendingWriteRequests.drainWhere { it.device.address == deviceId }
  ```
- `cleanup()`: `pendingReadRequests.clear()` + `pendingWriteRequests.clear()` added to the existing cleanup block.

### Modified: `BlueyAndroidError.kt`

Add under the existing `// --- Server-side request path → gatt-status-failed(0x0A) ---` section:

```kotlin
data class NoPendingRequest(val id: Long) :
    BlueyAndroidError("No pending request for id: $id")
```

### Modified: `Errors.kt`

Extend `toServerFlutterError()`'s existing `gatt-status-failed(0x0A)` arm:

```kotlin
is BlueyAndroidError.CharacteristicNotFound,
is BlueyAndroidError.CentralNotFound,
is BlueyAndroidError.NoPendingRequest ->
    FlutterError("gatt-status-failed", message, 0x0A)
```

### Modified: `Messages.x.kt`

Add `GattStatusDto.toAndroidStatus()` extension mirroring iOS's `toCBATTError()`:

```kotlin
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

All branches hit documented `BluetoothGatt.GATT_*` constants — no magic numbers.

## Data flow

### Read path (happy path)

1. Framework: `onCharacteristicReadRequest(device, requestId, offset, characteristic)` on binder thread.
2. `GattServer`: `pendingReadRequests.put(requestId.toLong(), PendingRead(device, requestId, offset))`.
3. `GattServer`: `handler.post { flutterApi.onReadRequest(dto) {} }` with `dto.requestId = requestId.toLong()`.
4. Binder-thread handler returns. No `sendResponse`.
5. Dart domain layer receives `ReadRequest` on `server.readRequests` stream. Handler calls `server.respondToRead(requestId, status: success, value: bytes)`.
6. Pigeon dispatches on main thread → `GattServer.respondToReadRequest(requestId, status, value, callback)`.
7. `pendingReadRequests.pop(requestId)` returns the entry.
8. `gattServer.sendResponse(entry.device, entry.requestId, GATT_SUCCESS, entry.offset, bytes)`.
9. `callback(Result.success(Unit))`.

### Write path (responseNeeded=true, preparedWrite=false — happy path)

Symmetric with read. `sendResponse(... value = null)` — write responses carry no payload on the wire.

### Write paths left untouched

- **`responseNeeded=false`** (write without response): no `put`, no `sendResponse` (framework doesn't expect one). `flutterApi.onWriteRequest` still fires so Dart sees the write. Dart-side `respondToWrite` is a programming error for these ids and will fail with `NoPendingRequest`.
- **`preparedWrite=true`** (long write): current behavior preserved exactly — `flutterApi.onWriteRequest` fires AND binder-thread auto-responds with echoed `value`. Owned by I050. Note: Dart-side `respondToWrite` for a prepared-write id changes from silent no-op (today) to `NoPendingRequest` failure (after fix). This is an acceptable semantic sharpening — prepared writes were not functionally usable from Dart before (no way to control response) and I050 will redesign the flow properly.

### CCCD / descriptor writes

Untouched. `onDescriptorWriteRequest` has its own correct subscribe/unsubscribe + auto-respond logic.

### Disconnect drain

Runs synchronously inside `onConnectionStateChange(STATE_DISCONNECTED)`, *before* `handler.post` to Flutter:

```kotlin
pendingReadRequests.drainWhere { it.device.address == deviceId }
pendingWriteRequests.drainWhere { it.device.address == deviceId }
```

Drained entries are logged and discarded — `sendResponse` would fail anyway.

### Cleanup drain

`cleanup()` calls `clear()` on both registries alongside existing teardown.

## Thread-safety argument

**Thread split:**

- **Binder thread:** Android BLE callback invocations (`onCharacteristicReadRequest`, `onConnectionStateChange`, etc.). Does `registry.put`, `registry.drainWhere`, `handler.post`. Never calls `sendResponse`, never calls `flutterApi.*` directly.
- **Main thread:** Pigeon-dispatched methods (`respondToReadRequest`, `cleanup`, etc.). Does `registry.pop`, `registry.clear`, `sendResponse`.

**Why `HashMap + synchronized` is safe:**

1. Every access path goes through `synchronized(lock)`. No raw reads or writes escape.
2. The only iterator created is via Kotlin's `Map.filterValues`, which eagerly builds a *new* `LinkedHashMap` snapshot under the lock. We then iterate the copy's keys while removing from `entries` — no `ConcurrentModificationException`.
3. Returns are snapshots (`List` built under the lock) or primitives (`Int`). No live views escape.
4. `PendingRead` / `PendingWrite` are `data class`es with `val` fields — references immutable once constructed.
5. `PendingWrite.value: ByteArray` is JVM-mutable, but we never mutate it after stashing. Documented via field comment.
6. Predicates passed to `drainWhere` run under the lock — must be O(1) and non-reentrant. Our only call site passes `{ it.device.address == deviceId }`.

**Happens-before across threads:** the `synchronized` block in `put` releases the monitor; the `synchronized` block in `pop` acquires the same monitor. This establishes happens-before. Combined with `Handler.post`'s own happens-before edge, every `pop` on main is downstream of its corresponding `put` on binder.

**Disconnect race:** the drain runs synchronously inside the binder callback, before the `handler.post` notifying Flutter. If Dart races and calls `respondToXxx` between disconnect and drain, `pop` returns the entry and `sendResponse` fires (framework silently drops it — device is gone — which is the best we can do). If Dart calls after the drain, `pop` returns null → `NoPendingRequest`. Both outcomes are consistent.

**Alternative rejected:** `Collections.synchronizedMap` — synchronizes per-method but `drainWhere`'s filter-then-remove needs external locking anyway, yielding two sync layers and no win.

**Alternative rejected:** `ConcurrentHashMap` — `drainWhere` and `clear` need atomic filter-then-remove-and-return-list semantics that CHM doesn't provide without `compute`-style contortions.

**Alternative rejected:** post-everything-to-main-thread — opens a race where a fast Dart responder hits `respondToXxx` before the `put` has executed, causing spurious `NoPendingRequest`.

## Error handling

| Situation | Result |
|---|---|
| `respondTo{Read,Write}` with unknown `requestId` | `NoPendingRequest` → `gatt-status-failed(0x0A)` |
| `respondTo{Read,Write}` called twice for same id | Second call fails with `NoPendingRequest` (first call popped) |
| `respondTo{Read,Write}` after central-disconnect drain | `NoPendingRequest` |
| `respondTo{Read,Write}` after `cleanup()` | `BlueyAndroidError.NotInitialized("GattServer")` (existing check: `gattServer == null` after cleanup) |
| `sendResponse` returns `false` (framework dropped it) | Logged; callback returns success. We can't distinguish "succeeded" from "device gone" from the boolean, and a synthetic failure would surprise callers during normal disconnect races. Matches iOS's fire-and-forget response model. |
| `SecurityException` from `sendResponse` | Existing `PermissionDenied` translation path. |

**No retry logic.** No internal timeout. Both would diverge from iOS semantics.

## Testing strategy

TDD order — each bullet is a distinct red-green cycle.

### Layer 1: `PendingRequestRegistryTest.kt` (new, pure JUnit)

1. `put then pop returns the entry`
2. `pop returns null for unknown id`
3. `pop twice returns null the second time`
4. `put with duplicate id overwrites`
5. `drainWhere removes and returns matching entries`
6. `drainWhere leaves non-matching entries in place`
7. `clear returns all entries and empties the registry`
8. `size reflects live entries`
9. `concurrent put/pop from many threads does not corrupt state` (stress test with `CountDownLatch` + `ExecutorService`)

Targets 100% registry coverage.

### Layer 2: `GattServerTest.kt` (extend existing mockk-based file)

1. `onCharacteristicReadRequest stashes pending entry and does NOT call sendResponse`
2. `respondToReadRequest with known id calls sendResponse with Dart-supplied value and status`
3. `respondToReadRequest with unknown id fails with NoPendingRequest`
4. `respondToReadRequest maps every GattStatusDto value correctly to BluetoothGatt constant` (table test)
5. `respondToReadRequest with null value sends empty ByteArray`
6. `onCharacteristicWriteRequest (responseNeeded=true, preparedWrite=false) stashes and does NOT call sendResponse`
7. `respondToWriteRequest with known id calls sendResponse with null value`
8. `respondToWriteRequest with unknown id fails with NoPendingRequest`
9. `onCharacteristicWriteRequest with responseNeeded=false does not stash and does not call sendResponse`
10. `onCharacteristicWriteRequest with preparedWrite=true preserves existing auto-respond echo behavior`
11. `onConnectionStateChange(DISCONNECTED) drains pending requests for that central only`
12. `cleanup() clears all pending requests`

### Layer 3: `bluey_android/test/android_server_test.dart` (extend)

1. `respondToReadRequest propagates gatt-status-failed Pigeon error as GattStatusFailedException` — confirms the new error path surfaces correctly at the Dart adapter boundary.

### Layer 4: `bluey/test/...` (no new tests)

Domain-level tests against `FakeBlueyPlatform` are unchanged — the domain contract is unchanged. Existing tests keep passing.

### Layer 5: manual example-app verification (mandatory per CLAUDE.md)

- Run `bluey/example` with Android device as server + iOS device as client.
- Trigger read/write handlers in the example app; confirm values flow end-to-end.
- Confirm `LifecycleServer` heartbeat still works (it issues server-side reads/writes and must remain functional).

## Files touched

| File | Change |
|---|---|
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt` | **New** — registry class + `PendingRead` + `PendingWrite` data classes |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` | Modify callbacks + respond methods + disconnect drain + cleanup |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt` | Add `NoPendingRequest` case |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt` | Extend `toServerFlutterError` arm |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Messages.x.kt` | Add `GattStatusDto.toAndroidStatus()` |
| `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/PendingRequestRegistryTest.kt` | **New** — Layer 1 tests |
| `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt` | Add Layer 2 tests |
| `bluey_android/test/android_server_test.dart` | Add Layer 3 test |
| `docs/backlog/I020-*.md`, `docs/backlog/I021-*.md` | Mark `status: fixed`, set `fixed_in`, update `last_verified` |

## Breaking-change acceptability

Today, any Dart consumer that adds a GATT server but ignores `readRequests` / `writeRequests` streams has their peer see auto-success. After this fix, ignored requests hang until ATT_TIMEOUT. This is the *correct* behavior (matches iOS, matches BLE spec) and matches what the stress-test suite expects. No user-visible breakage for any caller that wires up the streams. Unwired callers were already broken (stale values, no rejection capability) — they just didn't know.

## DDD / CA alignment

- **Dependencies inward:** `PendingRequestRegistry` depends on nothing. `PendingRead` / `PendingWrite` depend on `android.bluetooth.BluetoothDevice` (unavoidable; that's why they live in the Android package). `GattServer` depends on the registry; registry doesn't depend on `GattServer`.
- **Value objects:** `PendingRead` / `PendingWrite` are immutable `data class`es with equality by value.
- **Single responsibility:** registry owns the pending-request invariant; `GattServer` orchestrates BLE stack + Flutter API; error translation stays in `Errors.kt`.
- **Platform-interface contract unchanged:** Dart domain layer cannot tell whether responses are auto-generated or Dart-mediated — the fix is purely internal to the Android platform impl.
