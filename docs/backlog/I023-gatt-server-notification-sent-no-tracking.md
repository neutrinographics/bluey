---
id: I023
title: "`onNotificationSent` not tracked for completion"
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-04-23
related: [I012]
---

## Symptom

Android fires `onNotificationSent(device, status)` after each notification delivery (per-central on modern APIs, aggregate on legacy). The library only logs it. Callers have no way to observe delivery confirmation or failure on a per-central basis.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:550-553` — handler body: `Log.d("GattServer", ...)`.

## Root cause

No tracking map between `notifyCharacteristic()` calls and the `onNotificationSent` events. I012 is the symptom; this is the mechanism.

## Notes

Closely coupled to I012 — consider merging them into one PR. I012 describes the desired user-facing shape; I023 describes the native-side plumbing change. Both are the same fix.
