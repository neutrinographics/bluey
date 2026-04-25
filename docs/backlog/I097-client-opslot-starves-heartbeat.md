---
id: I097
title: Client-side OpSlot starvation causes false-positive heartbeat failures
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
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

Fix sketches, in rough order of preference:

1. **Distinguish wire-timeouts from local-queue-timeouts in `_sendProbe`.** A heartbeat probe that times out *while still in the OpSlot queue* (never reached the wire) is not a dead-peer signal — the local serialization is the cause, not the peer. Only count timeouts that occurred after the op went on the wire. Requires OpSlot to surface "did this op actually transmit?" in its error metadata, which it currently doesn't.

2. **Heartbeat probes bypass OpSlot.** Symmetric to the I079 fix sketch #2 (which was rejected). Same reasoning here: defeats the serialization invariant OpSlot was introduced to protect (concurrent-GATT-op hangs, see I012-era discussion). Risky.

3. **Record local-op success as activity.** Even when a user op times out, if it completed its OpSlot lifecycle (entered, was dispatched, got a response or hit per-op timeout *on the wire*), that's still activity from the local side's perspective. Currently `BlueyConnection` only records activity on success, but in OpSlot-starvation scenarios the user op itself failing doesn't contradict "the link is alive on the wire" — only the local queueing implies it. Underdetermined; needs more thought.

(1) is the right shape — it isolates the actual misclassification. The other ideas address symptoms.

Reproduction: iOS client + Android server, run the **failure-injection** stress test at any tolerance setting. Server-side log shows the dropped echo write but no heartbeat writes during the test window; client-side disconnect fires after N visible `GattTimeoutException`s where N grows roughly linearly with tolerance.

Verified by direct instrumentation (commit `a8ee29d`, since reverted): server only drops one write per `DropNextCommand`; the second timeout is purely client-side.

Medium severity: the scenario requires a very long-stalling user op (10s+) to accumulate starved heartbeats. Not impossible in production (file transfer, OTA, slow peer), but uncommon. The disconnect itself is the *correct* response to "peer hasn't been heard from" — the bug is that "peer hasn't been heard from" is being inferred from local serialization, not from wire-level silence.
