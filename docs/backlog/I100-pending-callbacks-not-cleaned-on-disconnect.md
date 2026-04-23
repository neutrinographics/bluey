---
id: I100
title: Pending callbacks not cleaned on disconnect
category: bug
severity: high
platform: android
status: fixed
last_verified: 2026-04-23
fixed_in: "8d210c3"
historical_ref: BUGS-ANALYSIS-ANDROID-A3
---

## Symptom (historical)

On `onConnectionStateChange(STATE_DISCONNECTED)`, pending callbacks for in-flight reads, writes, descriptor ops, service discovery, MTU requests, etc. were not failed. Their `Future`s on the Dart side hung indefinitely.

## Verified fix

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:524-534` — `onConnectionStateChange(STATE_DISCONNECTED)` now posts `queue.drainAll(FlutterError("gatt-disconnected", ...))` to the main thread, failing every pending and queued op on that connection.

Enabled by the Phase 2a GATT operation queue, which serializes all ops through a single `GattOpQueue` per connection and gives disconnect a single tear-down point (`drainAll`).

## Notes

Keep this entry — verification artifact. If a future refactor stops routing all ops through `GattOpQueue`, this bug would come back.
