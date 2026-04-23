---
id: I024
title: Server-side MTU change not propagated to Dart
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-04-23
related: [I004]
---

## Symptom

When a central negotiates a new MTU with the Android GATT server, `onMtuChanged(device, mtu)` fires on the native side. The value is cached in `centralMtus` but never surfaced to the Dart-side `Server`. Server apps can't learn the per-central MTU, can't chunk notifications appropriately, and can't react to MTU growth by increasing payload sizes.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:545-548` — caches to `centralMtus`, no Pigeon emission.

## Root cause

No `onCentralMtuChanged` event in the Pigeon schema; no `Central.mtu` getter or `Central.mtuChanges` stream in the domain layer.

## Notes

Fix sketch:

1. Add a Pigeon event `onCentralMtuChanged(centralId, mtu)` from native → Flutter.
2. Add `Central.mtu` and `Central.mtuChanges` (matching the client-side shape from I004).
3. Decide whether to also expose the Android GATT server's per-central MTU query — Android doesn't provide a synchronous read API; you have to keep state from the last `onMtuChanged`.

iOS side: `CBCentral.maximumUpdateValueLength` already exists; wire a parallel event — it changes when the central subscribes or unsubscribes. No explicit MTU-change callback, but observable via `centralDidSubscribeToCharacteristic` / periodic refresh.

Related: I004 solves the same thing for `Connection` (client side); this does it for `Server` + `Central` (server side).
