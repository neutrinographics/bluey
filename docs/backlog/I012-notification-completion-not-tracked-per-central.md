---
id: I012
title: Server notification completion not tracked per central
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-ANDROID-A5
---

## Symptom

When the server notifies multiple subscribed centrals, the Dart-side completion fires before the stack has actually sent the packets, and there's no per-central success/failure. If the packet for central B fails to go out, the caller never learns.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:119-153` — `notifyCharacteristic()` iterates subscribers and calls `sendNotification()` for each; the caller's completion callback resolves without waiting for `onNotificationSent`.

`GattServer.kt:550-553` — `onNotificationSent(device, status)` is present but only logs.

## Root cause

`onNotificationSent` isn't tied back to the originating call. The completion model is fire-and-forget at the native level; there's no `pendingNotifications` map keyed by central to resolve on each delivery.

## Notes

Fix sketch: per-central completion tracking.

1. In `notifyCharacteristic`, build a `Map<String, (Result<Unit>) -> Unit>` — one entry per subscribed central.
2. In `onNotificationSent`, pop the entry for `device.address` and invoke the callback with the status.
3. The outer Dart-side API presents the aggregate: `Future<Map<CentralId, Result<Unit>>>` or similar, so the server app can see per-central outcomes.

Complication: on Android pre-Tiramisu, `notifyCharacteristicChanged(device, char, confirm)` is the legacy API and has different semantics. Post-Tiramisu uses `notifyCharacteristicChanged(device, char, confirm, value)` which returns a status int. Need to handle both.

Indication (confirm=true) deserves its own handling — `onNotificationSent` fires even on un-confirmed indications; the actual ack is via a separate callback in some stacks.
