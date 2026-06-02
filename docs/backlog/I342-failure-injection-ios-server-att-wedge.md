---
id: I342
title: Failure-injection stress test wedges the ATT channel on an iOS server; client writes cascade as opaque `bluey-unknown`
category: bug
severity: low
platform: both
status: open
last_verified: 2026-06-02
related: [I087, I319, I338]
---

> **Note.** Originally drafted as I323 on a since-stale branch during the I338
> dogfood; renumbered to **I342** because I323 was assigned to a different
> issue (`connectAsPeer` GAP-role detection) in the interim.

## Symptom

Running the **failure-injection** stress test with **iOS as the server** and **Android as the client**:

- Each run of 10 echo writes produces **one** `GattTimeoutException` (expected — the deliberately-dropped first write) followed by a **variable cascade** of `BlueyPlatformException(bluey-unknown)` for the remaining writes.
- Success counts swing wildly run-to-run with no code change — e.g. 6/10, 7/10, **0/10**, 5/10.

Confirmed reproducible on `main` (i.e. **not** introduced by the I338 Stage 2–3 eviction work; the I338 branch was being dogfooded when this surfaced).

## Location

- `bluey/example/lib/features/stress_tests/.../stress_service_handler.dart` — the drop handler sets `_dropNextWrite` and then `return`s **without** calling `respondToWrite` for the next write.
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift` `didReceiveWrite` — CoreBluetooth requires exactly one `peripheralManager.respond(to:)` per `CBATTRequest`; the dropped write is never answered.
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt` + `Errors.kt` — when the Android stack is busy, `gatt.writeCharacteristic()` returns `false` → `IllegalStateException("Failed to write characteristic")` → translated to the opaque `bluey-unknown` (no typed "operation rejected / busy" error).

## Root cause

ATT is a **strictly sequential** protocol — one outstanding request per connection. The stress test's "drop" works by having the server never respond to the write, so the `CBATTRequest` stays un-acked and the **ATT channel stays busy until the stack-level timeout (~30 s)** — far longer than bluey's 10 s per-op timeout.

On the Android client:
1. Write #1 hits bluey's 10 s op timeout → surfaces `GattTimeoutException`; bluey's op queue advances.
2. But the underlying Android stack still has write #1's ATT transaction outstanding (the server never acked), so write #2's `gatt.writeCharacteristic()` returns `false` (channel busy) → `bluey-unknown`.
3. This repeats for the rest of the burst until the stack-level ATT timeout frees the channel, after which later writes can succeed again.

The run-to-run variance is timing-dependent recovery of the wedged channel (0/10 when it never clears within the window; 6–7/10 when it clears partway).

Two distinct facets:

1. **Stress-test design.** Dropping a *write-with-response* by going silent inherently wedges ATT on **any** server. Against an iOS server it manifests as this `bluey-unknown` cascade. (This is the role-reversed sibling of **I087**, the iOS-client → Android-server case, where the dropped write instead trips the heartbeat-failure → peer-unreachable → disconnect path and was resolved as wontfix.)
2. **Library ergonomics.** The Android client reports a stack-busy `writeCharacteristic() == false` as the opaque `bluey-unknown` rather than a typed "operation rejected / busy" error — the same opacity theme as **I319** (advertise failures collapsing to `bluey-unknown`).

## Notes

**Explicitly not I338.** The failure happens at client write-*initiation*, before any server response is relevant, so the I338 eviction status (`0x80`) never enters the picture; and the eviction gate only rejects requests from clients with **no established session**, whereas this client is fully connected. Confirmed by `main` reproducing the same pattern.

**Fix sketch (separate change off `main`):**
- Make the failure-injection drop use a **write-without-response** (no ATT ack expected → no wedge), or have the drop **respond with an error status** so the ATT transaction completes (frees the channel) without delivering a "real" success/notification.
- Optionally introduce a typed busy/rejected error on the Android client for the `writeCharacteristic() == false` (and the sibling read/MTU/discover) sync-failure paths, instead of the catch-all `bluey-unknown` (cf. I319).

Surfaced during the I338 dogfood (Task 4.2). The failure-injection test does **not** exercise the I338 eviction path.
