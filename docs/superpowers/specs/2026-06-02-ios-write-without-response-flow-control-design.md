# iOS write-without-response flow control (I339)

- **Date:** 2026-06-02
- **Status:** Approved (design)
- **Backlog:** [I339](../../../docs/backlog/I339-ios-write-without-response-no-flow-control.md)
- **Prior art:** I040 (the analogous fix on the iOS *notification* side — `peripheralManagerIsReadyToUpdateSubscribers:` drain). Android's `GattOpQueue` (the equivalent flow-control shape on the Android central side).
- **Related:** I338 (Pattern B; why this corruption became observable), I050 (prepared-write — distinct), I337.

## Problem

On the iOS central role, `CentralManagerImpl.writeCharacteristic(... withResponse: false)` calls `peripheral.writeValue(_:for:type: .withoutResponse)` **unconditionally** and returns success immediately. It never consults `peripheral.canSendWriteWithoutResponse` and implements no `peripheralIsReady(toSendWriteWithoutResponse:)` delegate.

Under burst — typically when a stalled Dart isolate unblocks and flushes a backlog of queued sends — some `writeValue` calls hit CoreBluetooth while its WriteNoResponse queue is full. Apple's documented behavior in that state is that writes "may be silently dropped or coalesced." Coalescing two adjacent framed payloads with no delimiter produces the observed corruption: a frame whose payload tail carries the **next** frame's magic prefix (`…}]}GS`, where `GS` = `0x47 0x53`, the head of `GSP1`). The Dart layer believes every byte was delivered (the call returned success), so the frame encoder keeps advancing.

Post-I338 the symptom is **permanent for the GATT session**: because heartbeat silence no longer tears down the consumer's frame decoder (the I338 fix, by design), the misalignment never self-heals. A single qualifying isolate hang (≥ ~10 s — e.g. iOS keyboard XPC reconnect) dead-ends the iOS-central → peer-peripheral data path for the lifetime of the link. See I339 for the full dogfood evidence.

## The contract (what this fix does and does not guarantee)

- **Guarantees:** no *local* drop or coalescing of WriteNoResponse writes, and in-order hand-off to CoreBluetooth. bluey honors CoreBluetooth's local flow-control contract instead of pretending it doesn't exist.
- **Does NOT guarantee end-to-end delivery.** "Without response" means no ATT-layer acknowledgment from the remote peer; there is no ATT retransmit. A consumer needing guaranteed delivery uses write-*with*-response (or an app-level ack). This is not a caveat — it is the defined trade-off of the no-response write type. Flow control paces against the **local** transmit buffer (`canSendWriteWithoutResponse`), not the peer's receipt.

## Decision: native flow control in `CentralManagerImpl` (fix A)

The flow-control loop lives in native Swift, right at the CoreBluetooth boundary — mirroring I040 (which solved the notification-side drain natively) and matching where the signal (`canSendWriteWithoutResponse`) exists. The alternative of exposing the primitives across Pigeon and pacing in Dart was rejected: it would add a Dart↔native round-trip to every bulk write — channel chatter and latency on exactly the high-throughput path being fixed.

### Mechanism

The FIFO/drain is a **standalone, unit-testable type** — `PendingWriteQueue` — whose interface is a **deliberate twin of the existing `PendingNotificationQueue`** (I040). Both are iOS's "drain-while-the-gate-is-open" flow-control pattern; keeping them structurally identical means a developer who understands one understands the other. It depends only on an **injected `send` closure**, not a live `CBPeripheral`, so its logic is testable in isolation:

```
internal final class PendingWriteQueue {
    struct Entry { let characteristic: CBCharacteristic; let data: Data; let completion: (Result<Void, Error>) -> Void }
    func enqueue(_ entry: Entry) -> Bool                 // false at cap; caller fires its own .failure (mirrors PendingNotificationQueue)
    func drain(send: (Entry) -> Bool)                    // FIFO: send each; true → pop + complete(.success); false → stop, preserve tail
    func failAll(error: Error)                           // disconnect/teardown: fail every pending completion, empty the queue
}
```

This is the *same* signature as `PendingNotificationQueue.drain(send:)` — the only difference is what the `send` closure does. For notifications the closure calls `updateValue(...)` (which returns a Bool). For writes, `writeValue(...)` returns `Void`, so the `canSendWriteWithoutResponse` precheck folds **into** the closure (returning `false` when the gate is shut):

`CentralManagerImpl` holds one `PendingWriteQueue` per `deviceId` and wires the real CoreBluetooth surface into it:

