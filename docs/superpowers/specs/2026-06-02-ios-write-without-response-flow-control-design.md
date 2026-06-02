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

The FIFO/drain is a **standalone, unit-testable type** — `PendingWriteQueue` — mirroring the existing `PendingNotificationQueue` (I040) and `OpSlot` (with-response writes). It depends on **injected closures**, not a live `CBPeripheral`, so its logic is testable in isolation:

```
internal final class PendingWriteQueue {
    struct Entry { let characteristic: CBCharacteristic; let data: Data; let completion: (Result<Void, Error>) -> Void; /* + timeout token */ }
    func enqueue(_ entry: Entry)
    func drain(canSend: () -> Bool, send: (Entry) -> Void)   // pops + sends + completes(success) while canSend() && non-empty
    func failAll(_ error: Error)                              // disconnect: fail every pending completion, empty the queue
    // per-entry timeout fires completion(.failure(gatt-timeout)) and removes the entry
}
```

`CentralManagerImpl` holds one `PendingWriteQueue` per `deviceId` and wires the real CoreBluetooth surface into it:

1. `writeCharacteristic(... withResponse: false)` → `queue.enqueue(...)` then `pump(deviceId)`. The `.withResponse` branch (the existing `OpSlot` path) is untouched.
2. `pump(deviceId)` calls `queue.drain(canSend: { peripheral.canSendWriteWithoutResponse }, send: { peripheral.writeValue($0.data, for: $0.characteristic, type: .withoutResponse) })`.
3. The new delegate `peripheralIsReady(toSendWriteWithoutResponse: CBPeripheral)` re-pumps that peripheral's queue when the gate reopens.
4. The disconnect/cleanup path calls `queue.failAll(notConnected)`.

The queue owns the FIFO, completion, and timeout logic (testable); the manager owns only the thin wiring of CoreBluetooth's `canSendWriteWithoutResponse` / `writeValue` / `peripheralIsReady` / disconnect into it (dogfood-confirmed).

### Completion semantics — complete-on-hand-off (Android parity)

The Dart `write()` Future resolves only when the write is actually handed to CoreBluetooth (drained), **not** on enqueue. When the gate is closed the completion is held and fires when the drain reaches it. This is identical to Android's `GattOpQueue`, which completes a write op only on `onCharacteristicWrite` and serializes one op at a time.

