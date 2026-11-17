---
id: I390
title: Finish pending work when the Android GATT server is cleaned up
category: bug
severity: low
platform: android
status: open
last_verified: 2026-11-17
---

## Symptom

If the engine outlives the activity, pending `addService` calls never complete and no client disconnects are emitted, so Dart state goes stale.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:505-557` — `cleanup()`.

## Root cause

Found by reading. `cleanup()` clears the pending `addService` callbacks without calling them and emits no client disconnects.

## Notes

Found by finding L5 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 5 (server and peer) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Related by cause to [I015](I015-gatt-server-close-order-on-engine-detach.md). Closes in slice 5. No known-defect test yet.