1. `writeCharacteristic(... withResponse: false)` → `queue.enqueue(...)` then `pump(deviceId)`. The `.withResponse` branch (the existing `OpSlot` path) is untouched.
2. `pump(deviceId)` calls:
   ```swift
   queue.drain(send: { entry in
       guard peripheral.canSendWriteWithoutResponse else { return false }   // gate shut → stop, keep tail
       peripheral.writeValue(entry.data, for: entry.characteristic, type: .withoutResponse)
       return true
   })
   ```
3. The new delegate `peripheralIsReady(toSendWriteWithoutResponse: CBPeripheral)` re-pumps that peripheral's queue when the gate reopens.
4. The disconnect/cleanup path calls `queue.failAll(error:)`.

The queue owns the FIFO + completion logic (testable); the manager owns only the thin wiring of CoreBluetooth's `canSendWriteWithoutResponse` / `writeValue` / `peripheralIsReady` / disconnect into it (dogfood-confirmed).

### Completion semantics — complete-on-hand-off

The Dart `write()` Future resolves only when the write is actually handed to CoreBluetooth (drained), **not** on enqueue. When the gate is shut the completion is held and fires when the drain reaches it. The shared principle with Android is *complete-when-the-local-stack-accepts-the-write* — Android completes on `onCharacteristicWrite`, iOS completes when the entry clears the `canSendWriteWithoutResponse` gate. (The concurrency models differ — see below — but the **contract** is the same on both platforms: `write()` resolving means "handed to the radio," and resolves later under saturation.)

