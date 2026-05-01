---
id: I315
title: iOS PendingNotificationQueue may hold stale entries for disconnected centrals
category: limitation
severity: low
platform: ios
status: open
last_verified: 2026-05-01
related: [I040, I201]
---

## Symptom

When a central disconnects mid-burst, any
`notifyCharacteristicTo(central, ...)` entries already enqueued in
`PendingNotificationQueue` (from I040) reference a `CBCentral` that is
no longer connected. The entry sits in the queue waiting for a drain
that may never come.

Two failure modes are possible depending on iOS's exact behavior for
`peripheralManager.updateValue(_:for:onSubscribedCentrals:[disconnectedCentral])`:

1. **iOS returns `false`** — head-of-line blocking. The dead entry
   never drains; entries behind it for healthy centrals also stall
   because `drain` halts at the first `false`. The whole queue
   freezes until `closeServer` flushes.
2. **iOS returns `true`** — silent data loss. The entry pops with
   `.success`, the caller's `Future<void>` resolves, but nothing left
   the device. Reporter thinks delivery succeeded.

Empirically untested — the I040 verification session at count=100 did
not exercise mid-burst disconnect.

## Location

`bluey_ios/ios/Classes/PendingNotificationQueue.swift` — the queue
itself. The cleanup hook would live in `PeripheralManagerImpl.swift`
where centrals are tracked (`centrals: [String: CBCentral]`).

## Root cause

iOS does not provide a client-disconnect callback (see I201 — "iOS has
no client disconnect callback (mitigated)"). The
`PeripheralManagerImpl` has no signal to fail-out queued entries
when a targeted central disconnects.

The Dart-side lifecycle layer infers disconnects via heartbeat-silence
timeouts, but that signal lives in `bluey/lib/src/gatt_server/` and
does not reach back to the iOS plugin's queue without additional
Pigeon plumbing.

## Notes

**Bounded scope:**
- Cap (1024 entries) limits the per-server-lifetime memory leak.
- `closeServer` calls `failAll` and releases every remaining entry
  with `BlueyError.handleInvalidated` — the bound is server lifetime.
- The leak is per-disconnected-central, not per-notification.
- For broadcast `notifyCharacteristic` (no targeted central) this
  doesn't apply — the queue entry has `central: nil` and routes to
  whichever centrals are subscribed at drain time.

**Fix sketches (uncertain whether either is worth doing):**

1. **Out-of-band cleanup hook**: add a Pigeon method
   `purgePendingNotifications(centralId)` that the Dart-side lifecycle
   layer calls when it declares a peer dead. Keeps the iOS plugin
   stateless about disconnect detection but plumbs a new wire
   message.
2. **Time-bounded entries**: stamp each entry with an enqueue
   timestamp; on drain, if an entry has been queued for > N seconds,
   fail it with a specific error. Doesn't require new Pigeon, but
   trades freshness for an arbitrary timeout heuristic.

**Verification before fix:** run the failure-injection stress test
with iOS as server, kill the Android client mid-burst, observe whether
iOS's `updateValue` returns `false` (case 1) or `true` (case 2). The
fix differs depending on the answer.

**My read:** low priority. The I040 fix as landed is correct for the
common case (graceful disconnect via lifecycle protocol). The
mid-burst-uncoordinated-disconnect path is rare in normal use; the
cap bounds the cost; `closeServer` bounds the lifetime. Pick up only
if a stress test or production report surfaces head-of-line blocking
in practice.
