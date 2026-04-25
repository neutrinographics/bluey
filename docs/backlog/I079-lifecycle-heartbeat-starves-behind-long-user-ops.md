---
id: I079
title: LifecycleServer declares clients gone while holding their pending requests
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-25
fixed_in: 4206343
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

Fixed in `4206343` by introducing pending-request tolerance in
`LifecycleServer`. The previous prose recommending a client-side fix
(routing successful user-op completions into `LivenessMonitor.recordActivity`)
described work that was already in tree (`bluey/lib/src/connection/bluey_connection.dart:317`,
`:364`, `:376`, `:619`) and did not address this scenario — during the 12 s
stall the user op has not yet *succeeded* on the client, so there is no
completion event to feed.

The actual fix, per
[the design doc](../superpowers/specs/2026-04-25-i079-lifecycle-server-pending-request-tolerance-design.md):

- `LifecycleServer` now tracks a per-client set of pending platform request
  IDs. While the set is non-empty, the heartbeat-timeout timer is paused.
  When the last pending request completes, the timer re-arms with a fresh
  interval.
- `BlueyServer` calls `requestStarted` on read / write-with-response arrival
  and `requestCompleted` *before* the platform `respondTo*` call (so the
  pending set drains even if the platform throws).
- iOS-server detection regression accepted: a client that drops its link
  while the iOS server is holding a pending request is detected only after
  the app responds + one full interval. Narrow corner; routine false-positive
  bug fixed.
