# iOS Concurrent GATT Op Correctness — Design

**Date:** 2026-04-23
**Status:** Approved
**Scope:** `bluey_ios` — Swift `CentralManagerImpl` completion tracking

## 1. Problem

`CentralManagerImpl` stores pending Pigeon completions in maps of the form:

- `[deviceId: [charUuid: Completion]]` (read, write, notify, descriptor read/write)
- `[deviceId: Completion]` (connect, disconnect, discoverServices, readRssi)

Each map holds **one completion per key**. When the Dart layer issues N
concurrent operations against the same key (most commonly `Future.wait(…)`
over 50 writes to one characteristic in the burst-write stress test), the
second op overwrites the first, the third overwrites the second, and so on.
CoreBluetooth faithfully executes all N ops and delivers N
`didWriteValueFor` callbacks in submission order — but our cache only holds
the most-recently-stored completion, so **only one** Dart future resolves.
The remaining N-1 callbacks find an empty slot and are silently dropped
(line 706-708 of `CentralManagerImpl.swift`).

### Observed symptoms

- **Burst write (iOS client → Android server):** UI shows "attempt 1
  succeeded" then hangs indefinitely. `Future.wait` never returns because
  N-1 completions are orphaned.
- **Downstream effects:** activity-aware heartbeat timing and reconnect
  cycles become misleading (connection thrashes because upstream code is
  waiting on futures that will never resolve).
- The Android adapter does not have this bug. It uses `GattOpQueue` which
  serializes ops with per-op callbacks (Android's `BluetoothGatt` fails if
  you issue a second op while one is in-flight, so it had to build a
  queue).

## 2. Goals and non-goals

**Goals**
- Every Dart future backing a GATT op resolves exactly once: either with
  the operation's result, a `gatt-timeout`, a `gatt-disconnected` on
  disconnect, or another typed platform error.
- No regression in throughput for reads (CoreBluetooth pipelines them).
- Per-op timeouts correctly reflect "time spent actually being processed
  by CoreBluetooth," not wall-clock since submission.
- Cross-platform parity with Android's queue semantics where it matters.

**Non-goals**
- Building a submission-gating queue on top of CoreBluetooth's own queue.
  CoreBluetooth already serializes write-with-response and pipelines
  reads; replicating that above it would hurt throughput and fight the
  platform.
- Changing Dart-facing API or the platform-interface contract.
- Rewriting unrelated `CentralManagerImpl` logic (peripheral discovery,
  notification delivery path, lifecycle wiring).

## 3. Architecture

### 3.1 New type: `OpSlot<T>`

A Swift generic type representing a FIFO of pending completions for a
single (device, key) pair. Lives in `bluey_ios/ios/Classes/`, probably
`OpSlot.swift`. Public API:

```swift
final class OpSlot<T> {
    init(timerFactory: TimerFactory = RealTimerFactory())

    /// Append a completion with its own timeout. If the appended entry
    /// becomes the head (slot was empty), starts its timer immediately.
    func enqueue(
        completion: @escaping (Result<T, Error>) -> Void,
        timeoutSeconds: TimeInterval,
        timeoutError: @autoclosure @escaping () -> Error
    )

    /// Pop head, cancel its timer, fire completion with `result`.
    /// If a new head exists, start its timer.
    /// No-op if slot is empty.
    func completeHead(_ result: Result<T, Error>)

    /// Cancel all timers, fire every pending completion with `error`,
    /// clear the slot. Safe to call on an empty slot.
    func drainAll(_ error: Error)

    var isEmpty: Bool { get }
}
```

**Key invariant:** at any time, at most one timer is live per slot — the
head's. Non-head ops are "waiting their turn." This is the Android-parity
timeout semantic.

### 3.2 Storage migration in `CentralManagerImpl`

Each former completion cache becomes a slot map. Per-characteristic:

```swift
// Before
var writeCharacteristicCompletions: [String: [String: (Result<Void, Error>) -> Void]] = [:]
var writeCharacteristicTimers: [String: [String: DispatchWorkItem]] = [:]

// After
var writeCharacteristicSlots: [String: [String: OpSlot<Void>]] = [:]
// (no separate timer map — OpSlot owns its timers)
```

Per-device:

```swift
// Before
var readRssiCompletions: [String: (Result<Int64, Error>) -> Void] = [:]
var readRssiTimers: [String: DispatchWorkItem] = [:]

// After
var readRssiSlots: [String: OpSlot<Int64>] = [:]
```

The 8 affected paths and their `T`:

