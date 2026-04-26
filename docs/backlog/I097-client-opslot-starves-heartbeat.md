---
id: I097
title: Client-side OpSlot starvation causes false-positive heartbeat failures
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-04-26
fixed_in: 8f8a5a9
related: [I079, I087, I077]
---

## Symptom

Running the **failure-injection** stress test on iOS-client → Android-server with `maxFailedHeartbeats=5` ("Very tolerant") still produces a disconnect after 2 visible `GattTimeoutException`s, despite the heartbeat-failure threshold of 5. The same scenario at `maxFailedHeartbeats=1` produces a disconnect after just 1 timeout.

Server-side instrumentation confirms only one write is dropped (the test's intended `DropNextCommand` target). Server log also shows **no heartbeat writes during the test window** — heartbeats schedule on the iOS client but never reach the server.

## Location

- `bluey_ios/ios/Classes/CentralManagerImpl.swift` — `OpSlot` serialization across all GATT ops, including heartbeats.
- `bluey/lib/src/connection/lifecycle_client.dart:236-309` — `_sendProbe` treats any `GattOperationTimeoutException` as a dead-peer signal via `_isDeadPeerSignal`, regardless of whether the timeout originated on the wire (server didn't answer) or in the local OpSlot queue (op never went on the wire).

## Root cause

Mirror image of [I079](I079-lifecycle-heartbeat-starves-behind-long-user-ops.md), but on the client side rather than the server side.

iOS's `OpSlot` serializes all client-initiated GATT operations on a connection — user writes, reads, and heartbeat probes share one slot. When a user op stalls (e.g., echo #0 in failure-injection: server drops the response, OpSlot holds the request for the per-op timeout), the heartbeat probe scheduled during that window queues behind the stalled user op.

When the user op times out at the OpSlot per-op timeout, the queued heartbeat probe times out too — without ever going on the wire. From `LifecycleClient._sendProbe`'s perspective, that timeout looks identical to "we sent the heartbeat and the peer didn't respond." The dead-peer counter increments. With `maxFailedHeartbeats` low enough relative to how many heartbeats queue and time out per stalled user op, the threshold trips and the client tears down the connection — even though the peer was healthy and answering everything that actually reached it.

The wider the `maxFailedHeartbeats` window, the more user-op stalls before the disconnect, but the disconnect still happens because heartbeats keep accumulating starvation-failures faster than they accumulate successes.

## Why this surfaced post-I079 / post-I096

Pre-I079, the **server** declared the client gone first (heartbeat starvation false-positive on the server side). Post-I079, the server stays patient. Post-I096, the disconnect cascade is well-typed. The remaining "client gives up" behaviour is now this client-side mirror, which the failure-injection test reliably reproduces.

The example app's tolerance setting (introduced 2026-04-26) was originally intended to demonstrate "low tolerance → disconnect, high tolerance → recovery." It does the first half — low tolerance reaches the threshold faster. It doesn't deliver the second half: even at tolerance=5, the disconnect still happens because the underlying starvation isn't bounded by the tolerance value.

## Notes

Fixed in `8f8a5a9` by switching from count-based (`maxFailedHeartbeats: int`) to time-based (`peerSilenceTimeout: Duration`) detection, with three coordinated changes:

1. **`PeerSilenceMonitor`** (renamed from `LivenessMonitor`) — wall-clock death watch keyed off the *first* unrecovered failure. Subsequent failures while the watch is armed do not push the deadline out; only a successful exchange cancels it. So OpSlot-starved heartbeats can no longer drive a runaway counter — the deadline is fixed once tripped.

2. **Defer probes during user-op pendency.** `LifecycleClient` tracks in-flight user ops via `markUserOpStarted` / `markUserOpEnded`. While `_pendingUserOps > 0`, scheduled probes defer rather than queue behind the user op in the OpSlot. The in-flight user op is itself an outstanding peer probe — its outcome will tell us about the peer's liveness.

3. **User-op timeouts feed the silence detector.** `BlueyConnection`'s GATT call sites wrap each user op with start/end accounting and route platform timeout exceptions into `LifecycleClient.recordUserOpFailure`, which arms the same death watch a heartbeat-probe timeout would. So the failure signal is now "any op we expected an answer to didn't get one within the silence window" rather than "N heartbeats in a row failed locally".

Subsequent on-device verification (this conversation, 2026-04-26) confirmed the fix delivers what was promised — heartbeats no longer starve behind user ops — but also surfaced a separate *platform* limit unrelated to I097: the Bluetooth Core Spec (Vol 3 Part F §3.3.3) caps an unacknowledged ATT transaction at 30 seconds, after which the bearer is dead and a new one must be established. CoreBluetooth implements this strictly; Android's stack is more permissive. So the **failure-injection** "tolerant recovery" path is reachable on Android-client but not iOS-client — the platform pulls the bearer at ~30 s before any reasonable `peerSilenceTimeout` would let recovery happen. This is now reflected in the failure-injection help text and is **not** a residual I097 bug; it's a candidate for a future cross-platform consistency project (transparent ATT-bearer reset at the Peer layer).
