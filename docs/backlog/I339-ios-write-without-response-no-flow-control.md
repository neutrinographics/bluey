---
id: I339
title: iOS `writeValue(...type: .withoutResponse)` is fire-and-forget — no `canSendWriteWithoutResponse` gate, no `peripheralIsReady` drain — causing silent drops / merged writes under burst
category: bug
severity: high
platform: ios
status: fixed
last_verified: 2026-07-06
fixed_in: d8277b7
related: [I050, I338]
---

## Symptom

When a central-role iOS app emits many `WriteNoResponse` writes in rapid
succession — typically after the Dart isolate unblocks from a hang and
flushes a backlog of queued sends — the bytes that arrive at the
peripheral are no longer reliably a faithful 1:1 reconstruction of the
sent stream. Consumers that frame messages on top of the GATT data
characteristic see one or both of:

1. **Frame length-prefix off by 2.** The decoder reads the 4-byte
   big-endian length from a frame, reads that many "payload" bytes, and
   the JSON parser at the next layer fails on the trailing 2 bytes — which
   reliably turn out to be the *first two bytes of the next frame's magic
   prefix*. Pattern: `…valid-JSON…}]}GS` where `GS` is `0x47 0x53`, the
   leading bytes of `GSP1`.
2. **Subsequent corruption-recovery skips of plausible-frame-sized
   chunks** (consistently in the 400–500 byte range — i.e. ~1 frame's
   worth of bytes) repeating every few seconds for tens of seconds after
   the burst.

Reproduced 2026-06-01 in the `gossip_chat` dogfood app, iPhone ↔ Pixel
6a. Bluey was on branch `i338-stage2-eviction` (HEAD `6b0f0ff`) — i.e.
with the full I338 fix landed — confirming this is **not** a manifestation
of the I338 phantom-disconnect path. Stage 1's "advisory only on
Android" behavior is observable in the same Android log (no
`central disconnected`, no `Peer disconnected` for the iOS peer); the
consumer-side frame decoder is **never torn down**. Corruption
nonetheless appears immediately following the burst.

Timeline:

```
iOS (central, peripheral-role on Pixel 6a):
  15:06:33  steady-state heartbeats, sending small (71–73 byte) writes.
  15:06:33–15:06:44   Dart isolate hung (`Hang detected: 10.72s
                       (debugger attached, not reporting)`). No
                       writeValue calls during this window. The
                       in-app send-queue (gossip_bluey
                       ConnectionService._sendQueue) accumulates
                       sends.
  15:06:44.296   isolate resumes. Lifecycle heartbeat goes first.
  15:06:44.345 → 15:06:44.430   25+ `writeValue(.withoutResponse)`
                       calls in <100 ms, each 366 bytes — the queue
                       flush. Sizes later climb to 384, 448, and
                       514 bytes as additional buffered messages
                       roll out.

Android (peripheral, GATT server):
  15:06:43.306  `bluey.server.lifecycle: client gone` (advisory; no
                 disconnect emitted — Stage 1 working).
  15:06:43.847+  Android still happily emitting notifications back
                 to the iOS client throughout (decoder + identification
                 intact).
  15:06:47.148  First `Malformed gossip message ... FormatException:
                 Unexpected character (at character 766)` — payload tail
                 `…}]}GS`.
  15:06:47.314  `frame decoder recovered from corruption ... discarded
                 405 bytes`.
  15:06:48.692 → 15:06:59.069  Six further recovery events. Discarded
                 byte counts: 446, 69, 446, 444, 446 — all roughly
                 one frame's worth.
  15:06:53.595  SWIM begins re-failing probes (Probe FAILED count 0→1):
                 the application-level effect is that the byte stream
                 from iOS is now lossy enough that gossip's own probes
                 start timing out.
```

The pattern reliably reproduces whenever the iOS isolate stalls for
long enough to accumulate ≥ ~10 framed sends that then dispatch as a
burst. A 10–12 s hang is on the high side of normal but absolutely a
real condition — the dogfood hang here was caused by the iOS remote
keyboard XPC reconnect after the QR-scan flow, which is observable
behavior on any user device.

### Update 2026-06-02: the desync is PERMANENT, not transient

Second dogfood run (post-I338 Pattern B, `bluey` HEAD `a8a807d`) with
the same scenario (iOS keyboard XPC reconnect → 16.07 s `Hang detected`)
reproduces the corruption and reveals a worse property: **the
misalignment never self-heals.** Confirmed by the consumer: 10+ minutes
after the burst, iOS's frames remain unparseable on Android with the
identical `}]}GS` tail signature; Android-as-server receives nothing
useful from this iOS client until something forces a fresh GATT session
(disconnect/reconnect, app restart, BT adapter cycle). The frame
decoder's scan-forward recovery does fire on each corrupt frame and
"succeeds" in the sense that it lands on a subsequent magic — but every
*next* frame iOS produces inherits the same defect, so the recovery
never finds a sustained good-stream-tail to lock back on.