| Path | T |
|---|---|
| `readCharacteristic` | `FlutterStandardTypedData` |
| `writeCharacteristic` | `Void` |
| `readDescriptor` | `FlutterStandardTypedData` |
| `writeDescriptor` | `Void` |
| `notify` (subscribe/unsubscribe via `setNotificationValue`) | `Void` |
| `discoverServices` | `Void` |
| `readRssi` | `Int64` |
| `connect` / `disconnect` | `Void` |

### 3.3 Submission model — eager (unchanged)

Every op is submitted to CoreBluetooth immediately on the Pigeon method
call, same as today. `OpSlot` only tracks completions and timeouts — it
does not gate submission to the peripheral. This preserves:

- CoreBluetooth's intrinsic write-with-response serialization.
- CoreBluetooth's read pipeline (multiple reads can be in-flight).
- `peripheralIsReady(toSendWriteWithoutResponse:)` semantics for
  write-without-response.

### 3.4 Disconnect cleanup

`clearPendingCompletions(for deviceId:)` iterates every slot map for the
device and calls `OpSlot.drainAll(…)` with a `gatt-disconnected`
`PigeonError`. All pending Dart futures resolve with a
`GattOperationDisconnectedException` (via existing Dart-side error
mapping in `ios_connection_manager.dart`).

## 4. Data flow — worked example

**Scenario:** Dart fires 50 concurrent writes to characteristic
`b1e7a002`, each `withResponse: true`.

```
Dart:    writeCharacteristic(…) × 50     (concurrent Future.wait)
           │
           ▼
Swift:   writeCharacteristic() × 50      (Pigeon serializes on main queue)
           │
           ├── call 1:  slot.enqueue(c1, 10s)   → slot = [c1], timer_1 armed
           │           peripheral.writeValue(…)
           ├── call 2:  slot.enqueue(c2, 10s)   → slot = [c1, c2], NO timer for c2
           │           peripheral.writeValue(…)
           │   …
           └── call 50: slot.enqueue(c50, 10s)  → slot = [c1 … c50]
                       peripheral.writeValue(…)

CoreBluetooth: internal serialization, ack'd in submission order
           │
           ▼
Swift:   didWriteCharacteristicValue  (× 50, in submission order)
           │
           ├── ack 1:  slot.completeHead(.success) → pop c1, fire c1(.success)
           │                                      → new head = c2, timer_2 armed now
           ├── ack 2:  slot.completeHead(.success) → pop c2, fire c2(.success)
           │                                      → new head = c3, timer_3 armed now
           │   …
           └── ack 50: slot now empty
```

Each op gets a full 10s from the moment it becomes head, not from
submission. Op 50 won't spuriously time out even if ops 1-49 each take
~1s (op 50's clock doesn't start until ~second 49).

**Reads (pipelined case):** same queue shape. CoreBluetooth may dispatch
reads faster than strictly serial; callbacks still arrive in submission
order per CB guarantees, and FIFO pop remains correct.

**Disconnect mid-burst:** `didDisconnectPeripheral` →
`clearPendingCompletions` → every slot's `drainAll(gattDisconnectedError)`
→ all 50 Dart futures resolve with
`GattOperationDisconnectedException`. No orphans.

## 5. Error handling and edge cases

### 5.1 Late callbacks after timeout

If `OpSlot` times out the head and CoreBluetooth subsequently delivers
the ack anyway, the next head would be resolved with the wrong op's
result.

**Mitigation:** `OpSlot` tracks the entry currently being timed-out, and
the next incoming `completeHead` for that slot that matches the
timed-out entry's identity is dropped.

A simple way to implement this: include a monotonically increasing op ID
in each slot entry. `completeHead` advances when called; if a late
callback arrives and the slot head has a different ID than the
just-timed-out op, the callback resolves the current head normally. In
practice, a single "ignore-next-delivery" flag is simpler if we assume
CoreBluetooth delivers at most one late callback per timed-out op; we'll
pick the simpler form unless tests reveal the need for full ID tracking.

Android uses `if (current !== op) return` in its timeout handler — the
same identity check.

### 5.2 Disconnect racing timeout

If a disconnect arrives just as a timer is about to fire:
- `drainAll` cancels all timers first, then fires completions, in that
  order. The already-scheduled timer closure captures `self` weakly and
  short-circuits if the slot has been cleared.

### 5.3 Reentrancy

A completion callback may synchronously enqueue a new op. `OpSlot`
handles this by:
1. Popping the head.
2. Firing the callback (which may enqueue).
3. Starting the new head's timer if the slot is non-empty.

Step 3 uses the *current* head after the callback returns, so a
reentrant enqueue that appended to the slot will see its entry promoted
to head if it was the only one left. If the original op had successors
already queued, the reentrant entry waits behind them (FIFO preserved).

### 5.4 Stray callbacks

