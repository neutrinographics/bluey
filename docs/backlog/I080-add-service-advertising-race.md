---
id: I080
title: "Android `addService` races with `startAdvertising`"
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`addService` is async on Android — `BluetoothGattServer.addService()` returns immediately; the service isn't actually registered until `onServiceAdded` fires. `startAdvertising` can be called independently and doesn't wait for services to finish registering. A central connecting while advertising is live but services aren't ready sees an incomplete GATT tree; subsequent `discoverServices()` on the client may return fewer services than expected.

The internal control service (the lifecycle heartbeat) is correctly awaited by `BlueyServer` before advertising starts. User-added services aren't.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:63-103` (addService and its pending callback) and `Advertiser.kt:41-155` (startAdvertising).

## Root cause

No coordination between the two state machines. `Advertiser` doesn't know whether all services are registered when it starts advertising.

## Notes

Fix sketch: require `startAdvertising` to be called only after all pending `addService` calls have resolved. Either (a) track `pendingServiceAdditions` count and defer advertising until zero; or (b) enforce in the domain-layer `BlueyServer` API — after `addService` returns, only then allow `startAdvertising`.

iOS has a similar async service-add pattern via `peripheralManager(_:didAdd:error:)` — worth checking whether iOS has the same race (cursory check suggests it also needs the await-then-advertise ordering).

Related: BlueyServer's control service wait is intentional; the user-service wait should be symmetric.
