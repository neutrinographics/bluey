---
id: I101
title: Android pending callback collision
category: bug
severity: high
platform: android
status: fixed
last_verified: 2026-04-23
fixed_in: "8d210c3"
historical_ref: BUGS-ANALYSIS-#6
---

## Symptom (historical)

Old callback storage was `pendingReads[deviceId:charUuid] = callback`. A concurrent second read overwrote the first callback; the first caller hung forever when the stack delivered the response to the overwritten callback.

## Verified fix

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:35` + `GattOpQueue.kt` — replaced the map with a per-connection `GattOpQueue`. Each op is enqueued with its own completion handler; the queue serializes and binds the handler to the specific op, so concurrent requests queue up instead of clobbering each other.

## Notes

Phase 2a (2026-04-21) — see `docs/superpowers/plans/2026-04-21-phase-2a-android-gatt-queue.md` and `docs/superpowers/specs/2026-04-21-phase-2a-android-gatt-queue-design.md` for the full design.
