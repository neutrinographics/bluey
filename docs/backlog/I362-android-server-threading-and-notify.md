---
id: I362
title: Thread-confine the Android GATT server and gate notifies on onNotificationSent
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-07-10
related: [I012]
---

## Symptom

Four related Android *server-side* hazards (the client stack is
rigorously main-thread-confined; audit DA-14..DA-17):

- shared maps (`connectedCentrals`, `centralMtus`,
  `characteristicByHandle`) mutated on binder threads while read on
  main — `ConcurrentModificationException` risk (DA-14)
- notify fan-out fires all recipients back-to-back, discarding
  `notifyCharacteristicChanged`'s status, instead of waiting for
  `onNotificationSent` per central — silent drops under load (DA-15)
- `Thread.sleep(100)` on the main thread in `ensureServerOpen` — ANR
  risk (DA-16)
- Pigeon replies + map mutations invoked directly on binder threads in
  `onServiceAdded` / Advertiser callbacks (DA-17)

## Location

`bluey_android/.../GattServer.kt`, `Advertiser.kt` (line refs in the
2026-07-07 audit, cluster M-D).

## Notes

Marshal mutations onto `handler.post` (as `STATE_DISCONNECTED` already
does), replace the sleep with `postDelayed`, and add a per-central send
queue mirroring iOS's `PendingNotificationQueue` — the server-side
sibling of shipped
[I012](I012-notification-completion-not-tracked-per-central.md). The
Kotlin captured-callback harness covers all of this territory.
