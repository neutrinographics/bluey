---
id: I079
title: LifecycleClient heartbeat probe starves behind long user ops, causing spurious server-initiated disconnects
category: bug
severity: high
platform: both
status: open
last_verified: 2026-04-24
related: [I012, I077]
---

## Symptom

During the stress-test timeout-probe and failure-injection tests (iOS client → Android server), a deliberately-stalled user write of ~12s causes the server to tear down the connection mid-test:

1. Client does `stressChar.write(DelayAckCommand(delayMs: 12000))` (or `DropNextCommand` followed by an echo write).
2. iOS serializes the write through `OpSlot<T>` so the user op holds the slot for the full delay/timeout window.
3. `LifecycleClient._sendProbe` calls `_platform.writeCharacteristic(...)` — which goes through the **same** OpSlot. The heartbeat probe queues behind the in-flight user op and does not execute.
4. Server-side `LifecycleServer` heartbeat timer fires (no heartbeat arrived within its tolerance window) → server considers the client gone → closes the GATT link.
5. Client sees the disconnect, surfaces a `GattTimeoutException` for the user op, and either auto-reconnects (timeout probe) or emits a cascade of `DisconnectedException`s for queued ops (failure injection).

The effect: any single client-side op that blocks longer than the server's lifecycle tolerance (~2× heartbeat interval by default, ≈10 s) reliably triggers a spurious disconnect, even though the underlying BLE link is healthy.

## Location

- `bluey/lib/src/connection/lifecycle_client.dart:192-239` — `_sendProbe` writes the heartbeat through `_platform.writeCharacteristic`.
- `bluey_ios/ios/Classes/OpSlot.swift` — serializes all GATT ops per connection, including the heartbeat write.
- `bluey/lib/src/gatt_server/lifecycle_server.dart:143-145` — server's per-client heartbeat-timeout timer that fires and releases the client.

## Root cause

The client-side heartbeat was designed as a "liveness probe" under the assumption that the write itself is always free to fire promptly. After 6a15c75 introduced `OpSlot<T>` on iOS (to fix concurrent-GATT-op hangs — I012-era), heartbeat writes share the slot with user ops and are blocked whenever a user op is in flight.

Separately, the `LivenessMonitor.recordActivity()` contract already says "any successful user op is liveness evidence" — but nothing actually calls `recordActivity()` from user-op completion paths today. So even when a user op is about to succeed, the monitor still asks for a probe, which can't fire because the user op hasn't returned yet. Catch-22.

Android shares the protocol (`LifecycleClient` lives in domain) and native GATT also serializes ops one-at-a-time, so the same class of bug is theoretically reachable on Android — but Android's native layer has tighter per-op timeouts, so the starvation window is shorter and the symptom less reproducible. iOS is the routine trigger.

## Notes

Fix sketches, rough order of preference:

1. **Have successful user ops feed `recordActivity()`**. Route completion of any read/write/notify through the `LivenessMonitor` on the client side. A user op that just succeeded is *better* liveness evidence than a probe. This alone removes the need to fire a probe while user traffic is active, and the scheduler already handles deferral correctly (I077).

   Open question: also signal "op started" so the heartbeat deadline isn't armed against a stale anchor while a long op is in flight. Simplest form — when dispatching a user op, call `recordActivity()` optimistically; if the op fails with a dead-peer signal, the existing disconnect path handles it.

2. **Have the heartbeat bypass the OpSlot** (separate queue, or priority-insert in front of queued user ops). Risky — defeats the serialization invariant OpSlot was introduced to protect. Not recommended.

3. **Raise the server-side lifecycle tolerance** to cover the longest plausible user-op duration. Brittle — depends on application-layer timeouts the library doesn't control.

(1) is the right shape. The change is small: `BlueyConnection` already knows when ops succeed; it needs to notify the `LifecycleClient` attached to that connection (via the existing Peer wiring).

Reproduction: iOS client + Android server, run the **timeout probe** stress test. Every invocation reproduces. Failure-injection reproduces the same underlying issue but with a messier post-disconnect error cascade (see I087).

High severity because it's not hypothetical — it fires on ordinary long-running user ops. Any production app that does a slow read/write (file transfer, OTA, any operation where the peer takes a few seconds to respond) will see spurious disconnects.
