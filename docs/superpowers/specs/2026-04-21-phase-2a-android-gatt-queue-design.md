# Phase 2a — Android GATT Operation Queue Design

## Problem

Android's `BluetoothGatt` API allows **only one GATT operation in flight at a time per connection**. Calling `gatt.writeCharacteristic()` while another op is outstanding returns `false` synchronously, and no `BluetoothGattCallback` fires. Today, `ConnectionManager.kt` fires GATT ops directly from the caller's thread with no coordination, so:

- User-initiated ops (read / write / subscribe) race with the lifecycle heartbeat and with iOS's Service Changed re-discovery, producing sporadic `"Failed to <op>"` errors with no path to recover.
- The heartbeat's first failure used to tear the connection down (fixed in Phase 1 by teaching `LifecycleClient` to ignore non-timeout errors). Phase 1 made the system resilient to the race; Phase 2 eliminates the race at its source.

CoreBluetooth on iOS handles this internally — callers can submit multiple ops without coordination. We replicate that observable behavior on Android with an explicit per-connection operation queue.

## Goal

Serialize every GATT-layer operation per connection through a single internal queue so that `BluetoothGatt` never sees concurrent ops. Each op gets its own timeout, drain-on-disconnect semantics, and well-defined failure modes. Phase 1's lifecycle changes remain in place; Phase 2a reduces the frequency of the transient errors that Phase 1 made survivable.

### In scope

