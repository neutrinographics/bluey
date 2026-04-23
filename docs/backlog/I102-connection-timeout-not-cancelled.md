---
id: I102
title: Connection timeout not cancelled on success
category: bug
severity: medium
platform: android
status: fixed
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#10, BUGS-ANALYSIS-ANDROID-A6
---

## Symptom (historical)

`connect()` scheduled a timeout `Runnable` via `handler.postDelayed`. On successful connect, only `pendingConnections[deviceId]` was cleared — the `Runnable` wasn't removed, so it fired later and attempted to tear down an already-live connection.

## Verified fix

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:508-509` — `onConnectionStateChange(STATE_CONNECTED)` now calls `pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }`.

A `pendingConnectionTimeouts: MutableMap<String, Runnable>` was added at construction time to enable cancellation.

## Notes

Likely landed as part of the broader Phase 2a work; not explicitly called out in the Phase 2a spec, but the ordering is consistent with that commit range.