CoreBluetooth can deliver `didWriteValueFor` for a characteristic we
never wrote to (rare — cached response replay). `completeHead` is a
no-op on an empty slot, matching current defensive behavior.

### 5.5 Empty slot retention

Slots stay allocated in their parent map once created (per device, per
key), even when they go empty after the last op completes. This avoids
re-allocation churn during steady-state bursts. `clearPendingCompletions`
removes them entirely on disconnect.

## 6. Testing strategy

### 6.1 Unit tests — `OpSlotTests.swift`

XCTest cases covering `OpSlot<Void>` (and `OpSlot<Int>` for generic
correctness):

1. `enqueue_intoEmptySlot_startsHeadTimer`
2. `enqueue_intoNonEmptySlot_doesNotStartSecondTimer`
3. `completeHead_popsFIFO_inOrder`
4. `completeHead_withNewHead_startsNextTimer`
5. `completeHead_onEmptySlot_isNoOp`
6. `timeout_firesHeadCompletionOnly`
7. `timeout_advancesQueue_andStartsNextTimer`
8. `timeout_thenLateCallback_doesNotResolveWrongOp`
9. `drainAll_firesEveryPendingWithError`
10. `drainAll_cancelsAllTimers`
11. `drainAll_onEmptySlot_isNoOp`
12. `reentrantEnqueue_duringCompletionCallback_preservesOrder`

### 6.2 Timer abstraction for testability

`OpSlot` accepts a `TimerFactory` protocol:

```swift
protocol TimerFactory {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> TimerHandle
}

protocol TimerHandle {
    func cancel()
}
```

- Production: `DispatchWorkItem`-based implementation using
  `DispatchQueue.main.asyncAfter`.
- Tests: `FakeTimerFactory` with `advance(by:)` to fire timers deterministically
  without real sleep.

### 6.3 Integration smoke tests

Where `CentralManagerImpl` can be exercised without full CoreBluetooth
stubbing (i.e., through public methods that don't immediately call
CB APIs), add 1-2 smoke tests confirming wiring. If the Swift surface
area is too entangled with CB, rely on `OpSlot` unit tests plus Dart-side
verification.

### 6.4 End-to-end verification

After the fix:
1. Re-run iOS-client → Android-server burst-write stress test.
   Expected: attempts = 50, successes = 50, 0 hang.
2. Re-run other iOS-client stress tests (mixed-ops, soak,
   failure-injection, timeout-probe, notification-throughput,
   MTU-probe). Expected: no regressions.
3. Re-run Android-client → iOS-server stress tests as regression check
   (should behave the same as before — this fix is client-side iOS).

## 7. Out of scope

- The activity-aware liveness / reconnect investigation. The observed
  reconnect loop in the original bug report was downstream of the
  orphaned completions; fixing completions is expected to eliminate the
  visible symptom. If reconnect thrashing persists after this PR, it
  gets its own investigation.
- Notification delivery path (`didUpdateValueFor:` for notifying
  characteristics). Notifications don't have pending completions — they
  stream into `flutterApi.onNotification`. No bug.
- Android parity beyond semantic matching of queue ordering. We are not
  importing Android's `GattOpQueue` architecture wholesale, because iOS
  has its own intrinsic serialization we'd be fighting.

## 8. File touch list (indicative)

- **New:** `bluey_ios/ios/Classes/OpSlot.swift`
- **New:** `bluey_ios/ios/Classes/TimerFactory.swift` (or folded into `OpSlot.swift`)
- **New:** `bluey_ios/example/ios/RunnerTests/OpSlotTests.swift`
- **Edited:** `bluey_ios/ios/Classes/CentralManagerImpl.swift` — replace
  8 completion/timer map pairs with slot maps, update each path's
  enqueue/complete call sites, update `clearPendingCompletions`.
- **Edited:** `bluey_ios/example/ios/Runner.xcodeproj/…` — add new files
  to the Runner and RunnerTests targets.

## 9. Risks and open questions

1. **Late-callback mitigation complexity.** The simple
   "ignore-next-delivery" flag may not suffice if CoreBluetooth can
   deliver multiple delayed callbacks for a single timed-out op. Will
   validate during implementation; fall back to monotonic op IDs if
   needed.
2. **TimerFactory injection.** Adding a protocol parameter to `OpSlot`
   adds surface area. Alternative: make timers internal
   (`DispatchWorkItem` directly) and test timeout behavior via
   integration paths. Decision deferred to planning phase; my
   recommendation is the protocol for determinism in tests.
3. **Write-without-response gating.** `peripheralIsReady(toSendWriteWithoutResponse:)`
   is not currently wired to anything; write-without-response
   completes synchronously from Dart's perspective. This design does not
   change that. If it becomes an issue it's a separate concern.