Consequence — automatic backpressure: a serial consumer that `await`s each write (e.g. gossip's `_sendQueue`) caps outstanding writes at ~1, so the FIFO stays at ~1 entry and never floods. This is the property that prevents the saturation in the first place. The observable behavior change — a `write()` Future taking longer to resolve under saturation — is the intended signal that the link is busy.

### Edge handling

`PendingWriteQueue` mirrors `PendingNotificationQueue`'s recovery model (no per-entry timer; rely on the disconnect-driven `failAll`), which is the right fit for iOS:

| Case | Behavior |
|---|---|
| Peripheral disconnects / link lost / `disconnect()` | `failAll(error:)` fails every pending WnR completion for that `deviceId` with `gatt-disconnected` and empties the FIFO. Wired into the existing `didDisconnectPeripheral` → `clearPendingCompletions(for:error:)` path, right beside the existing `writeCharacteristicSlots…drainAll` cleanup. |
| Gate momentarily shut on a live link | `peripheralIsReady(toSendWriteWithoutResponse:)` reopens it (≈ms) → drain resumes. No timer needed. |
| Fast producer | No FIFO cap. Backpressure (complete-on-hand-off) + disconnect-`failAll` are the safety nets. |

- **No per-write timeout** (a deliberate divergence from Android's `GattOpQueue`, which *needs* one because it waits on a per-op callback that might never fire). iOS's recovery is the central-role `didDisconnectPeripheral` callback — a first-class CoreBluetooth signal with no I201-style gap — so a write cannot hang indefinitely: an un-drainable TX queue is an un-acked link, which the BLE supervision timeout resolves into a disconnect → `failAll`. Worst-case "stuck" is therefore bounded by the supervision timeout (seconds up to ~30 s, connection-parameter dependent), not a fixed 10 s, and never forever. This matches `PendingNotificationQueue`, which likewise has no per-entry timer.
- **Scope of the FIFO:** WriteNoResponse-specific, alongside the existing per-op-type structures (`OpSlot` for with-response, etc.). Not a unified op queue like Android's — CoreBluetooth gates WnR independently of with-response acks, so a dedicated FIFO is correct and keeps the change scoped.

### A note on cross-platform shape (Android `GattOpQueue` vs iOS `PendingWriteQueue`)

The two platforms' flow-control queues are **shaped differently for a platform-API reason, not by accident**, and the difference should not be "fixed" by forcing one to imitate the other:

- **Android** gets a completion callback *per write* (`onCharacteristicWrite`, even for no-response) and its stack permits **one op in flight**. So `GattOpQueue` is a unified, serial, advance-on-callback queue with a per-op timeout.
- **iOS** gets **no per-write callback** for WriteNoResponse — only a batch gate (`canSendWriteWithoutResponse`) plus a single `peripheralIsReady` re-pump. So the natural shape is **drain-while-the-gate-is-open**, which is exactly what iOS already does for notifications (`PendingNotificationQueue`).

The right consistency axis is therefore **intra-platform**: `PendingWriteQueue` is a twin of `PendingNotificationQueue`. Cross-platform understanding is bridged by **cross-reference doc comments** on all three types (`GattOpQueue` ↔ `PendingWriteQueue` ↔ `PendingNotificationQueue`) that name the analogy and explain why the concurrency models differ (per-op callback vs batch gate). Vocabulary is aligned where it can be (`enqueue`, `gatt-disconnected`); the iOS types keep `failAll` (their existing name) over Android's `drainAll`, with the doc comment mapping the two.

## Out of scope

- **Option B — exposing `canSendWriteWithoutResponse` / a "queue drained" event to Dart consumers** for their own pacing. Fix A makes the default correct; B is an advanced add-on, deferred until a concrete consumer needs to do its own throttling. (A and B compose later.)
- **iOS peripheral-role `notifyTo` write back-pressure** (`peripheralManagerIsReadyToUpdateSubscribers:` is already handled for broadcast notify by I040; per-central `notifyTo` saturation is a distinct item).
- **Android.** Its GATT central already enforces this via the serialized `GattOpQueue` + `onCharacteristicWrite` completion. No change.
- **Prepared-write / long-write (I050).** Distinct surface (reassembly on top of with-response writes).
- **Throughput tuning / payload sizing.** Once flow control is in place, `maxWritePayload` becomes a safe ceiling rather than a hazard.

## Testing & verification

The fix is native Swift, but it is **not** dogfood-only: `bluey_ios` already has an XCTest harness (`bluey_ios/example/ios/RunnerTests/`) where the direct prior art — `PendingNotificationQueueTests.swift` (I040's drain) and `OpSlotTests.swift` (the with-response slot) — is thoroughly unit-tested. Extracting `PendingWriteQueue` as a closure-driven type (above) makes the flow-control logic unit-testable the same way. TDD applies.

1. **XCTest unit tests for `PendingWriteQueue`** (TDD red→green; mirror `PendingNotificationQueueTests.swift`), covering at least:
   - drain while `send` returns true completes-success every entry in order, empties the queue;
   - `send` returns false from the start (gate shut) → entry stays queued, completion does **not** fire;
   - `send` returns false mid-drain (gate shuts partway) stops and preserves the tail in order;
   - re-drain after a partial drain resumes from the head (the `peripheralIsReady` re-pump path);
   - `failAll(error:)` fires `.failure` for every pending entry and empties (the disconnect path);
   - `enqueue` returns false at cap (leaves the entry out; caller fires its own failure) — mirroring `PendingNotificationQueue`.

   (Same matrix as `PendingNotificationQueueTests.swift`, minus its `failEntries(matching:)` case unless a need surfaces.)
2. **Real-device dogfood** — *confirmation* of the wiring end-to-end. Re-run the corruption scenario in `gossip_chat`, iPhone (central) ↔ Pixel 6a (peripheral): induce a ≥10 s isolate hang (e.g. the keyboard XPC reconnect via the QR-scan flow), then confirm:
   - no `}]}GS`-tail `Malformed gossip message` / `frame decoder recovered from corruption` events on the Android side after the burst;
   - the iOS-central → Android-peripheral data path keeps working after the hang (typing/messages from iOS continue to land on Android — no permanent one-way degradation);
   - normal (non-burst) writes are unaffected.
3. A clean `flutter analyze` on the Dart side (the change should not touch Dart — a no-regression check).

**Execution note.** Running the XCTest target needs `xcodebuild` (available) + a simulator + the example iOS build (CocoaPods + `flutter assemble`). That may be a CI / developer-Mac step rather than this sandbox; the tests are nonetheless real, runnable unit tests (red→green), not a dogfood substitute.

## Implementation footprint

- `bluey_ios/ios/Classes/PendingWriteQueue.swift` (**new**): the standalone, closure-driven FIFO/drain/`failAll` type — interface twin of `PendingNotificationQueue.swift`. Doc comment cross-references `PendingNotificationQueue` (iOS sibling) and Android's `GattOpQueue` (the per-op-callback analog), explaining the batch-gate-vs-serial difference.
- `bluey_ios/example/ios/RunnerTests/PendingWriteQueueTests.swift` (**new**): the XCTest unit suite (above), modeled on `PendingNotificationQueueTests.swift`.
- `bluey_ios/ios/Classes/CentralManagerImpl.swift`: hold one `PendingWriteQueue` per `deviceId`; rewrite the `.withoutResponse` branch of `writeCharacteristic` to `enqueue` + `pump`; add `pump(deviceId:)` wiring `canSendWriteWithoutResponse` / `writeValue`; add the `peripheralIsReady(toSendWriteWithoutResponse:)` delegate; call `failAll(error:)` from the existing `clearPendingCompletions(for:error:)` (the `didDisconnectPeripheral` cleanup), beside the existing `writeCharacteristicSlots…drainAll`. The `.withResponse` (`OpSlot`) path is untouched.
- **Doc-comment cross-references** added to `bluey_ios/ios/Classes/PendingNotificationQueue.swift` and `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt` pointing at the other two, so the Android↔iOS mapping is discoverable from any of the three.
- No Pigeon, platform-interface, domain, or Android *logic* changes (the `GattOpQueue.kt` edit is a doc comment only).