- A per-connection serial FIFO queue (`GattOpQueue`) inside `bluey_android`
- Routing every GATT op (read/write char, read/write descriptor, discoverServices, requestMtu, readRssi, setNotification's CCCD write) through the queue
- Per-op timeout delivered via the queue (replaces the existing ad-hoc `postDelayed` Runnables for these ops)
- Drain-on-disconnect: all pending + in-flight callbacks fire with a typed error when the link drops
- Hygiene fix #1: the missing `setNotification` CCCD-write timeout is subsumed by the queue
- Hygiene fix #2: the `cancelAllTimeouts` dangling-callback bug is subsumed — timeouts are now owned by the queue, drained together with their callbacks
- New Pigeon error code `"gatt-disconnected"` and corresponding public-facing `DisconnectedException` translation at the Dart pass-through and `BlueyConnection` boundaries
- Full TDD: Kotlin unit tests for `GattOpQueue` and integration tests for `ConnectionManager`'s use of it

### Out of scope (deferred to Phase 2b)

- Removing the now-unused `pendingReads` / `pendingWrites` / etc. maps in `ConnectionManager.kt`. They remain declared but unused in 2a; 2b removes them after 2a is on-device-validated.
- Removing the now-unused `cancelAllTimeouts` helper. Same reasoning.
- A proper reusable Kotlin test harness (helper factories, fake timers, test DSL). 2a uses the existing mockk pattern from `GattServerTest.kt` directly; 2b extracts reusable scaffolding.
- Write-without-response pipelining via BLE link-layer credits (Android's `peripheralIsReady(toSendWriteWithoutResponse:)` equivalent). Phase 2a is strictly serial for all op types. CoreBluetooth's pipelining is an optimization that buys higher throughput for some workloads; YAGNI until a workload demands it.
- iOS-side changes. CoreBluetooth already serializes internally; `bluey_ios` does not need a queue.

## Architecture

One `GattOpQueue` instance per connection, keyed by `connectionId` inside `ConnectionManager`. Strict-serial FIFO — at most one op in flight at a time.

```
┌─────────────────────────────────────────────────────────────┐
│ ConnectionManager (anti-corruption layer)                   │
│                                                             │
│  Map<String, GattOpQueue> queues  ← one per connection      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ GattOpQueue (aggregate root)                        │    │
│  │                                                     │    │
│  │   pending: ArrayDeque<GattOp>     ← FIFO            │    │
│  │   current: GattOp?                ← in-flight       │    │
│  │   currentTimeout: Runnable?                         │    │
│  │                                                     │    │
│  │   enqueue(op)  ────────────┐                        │    │
│  │   onComplete(result)       │                        │    │
│  │   drainAll(reason)         │                        │    │
│  │                            ▼                        │    │
│  │              [start op → gatt.X() → wait for cb]    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  BluetoothGattCallback overrides delegate to queue.onComplete│
└─────────────────────────────────────────────────────────────┘
```

**DDD notes:**

- `GattOpQueue` is the aggregate root for "work-in-flight on one connection." It owns its state; external callers only interact via `enqueue` / `onComplete` / `drainAll`. Consumers cannot bypass the queue to read or mutate `pending` or `current`.
- Each `GattOp` subclass is a Command object (Command pattern), not a Value Object — it carries a user callback that gets executed once. Its configuration fields are immutable after construction; equality-by-value is not meaningful here.
- Op type names follow the ubiquitous language of the GATT Client bounded context: `ReadCharacteristicOp`, `WriteCharacteristicOp`, `ReadDescriptorOp`, `WriteDescriptorOp`, `DiscoverServicesOp`, `RequestMtuOp`, `ReadRssiOp`, `EnableNotifyCccdOp`. Names match the platform-interface method names exactly. No platform-specific jargon (no `GattReadOp` or `BluetoothWriteOp`).
- `ConnectionManager` is the anti-corruption layer between Android's `BluetoothGatt` framework and the platform interface. The queue sits inside this ACL; nothing queue-shaped leaks above it.

**What is NOT queued:**

- Incoming notifications (`onCharacteristicChanged`) — pure arrivals, bypass the queue entirely, continue flowing into the notification stream unchanged.
- `connect` / `disconnect` — connection-level, not GATT.
- `bond` / `removeBond` — `BluetoothDevice.createBond()`, separate Android API.
- The synchronous `gatt.setCharacteristicNotification(char, enable)` call inside `setNotification` — purely local (doesn't hit the wire), runs inline before enqueueing the CCCD descriptor write.
- Callbacks that aren't responses to our ops (`onConnectionStateChange`, `onServiceChanged`, `onMtuChanged` when unsolicited).

## Components

### `GattOp` sealed class

Private inside `ConnectionManager.kt`'s package (`com.neutrinographics.bluey`). One concrete subclass per op type.

```kotlin
internal sealed class GattOp {
    /** Human-readable operation description for error messages, e.g. "Write characteristic". */
    abstract val description: String
    abstract val timeoutMs: Long
    /**
     * Initiates the op on the provided GATT handle. Returns true if the OS
     * accepted the request (async completion pending); false if it was
     * rejected synchronously (the caller's callback has been failed).
     */
    abstract fun execute(gatt: BluetoothGatt): Boolean
    /**
     * Delivers the op's outcome to the caller. Called on one of: successful
     * BluetoothGattCallback completion, timeout, synchronous rejection, or
     * queue drain on disconnect.
     */
    abstract fun complete(result: Result<Any?>)
}

internal class WriteCharacteristicOp(
    private val characteristic: BluetoothGattCharacteristic,
    private val value: ByteArray,
    private val writeType: Int,
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Write characteristic"
    override fun execute(gatt: BluetoothGatt): Boolean { /* gatt.writeCharacteristic... */ }
    override fun complete(result: Result<Any?>) {
        @Suppress("UNCHECKED_CAST")
        callback(result as Result<Unit>)
    }
}

// Similar shape: ReadCharacteristicOp, ReadDescriptorOp, WriteDescriptorOp,
// DiscoverServicesOp, RequestMtuOp, ReadRssiOp, EnableNotifyCccdOp.
// Each provides its own description string (preserved from Phase 1's
// existing timeout messages: "Read characteristic", "Write descriptor",
// "Service discovery", "MTU request", "RSSI read", "Enable notify CCCD").
```

Each op encapsulates the `gatt.X()` call it performs, the typed callback it fires, and its human-readable description for error messages. Timeout values come from the existing `ConnectionManager` config (`readCharacteristicTimeoutMs`, etc.) — `ConnectionManager` constructs ops with the configured values; the queue does not know about the config.

### `GattOpQueue` class

File: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt`. Lives in the same package as `ConnectionManager`; marked `internal` so it's not part of the plugin's public Kotlin API.

```kotlin
internal class GattOpQueue(
    private val gatt: BluetoothGatt,
    private val handler: Handler,
) {
    private val pending = ArrayDeque<GattOp>()
    private var current: GattOp? = null
    private var currentTimeout: Runnable? = null

    fun enqueue(op: GattOp) {
        pending.addLast(op)
        if (current == null) startNext()
    }

    fun onComplete(result: Result<Any?>) {
        val op = current ?: return  // stray callback: no-op
        currentTimeout?.let { handler.removeCallbacks(it) }
        currentTimeout = null
        current = null               // clear BEFORE firing callback (reentrancy)
        op.complete(result)
        if (pending.isNotEmpty()) startNext()
    }

    fun drainAll(reason: Throwable) {
        currentTimeout?.let { handler.removeCallbacks(it) }
        currentTimeout = null
        val inFlight = current
        current = null
        val queued = pending.toList()
        pending.clear()
        inFlight?.complete(Result.failure(reason))
        for (op in queued) op.complete(Result.failure(reason))
    }

    private fun startNext() {
        val op = pending.removeFirst()
        current = op
        val timeout = Runnable {
            // Defensive: only fire if this op is still current
            if (current !== op) return@Runnable
            currentTimeout = null
            current = null
            op.complete(Result.failure(
                FlutterError("gatt-timeout", "${op.description} timed out", null)
            ))
            if (pending.isNotEmpty()) startNext()
        }
        currentTimeout = timeout
        handler.postDelayed(timeout, op.timeoutMs)
        if (!op.execute(gatt)) {
            // Synchronous rejection
            currentTimeout?.let { handler.removeCallbacks(it) }
            currentTimeout = null
            current = null
            op.complete(Result.failure(
                IllegalStateException("Failed to ${op.description.replaceFirstChar { it.lowercase() }}")
            ))
            if (pending.isNotEmpty()) startNext()
        }
    }
}
```

Notes on the above skeleton:
- Error messages are built from `op.description` so the queue doesn't need to know about op-specific text. Timeout: `"<description> timed out"` (e.g. "Write characteristic timed out"). Sync rejection: `"Failed to <lowercased description>"` (e.g. "Failed to write characteristic"). Both string shapes match the existing Phase 1 / pre-Phase-1 message format.
- The reentrancy contract: `current` is cleared BEFORE `op.complete(result)` is called, so if a user callback synchronously enqueues another op, it finds a clean queue and gets FIFO-queued correctly.

### `ConnectionManager` integration

Changes to `ConnectionManager.kt`:

- New field: `private val queues = mutableMapOf<String, GattOpQueue>()`.
- On successful connect (inside the `onConnectionStateChange(STATE_CONNECTED)` branch): create a `GattOpQueue(gatt, handler)` and store it under `connectionId`.
- On disconnect (inside `onConnectionStateChange(STATE_DISCONNECTED)`): call `queues[connectionId]?.drainAll(FlutterError("gatt-disconnected", "connection lost with pending GATT op", null))`, then `queues.remove(connectionId)`.
- Each public method (`readCharacteristic`, `writeCharacteristic`, `readDescriptor`, `writeDescriptor`, `discoverServices`, `requestMtu`, `readRssi`, `setNotification`) constructs the appropriate `GattOp`, enqueues it on `queues[deviceId]`, and returns. The existing synchronous validation (device connected, characteristic exists, etc.) happens BEFORE enqueueing.
- Each `BluetoothGattCallback` override (`onCharacteristicWrite`, `onCharacteristicRead`, `onDescriptorWrite`, `onDescriptorRead`, `onServicesDiscovered`, `onMtuChanged`, `onReadRemoteRssi`) resolves `queues[address.toDeviceId()]` and calls `queue.onComplete(Result.success(...))` or `queue.onComplete(Result.failure(...))` based on the `status` argument.
- The existing `pendingReads` / `pendingWrites` / `pendingDescriptorReads` / `pendingDescriptorWrites` / `pendingServiceDiscovery` / `pendingMtuRequests` / `pendingRssiReads` maps and their corresponding timeout maps are **no longer written to or read from**. Their declarations stay in the file for 2b to remove.
- The existing `cancelAllTimeouts` helper stops being called from `onConnectionStateChange(STATE_DISCONNECTED)` — `drainAll` replaces it. The helper itself stays in the file for 2b to remove.

### `setNotification` two-step handling

Current `setNotification` does:
1. `gatt.setCharacteristicNotification(char, enable)` — local only, returns boolean sync.
2. Look up CCCD descriptor.
3. `gatt.writeDescriptor(cccd, value)` — async, fires `onDescriptorWrite`.

Under Phase 2a:
1. Step 1 runs inline before enqueueing. If it returns false, the caller's callback fails immediately with `IllegalStateException("Failed to set notification")` — no queue interaction.
2. CCCD lookup runs inline. If null, the caller's callback succeeds immediately (no CCCD = notify-enabled locally, nothing to write) — matches existing behavior.
3. The CCCD write is enqueued as an `EnableNotifyCccdOp` with timeout = `writeDescriptorTimeoutMs`. **This is new — today this descriptor write has no timeout at all.** When the queue fires its callback, the caller's `setNotification` completion completes with it.

## Data flow

```
caller (e.g. Dart-side writeCharacteristic)
   │
   ▼
ConnectionManager.writeCharacteristic(deviceId, charUuid, value, withResponse, cb)
   │  validate connected, find char
   │  construct WriteCharacteristicOp(char, value, writeType, cb, writeCharacteristicTimeoutMs)
   │  queues[deviceId].enqueue(op)
   ▼
GattOpQueue.enqueue
   │  pending.addLast(op)
   │  if (current == null) startNext()
   ▼
startNext
   │  current = pending.removeFirst()
   │  schedule currentTimeout via handler.postDelayed
   │  if (!op.execute(gatt)) → handleSyncFailure()
   ▼
op.execute → gatt.writeCharacteristic(...)
   │  returns true (async completion pending)
   ▼
   ...OS sends write over the air, remote ACKs...
   ▼
BluetoothGattCallback.onCharacteristicWrite(status=SUCCESS)
   │  queues[deviceId].onComplete(Result.success(Unit))
   ▼
GattOpQueue.onComplete
   │  handler.removeCallbacks(currentTimeout)
   │  current = null     ← cleared BEFORE user callback for reentrancy safety
   │  op.complete(Result.success(Unit))     ← fires caller's cb
   │  if pending non-empty: startNext()
```

## Error handling

Four failure modes, all unified through the queue:

| Mode | Trigger | Op callback receives | Queue action |
|------|---------|----------------------|--------------|
| Sync rejection | `op.execute(gatt)` returns `false` | `IllegalStateException("Failed to <op>")` (unchanged from today) | Advance to next op |
| Status failure | `BluetoothGattCallback.onXXX(status != SUCCESS)` | `IllegalStateException("<op> failed with status: $status")` (unchanged) | Advance |
| Timeout | `handler.postDelayed` fires | `FlutterError("gatt-timeout", "...", null)` (Phase 1) | Advance |
| Disconnect | `onConnectionStateChange(STATE_DISCONNECTED)` | `FlutterError("gatt-disconnected", "...", null)` (new) | Drain all |

**New Pigeon error code: `"gatt-disconnected"`.** Emitted by `ConnectionManager` during drain, carried over Pigeon to Dart. To preserve the typed-exception symmetry established in Phase 1, the platform-interface layer gets a companion typed exception and the pass-throughs translate to it; `BlueyConnection` then catches the typed platform exception at its public API boundary and rethrows the existing `DisconnectedException` from the `BlueyException` hierarchy.

**New typed platform exception — `bluey_platform_interface/lib/src/exceptions.dart`:**

```dart
/// A GATT operation (read, write, etc.) could not complete because the
/// underlying connection was torn down before the operation's response
/// was received. Distinct from [GattOperationTimeoutException]: the peer
/// didn't just stop responding — the link itself is gone.
class GattOperationDisconnectedException implements Exception {
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

Same shape/contract as Phase 1's `GattOperationTimeoutException`.

**Dart-side pass-through helper change (`bluey_android/lib/src/android_connection_manager.dart` and the iOS mirror):**

The existing `_translateGattTimeout` helper currently handles only `'gatt-timeout'`. Rename to `_translateGattPlatformError` and add the `'gatt-disconnected'` branch:

```dart
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

Every existing call site updates from `_translateGattTimeout(...)` to `_translateGattPlatformError(...)`. All existing Phase 1 tests continue to pass unchanged (the timeout branch behavior is preserved).

**`BlueyConnection`'s public API boundary (`bluey/lib/src/connection/bluey_connection.dart`):**

The parallel helper in `BlueyConnection` (also currently named `_translateGattTimeout`, also renamed to `_translateGattPlatformError`) now catches both typed platform exceptions and rethrows the appropriate `BlueyException`. It has access to `this.deviceId` so it can construct `DisconnectedException` correctly:

```dart
Future<T> _translateGattPlatformError<T>(
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

Note: `DisconnectedException` (from `bluey/lib/src/shared/exceptions.dart`) takes a `UUID deviceId` and a `DisconnectReason` enum value — NOT a free-form string. `DisconnectReason.linkLoss` is the closest existing match ("Connection lost (out of range, etc.)") and is the right semantic for a mid-op disconnect.

In `BlueyConnection`, `deviceId` is available as a field on the outer class, so the helper needs to be a method rather than a top-level function — or be passed the `deviceId` explicitly. Convert from a top-level helper to an instance method, OR accept `deviceId` as an extra parameter. Call sites choose based on what reads cleaner when implementing; this is a small detail best resolved during implementation. The `BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor` classes don't have the connection-level `deviceId` directly available; they have `_connectionId` (the platform handle string). Resolve by passing the owning `BlueyConnection`'s `deviceId` into these subclasses at construction time so they can call the same helper.

## Testing

### Kotlin unit tests — `GattOpQueue`

New file: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattOpQueueTest.kt`.

Uses the existing mockk pattern from `GattServerTest.kt`. Mocks `BluetoothGatt` and `Handler`; `Handler.postDelayed` is mocked to capture the `Runnable` without executing it, so each test can fire the timeout manually.

Test cases:

1. `enqueue when idle starts op immediately` — verify `gatt.writeCharacteristic` called once, `postDelayed` scheduled.
2. `enqueue while busy waits for current to complete` — second op verified NOT executed until first's `onComplete` fires.
3. `onComplete fires caller callback and starts next op` — callback invoked with result; second op's `gatt.X()` now called.
4. `timeout fires caller callback with gatt-timeout and advances` — test fires the captured `Runnable`; verify caller sees timeout error, next op starts.
5. `sync rejection fires caller callback with IllegalStateException and advances` — stub `gatt.writeCharacteristic` to return false; verify IllegalStateException delivered, next op starts.
6. `drainAll fires all callbacks with gatt-disconnected and empties queue` — enqueue three ops, drain; all three callbacks receive the drain reason, queue is empty.
7. `reentrant enqueue inside user callback preserves FIFO order` — the reentrant op queues behind already-pending ops and runs when its turn comes.
8. `stray onComplete on empty queue is a no-op` — no crash, no state change.
9. `late timeout after completion is a no-op` — fire `onComplete` then fire the (now-stale) timeout Runnable; caller callback fires only once.
10. `multiple enqueues while busy preserve FIFO order` — four ops queued; verify execution order A → B → C → D.

### Kotlin integration tests — `ConnectionManager`

New file: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ConnectionManagerQueueTest.kt`.

Tests `ConnectionManager`'s use of the queue end-to-end (mocking `BluetoothGatt` and callbacks but using the real `GattOpQueue` and real op types).

Test cases:

1. Two `writeCharacteristic` calls back-to-back → `gatt.writeCharacteristic` called twice in submission order, second only after `onCharacteristicWrite` callback delivered for the first.
2. Mixed `writeCharacteristic` + `readCharacteristic` + `discoverServices` → ops execute in submission order, each waiting for its callback.
3. `onConnectionStateChange(DISCONNECTED)` → all pending callbacks receive `FlutterError("gatt-disconnected", ...)`, queue map entry removed.
4. `setNotification` with CCCD present → `gatt.setCharacteristicNotification` called sync (returns true), then `gatt.writeDescriptor(cccd)` queued, timeout active.
5. `setNotification` CCCD-write timeout fires → caller callback sees `FlutterError("gatt-timeout", ...)` (hygiene fix #1 validated).
6. `onCharacteristicChanged` (incoming notification) bypasses queue — verify `queue.onComplete` NOT called for notification arrivals, and that the notification is still forwarded to `flutterApi.onNotification` as before.

### Dart platform-interface tests — `GattOperationDisconnectedException`

Extend `bluey_platform_interface/test/exceptions_test.dart` with a new `group('GattOperationDisconnectedException', ...)` mirroring the Phase 1 `GattOperationTimeoutException` group: exposes operation name, is an `Exception`, value equality, `toString` mentions the operation.

### Dart pass-through translation tests

Extend `bluey_android/test/android_connection_manager_test.dart` and `bluey_ios/test/ios_connection_manager_test.dart`:

- Update the existing `group('error translation', …)` — the helper is now `_translateGattPlatformError`, not `_translateGattTimeout`. The negative ("rethrows non-timeout non-disconnect unchanged") test updates its assertion to confirm the third branch doesn't fire on unrelated codes.
- One new test per file: `writeCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException` with `.operation == 'writeCharacteristic'`.
- The existing parameterized "all wrapped methods translate gatt-timeout with correct operation name" test gets a mirror: "all wrapped methods translate gatt-disconnected with correct operation name" covering every wrapped op.

### Dart integration test — `BlueyConnection` public API

Extend `bluey/test/connection/bluey_connection_timeout_test.dart`:

- New test: `FakeBlueyPlatform.simulateWriteDisconnected = true` → `RemoteCharacteristic.write()` throws `DisconnectedException` (with the Connection's `deviceId` and `DisconnectReason.linkLoss`).
- New test: the thrown `DisconnectedException` is a `BlueyException` (sealed-hierarchy pattern-matching still works post-2a).
- New test: the platform-interface typed exception (`GattOperationDisconnectedException`) does NOT leak to public consumers. Same shape as the Phase 1 `GattOperationTimeoutException` non-leak test.

`FakeBlueyPlatform` gets a new field `simulateWriteDisconnected` that throws `GattOperationDisconnectedException('writeCharacteristic')` from `writeCharacteristic`, symmetric with the existing `simulateWriteTimeout`.

### What's NOT tested at the Dart integration layer

- `FakeBlueyPlatform` does not model Android's single-op constraint. Serialization behavior can only be validated at the Kotlin layer. The observable improvement (fewer `"Failed to <op>"` errors in practice) is confirmed by the on-device manual test.

### Manual device test

Run the same manual repro from Phase 1's closure:
1. iOS advertising as server, Android as client.
2. Scan, connect, subscribe to a characteristic, send notifications from iOS, read from Android.
3. Watch Android logs — confirm NO `"Failed to read from characteristic"` / `"Failed to write characteristic"` messages. Any such error in 2a indicates the queue is being bypassed somewhere.

## Migration plan

Commits are organized TDD-first, each commit leaves the suite green:

1. `feat(platform-interface): add GattOperationDisconnectedException` — RED (tests for the new type) + GREEN (add the class). Mirror of Phase 1's typed-exception introduction; tests go in `bluey_platform_interface/test/exceptions_test.dart`.

2. `test(bluey_android): add GattOpQueueTest.kt with failing unit tests` — RED. Tests exercise the queue alone via mocked `BluetoothGatt` and `Handler`. Fails because `GattOpQueue` doesn't exist yet.

3. `feat(bluey_android): add GattOpQueue and GattOp sealed hierarchy` — GREEN for the unit tests. New files: `GattOpQueue.kt`, `GattOp.kt` (or inlined inside `ConnectionManager.kt` — implementation's choice). No `ConnectionManager` changes yet.

4. `test(bluey_android): add ConnectionManagerQueueTest.kt with failing integration tests` — RED. Tests exercise `ConnectionManager` routing ops through the queue.

5. `refactor(bluey_android): route GATT ops through queue` — GREEN. `ConnectionManager`'s public methods now enqueue instead of firing directly; `BluetoothGattCallback` overrides delegate to the queue. `pendingX` maps become dead writes (stop being populated / read); declarations remain for 2b to remove. `cancelAllTimeouts` stops being called; declaration remains for 2b.

6. `feat(bluey_android): drain queue on disconnect with gatt-disconnected code` — adds the drain path in `onConnectionStateChange(STATE_DISCONNECTED)`. Kotlin integration test for drain passes.

7. `refactor(bluey_android,bluey_ios): rename translation helper, add gatt-disconnected branch` — Dart-side pass-through. Renames `_translateGattTimeout` → `_translateGattPlatformError`, updates all existing call sites, adds the `gatt-disconnected` → `GattOperationDisconnectedException` branch. New test per platform: `writeCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException`. Existing Phase 1 tests updated to reflect the new helper name.

8. `refactor(bluey): surface DisconnectedException from BlueyConnection at public API` — renames `_translateGattTimeout` → `_translateGattPlatformError` in `bluey_connection.dart`, adds the `GattOperationDisconnectedException` → `DisconnectedException(deviceId, DisconnectReason.linkLoss)` branch. Resolves how `deviceId` is threaded into `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor`.

9. `test(bluey): add simulateWriteDisconnected + BlueyConnection disconnect translation tests` — `FakeBlueyPlatform` gains `simulateWriteDisconnected`; new tests in `bluey_connection_timeout_test.dart` verify the rewrap at the public API.

10. `docs(bluey_android): document operation queue in ANDROID_BLE_NOTES.md` — add a section on Android's single-op constraint, our queue's guarantees, and what's NOT queued (notifications, bond, connect/disconnect).

Each commit passes CLAUDE.md's TDD discipline (test → impl → refactor). Order matters: commit 3 depends on commit 1's typed exception (via the Kotlin-side sealed op hierarchy receiving configured `FlutterError` codes). Commits 7 and 8 depend on commit 1 (the typed Dart exception exists) and commit 6 (the Kotlin side emits `gatt-disconnected`).

## Success criteria

- All 712+ existing tests still pass after Phase 2a lands.
- New tests:
  - ~4 tests in `bluey_platform_interface` for the new `GattOperationDisconnectedException` type (mirror of Phase 1's `GattOperationTimeoutException` tests).
  - ~10 Kotlin unit tests for `GattOpQueue`.
  - ~6 Kotlin integration tests for `ConnectionManager`.
  - ~4 Dart pass-through translation tests (2 per platform: one direct `gatt-disconnected` → typed-exception, plus update to the parameterized "all wrapped methods" for the new code).
  - ~3 Dart integration tests for `BlueyConnection` translation to `DisconnectedException` (surface + is-BlueyException + no-leak).
  - Total ~27 new tests.
- Manual device test: same flow as Phase 1's repro shows no `"Failed to <op>"` transient errors caused by op collisions.
- `flutter analyze` clean (no new warnings).
- No behavioral regression on iOS (`bluey_ios` changes are limited to the pass-through's extended error translation).

## Open questions

None at design time. All in-scope decisions are settled above.
