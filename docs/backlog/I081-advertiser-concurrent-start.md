---
id: I081
title: "Advertiser allows concurrent `startAdvertising` before `isAdvertising` flag set"
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`Advertiser.startAdvertising` checks `isAdvertising` at entry; if false, it starts the BLE advertiser and relies on `onStartSuccess` to set `isAdvertising = true`. Between the start call and the callback, a concurrent `startAdvertising` sees `isAdvertising == false` and starts a second advertiser. Result: two advertisers overlap; state bookkeeping diverges from reality; the caller gets two success callbacks and one failure.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt:41-155` (startAdvertising) and `:116-123` (onStartSuccess).

## Root cause

Check-and-act on `isAdvertising` without an intermediate "starting" state. The flag transitions only on success callback.

## Notes

Fix: add `isStarting: Boolean` flag. Entry sets it true; `onStartSuccess` transitions to `isAdvertising = true, isStarting = false`; `onStartFailure` resets to `isStarting = false`. Entry checks both: if either is true, reject.

Not common in practice — callers typically don't call `startAdvertising` repeatedly before awaiting — but the bug is real and the guard is cheap.