What this means in practice:

- A single `Hang detected` event past ~10 s permanently dead-ends the
  iOS-as-central → Android-as-peripheral data path for that GATT
  session. The bidirectional behavior degrades to one-way (Android →
  iOS still works, because the inverse path uses `notify(...)` plus
  `peripheralManagerIsReadyToUpdateSubscribers:` flow control — already
  correct, see I040).
- Application-layer observable: in `gossip_chat`, typing indicators and
  messages typed on Android land on iOS; typing indicators and messages
  typed on iOS never reach Android. Users perceive this as a one-way
  connection that "won't go away" — no error UI, just silent
  unidirectional drop.
- Severity of consumer impact is closer to a **persistent connection
  fault** than a "burst-corruption" event. Without a forced
  disconnect/reconnect (which the Pattern B I338 fix now correctly
  *avoids*, by design — heartbeat silence is no longer a disconnect),
  the GATT link stays up indefinitely, broken.

### Why the desync persists (mechanism sketch)

The corruption tail is consistently the first 2 bytes of the next
frame's magic prefix (`G`, `S` = `0x47 0x53`). The decoder reads
`length = N` from the prefix, reads N bytes, and the JSON parser finds
`}]}` (valid JSON tail) followed by `GS` (junk). The most parsimonious
read of this is: the wire bytes for frame F1 are interleaved or
reordered with the bytes for F2 such that F1's apparent payload
contains F2's magic head. Two candidate root causes:

1. **CoreBluetooth's `WriteWithoutResponse` queue, under burst, will
   coalesce or partially-deliver writes.** This is documented Apple
   behavior for the case where `canSendWriteWithoutResponse == false`
   and the caller pushes anyway: writes "may be silently dropped or
   coalesced." Coalescing two adjacent `writeValue` payloads with no
   delimiter, where the payloads each begin with a `GSP1` magic, would
   produce exactly this byte pattern on the wire from Android's GATT
   server's perspective.
2. **CoreBluetooth's internal write-queue state remains permanently
   degraded** after a saturation event until the peripheral connection
   is torn down. Other reports of similar `writeValue
   .withoutResponse` foot-guns on iOS describe "the queue is poisoned
   until reconnect." A flow-control gate via
   `canSendWriteWithoutResponse` +
   `peripheralIsReady(toSendWriteWithoutResponse:)` is exactly the
   prophylaxis Apple's API provides to keep the queue from entering
   this state.

Either way, the fix surface is the same: implement the
`canSendWriteWithoutResponse` gate + `peripheralIsReady` drain. If the
queue can be kept from saturating in the first place, neither root
cause has the chance to fire.

## Root cause

`bluey_ios/ios/Classes/CentralManagerImpl.swift:329–353` implements
characteristic writes from the central role:

```swift
let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse

if withResponse {
    let cacheKey = characteristic.uuid.uuidString.lowercased()
    let slot = writeCharacteristicSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<Void>()
    writeCharacteristicSlots[deviceId, default: [:]][cacheKey] = slot
    slot.enqueue(
        completion: completion,
        timeoutSeconds: writeCharacteristicTimeout,
        makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Write characteristic timed out", details: nil)
    )
}

peripheral.writeValue(value.data, for: characteristic, type: type)

if !withResponse {
    completion(.success(()))
}
```

The `.withoutResponse` branch:

1. **Calls `writeValue` unconditionally**, without first consulting
   `peripheral.canSendWriteWithoutResponse`. Apple's `CBPeripheral`
   documentation is explicit that this property is the gate for
   `WriteNoResponse` correctness: "If `canSendWriteWithoutResponse`
   is `false`, additional `writeValue:forCharacteristic:type:` calls
   that pass `CBCharacteristicWriteWithoutResponse` may be silently
   dropped or coalesced by the system. Wait for
   `peripheralIsReady(toSendWriteWithoutResponse:)` before the next
   call."
2. **Returns success immediately** (`completion(.success(()))`), so
   every higher layer believes the write reached the peer. There is
   no Dart-visible signal that any byte ever left the device.