Consequence — automatic backpressure: a serial consumer that `await`s each write (e.g. gossip's `_sendQueue`) caps outstanding writes at ~1, so the FIFO stays at ~1 entry and never floods. This is the property that prevents the saturation in the first place. The observable behavior change — a `write()` Future taking longer to resolve under saturation — is the intended signal that the link is busy.

### Edge handling (matches Android's `GattOpQueue`)

| Case | Behavior | Android analog |
|---|---|---|
| Peripheral disconnects mid-burst | Fail all pending WnR completions for that `deviceId` with `notConnected`; clear the FIFO. Hung off the existing disconnect/cleanup handler. | `GattOpQueue.drainAll(reason)` |
| Write can't drain (gate stays closed) | Per-write timeout reusing `writeCharacteristicTimeout` (10 s) → fail with `gatt-timeout`. Prevents a never-reopening gate from hanging a consumer's `await` forever. | per-op `postDelayed(timeout, op.timeoutMs)` |
| Fast producer | No FIFO cap. Serialization + per-write timeout + disconnect-drain are the safety nets. | unbounded `ArrayDeque` |

- **Timeout start point:** the timer starts when the write is appended to the FIFO. Under fix A + a serial consumer the FIFO sits at ~1, so enqueue ≈ head and this is effectively equivalent to Android's "timer starts when in-flight."
- **Scope of the FIFO:** WriteNoResponse-specific, alongside the existing per-op-type structures (`OpSlot` for with-response, etc.). This is **not** a unified op queue like Android's — CoreBluetooth gates WnR independently of with-response acks, so a dedicated FIFO is correct and keeps the change scoped.

## Out of scope

- **Option B — exposing `canSendWriteWithoutResponse` / a "queue drained" event to Dart consumers** for their own pacing. Fix A makes the default correct; B is an advanced add-on, deferred until a concrete consumer needs to do its own throttling. (A and B compose later.)
- **iOS peripheral-role `notifyTo` write back-pressure** (`peripheralManagerIsReadyToUpdateSubscribers:` is already handled for broadcast notify by I040; per-central `notifyTo` saturation is a distinct item).
- **Android.** Its GATT central already enforces this via the serialized `GattOpQueue` + `onCharacteristicWrite` completion. No change.
- **Prepared-write / long-write (I050).** Distinct surface (reassembly on top of with-response writes).
- **Throughput tuning / payload sizing.** Once flow control is in place, `maxWritePayload` becomes a safe ceiling rather than a hazard.

## Testing & verification

The fix is native Swift, but it is **not** dogfood-only: `bluey_ios` already has an XCTest harness (`bluey_ios/example/ios/RunnerTests/`) where the direct prior art — `PendingNotificationQueueTests.swift` (I040's drain) and `OpSlotTests.swift` (the with-response slot) — is thoroughly unit-tested. Extracting `PendingWriteQueue` as a closure-driven type (above) makes the flow-control logic unit-testable the same way. TDD applies.

1. **XCTest unit tests for `PendingWriteQueue`** (TDD red→green; mirror `PendingNotificationQueueTests.swift`), covering at least:
   - drain while `canSend` stays true sends + completes-success every entry in order, empties the queue;
   - `canSend` false from the start → entry stays queued, completion does **not** fire;
   - partial drain (`canSend` flips false mid-drain) stops and preserves the tail in order;
   - re-drain after a partial drain resumes from the head (the `peripheralIsReady` re-pump path);
   - `failAll` fires `.failure(notConnected)` for every pending entry and empties (the disconnect path);
   - per-entry timeout fires `.failure(gatt-timeout)` and removes that entry;
   - no cap (unbounded) — large enqueue then full drain completes all.
2. **Real-device dogfood** — *confirmation* of the wiring end-to-end. Re-run the corruption scenario in `gossip_chat`, iPhone (central) ↔ Pixel 6a (peripheral): induce a ≥10 s isolate hang (e.g. the keyboard XPC reconnect via the QR-scan flow), then confirm:
   - no `}]}GS`-tail `Malformed gossip message` / `frame decoder recovered from corruption` events on the Android side after the burst;
   - the iOS-central → Android-peripheral data path keeps working after the hang (typing/messages from iOS continue to land on Android — no permanent one-way degradation);
   - normal (non-burst) writes are unaffected.
3. A clean `flutter analyze` on the Dart side (the change should not touch Dart — a no-regression check).

**Execution note.** Running the XCTest target needs `xcodebuild` (available) + a simulator + the example iOS build (CocoaPods + `flutter assemble`). That may be a CI / developer-Mac step rather than this sandbox; the tests are nonetheless real, runnable unit tests (red→green), not a dogfood substitute.

## Implementation footprint

- `bluey_ios/ios/Classes/PendingWriteQueue.swift` (**new**): the standalone, closure-driven FIFO/drain/`failAll`/timeout type, modeled on `PendingNotificationQueue.swift`.
- `bluey_ios/example/ios/RunnerTests/PendingWriteQueueTests.swift` (**new**): the XCTest unit suite (above), modeled on `PendingNotificationQueueTests.swift`.
- `bluey_ios/ios/Classes/CentralManagerImpl.swift`: hold one `PendingWriteQueue` per `deviceId`; rewrite the `.withoutResponse` branch of `writeCharacteristic` to `enqueue` + `pump`; add `pump(deviceId:)` wiring `canSendWriteWithoutResponse` / `writeValue`; add the `peripheralIsReady(toSendWriteWithoutResponse:)` delegate; call `failAll(notConnected)` from the existing disconnect/cleanup path. The `.withResponse` (`OpSlot`) path is untouched.
- No Pigeon, platform-interface, domain, or Android changes.
