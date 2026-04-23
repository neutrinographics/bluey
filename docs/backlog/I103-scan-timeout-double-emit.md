---
id: I103
title: Scan timeout fires after manual stop
category: bug
severity: low
platform: android
status: fixed
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-ANDROID-A7
---

## Symptom (historical)

When `stopScan()` was called before the scan-timeout `Runnable` fired, the timeout still posted `onScanComplete` later, producing a duplicate completion event.

## Verified fix

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt:124-137` — `stopScanInternal()` removes the timeout `Runnable` before clearing state, and `stopScan()` calls `stopScanInternal()` before dispatching `onScanComplete`. Defensive ordering prevents the double-emit.

## Notes

The `onScanComplete` dispatcher is still a plain "scan ended" event — see I013 for the related, still-open bug that the error code from `onScanFailed` isn't propagated.