3. **Implements no `peripheralIsReady(toSendWriteWithoutResponse:)`
   delegate method.** A grep over the file shows handlers for
   `didUpdateValueFor`, `didWriteValueFor`, `didModifyServices`,
   `didUpdateNotificationStateFor` — but none for the
   `peripheralIsReady` flow-control callback.

Net effect: under burst conditions, some `writeValue` calls hit
CoreBluetooth while its `WriteNoResponse` queue is full. Apple's
implementation is allowed (and does, observably) to merge or drop
those writes. The bluey caller has no idea this happened — the slot
already returned success — so the Dart-level frame encoder continues
to advance the byte stream as if every byte landed.

This is symptomatic of the same class of foot-gun that motivated I050
(prepared-write unimplemented) and that I040 fixed for the
notification path — `peripheralIsReady` flow-control is not optional
on iOS for high-throughput WriteNoResponse, and bluey's current
implementation pretends it is.

## Why this surfaces only post-I338

Pre-I338, a lifecycle-silence event tore down the consumer-side frame
decoder (`gossip_bluey`'s
`ConnectionService._decoders.remove(nodeId)`) on the same code path,
masking the symptom: any in-flight bytes lost during the burst were
attributed to "decoder was reset, will resync." With I338 Stage 1
landed, the decoder *is not* reset, so the underlying wire-integrity
problem is now directly observable. The corruption magnitudes and
recovery patterns match pre-I338 almost byte-for-byte (405, 446, 69,
446, 444, 446 bytes discarded) — confirming this was the same
underlying mechanism, previously hidden behind a different bug.

## Why this is a bluey bug

The `MessagePort` / `Connection.write(...)` API is presented as a
reliable byte-stream channel from the consumer's perspective: every
successful call's bytes are expected to reach the peer in order, or
fail. For `.withoutResponse` writes, bluey on iOS today does not honor
that contract: it returns success but does not guarantee delivery
even when CoreBluetooth has all the information needed to provide
that guarantee via `canSendWriteWithoutResponse` +
`peripheralIsReady(...)`.

There is no API surface that lets a consumer participate in the
flow-control loop themselves. The consumer cannot ask "did the bytes
actually leave the device?" or "is the queue saturated, should I
pause?" The only mechanism Apple offers is on the CoreBluetooth side
of the Pigeon boundary, where bluey is and is not using it.

## Proposed fix

### A. Implement `peripheralIsReady` flow control inside `CentralManagerImpl` (preferred)

Maintain a per-peripheral FIFO of pending WriteNoResponse payloads.
Drain it whenever `peripheral.canSendWriteWithoutResponse` is true,
and refill the pump from the `peripheralIsReady(toSendWriteWithoutResponse:)`
delegate callback.

Sketch:

```swift
final class CentralManagerImpl: NSObject, CBPeripheralDelegate {
    // ...

    /// Per-peripheral FIFO of (characteristic, payload, completion) for
    /// writeNoResponse calls that have been throttled by Apple's
    /// `canSendWriteWithoutResponse` gate. Drained either:
    /// - immediately on the writeValue entry path when the gate is open,
    /// - from `peripheralIsReady(toSendWriteWithoutResponse:)` when the
    ///   gate flips back open.
    private var pendingWriteNoResponse: [String: [PendingWnR]] = [:]

    private struct PendingWnR {
        let characteristic: CBCharacteristic
        let data: Data
        let completion: (Result<Void, Error>) -> Void
    }

    func writeCharacteristic(
        deviceId: String,
        characteristic: CBCharacteristic,
        value: FlutterStandardTypedData,
        withResponse: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // ... withResponse branch unchanged ...

        // .withoutResponse:
        let pending = PendingWnR(
            characteristic: characteristic,
            data: value.data,
            completion: completion
        )
        pendingWriteNoResponse[deviceId, default: []].append(pending)
        drainWriteNoResponse(deviceId: deviceId, peripheral: peripheral)
    }

    private func drainWriteNoResponse(deviceId: String, peripheral: CBPeripheral) {
        while peripheral.canSendWriteWithoutResponse,
              var queue = pendingWriteNoResponse[deviceId],
              !queue.isEmpty {
            let head = queue.removeFirst()
            pendingWriteNoResponse[deviceId] = queue
            peripheral.writeValue(head.data, for: head.characteristic, type: .withoutResponse)
            head.completion(.success(()))
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        drainWriteNoResponse(deviceId: deviceId, peripheral: peripheral)
    }

    // ... on disconnect, drain any pending with .failure(.notConnected).
}
```

Notes:

- The `completion(.success(()))` still fires synchronously from the
  consumer's perspective (Pigeon round-trip), but only after the write
  has actually been handed to CoreBluetooth — not after it has been
  queued in `pendingWriteNoResponse`. A consumer chaining writes (which
  gossip_bluey does, via `_sendQueue`) will naturally cap its
  outstanding-write count, because each `await` won't return until the
  Pigeon call returns, and the Pigeon call won't return until the
  flow-control loop has had its turn.
- Alternative: complete on enqueue, drain in background. Simpler
  semantically (writes are "accepted") but lets the consumer pile up
  bytes in the Swift FIFO unboundedly during a slow drain. Pick the
  first option unless there's a strong reason to expose the queue
  separately.
- Cleanup on disconnect needs to drop pending writes and fail their
  completions, otherwise a peripheral that disappears mid-burst leaves
  stuck callbacks. The cleanup path can hang off the existing
  disconnection handler.

### B. Add `peripheralIsReady` semantics to the public Connection API

Expose `canSendWriteWithoutResponse` on `Connection` (Dart side) and a
matching stream of "queue drained" events, so consumers can implement
their own pacing if they prefer. This is non-breaking but pushes
correctness onto every consumer. Apple's CoreBluetooth documentation
treats `canSendWriteWithoutResponse` as the contract; if bluey is going
to surface CoreBluetooth's primitives faithfully it should arguably
expose this too. But option A is the right *default* — consumers
shouldn't have to know about this to avoid silent data loss.

A and B compose: do A so the default is correct; consider adding B
later for advanced consumers that want to do their own throttling.

### Out of scope

- Per-peripheral throughput tuning (write batching, payload sizing).
  Once flow control is in place, `maxWritePayload` becomes a safe
  ceiling rather than the hazard it is today.
- iOS peripheral-role / `notifyTo` write back-pressure. The peripheral
  side has its own analogous problem
  (`peripheralManagerIsReadyToUpdateSubscribers:`) — distinct enough to
  warrant its own item.
- The Android side. Android's GATT central does enforce ATT-level
  back-pressure natively (the BluetoothGattCallback fires
  `onCharacteristicWrite` for `WriteNoResponse`-equivalent at the
  Java layer); this issue is iOS-specific to start with.

## Why severity is high

- **Silent.** No log, no exception, no warning. The consumer believes
  every byte was delivered. The frame decoder on the peer side eats the
  corruption and "recovers" — meaning the wire-level loss is invisible
  unless you happen to be looking for `frame decoder recovered from
  corruption` warnings.
- **Permanent for the GATT session.** Per the 2026-06-02 dogfood
  update above, a single qualifying hang dead-ends the iOS-as-central
  → peer-as-peripheral data path for the *lifetime of the GATT link*.
  The link does not self-heal. Combined with I338 Pattern B — which
  (correctly) no longer disconnects on heartbeat silence — the
  application sees a persistent half-broken connection with no
  built-in recovery path. This pushes severity from "transient
  throughput degradation" to "persistent connection fault."
- **Triggered by routine iOS behavior.** Any Dart isolate stall ≥ a
  few hundred ms (keyboard XPC reconnect, image decode, large JSON
  parse, GC pause, debugger pause) is a candidate. Real apps stall.
- **Throughput-bound — affects every protocol that frames messages
  larger than a single ATT write or sends bursts.** Gossip is one
  example; any future consumer doing chunked transfers, file sync,
  log shipping etc. will hit this.
- **No workaround at the consumer layer that doesn't sacrifice
  throughput.** Capping `chunkSizeFor` to something tiny (≈ 100 bytes)
  reduces the burst-of-large-writes risk but adds per-frame overhead
  on every operation, healthy or not.

## Notes

- `bluey_ios/ios/Classes/CentralManagerImpl.swift:797–814`
  (`didWriteCharacteristicValue`) already correctly handles the
  `.withResponse` side via `OpSlot`. The fix here is the missing
  parallel structure for `.withoutResponse`.
- I050 (prepared-write flow unimplemented) is a related but distinct
  surface — it covers long-write reassembly on top of standard
  `withResponse` writes, which is its own can of worms. Address this
  one first; the `.withoutResponse` path is by far the more common
  carrier of bulk data.
- I040 fixed the analogous issue on the *notification* side
  (`peripheralManagerIsReadyToUpdateSubscribers:` queue draining for
  outbound notifications from iOS-as-peripheral). The same shape of
  fix applies here, on the central-write side. Worth reading I040 for
  prior art on the Apple API contract.
- Confirmed during dogfood that the frame-decoder corruption pattern
  is byte-for-byte the same as pre-I338, post-I337 — i.e. it is
  reproducible and stable, not a flaky environmental issue.
