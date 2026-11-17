---
id: I388
title: Bind Android GATT callbacks to their gatt instance
category: bug
severity: low
platform: android
status: open
last_verified: 2026-11-17
related: [I328, I063]
---

## Symptom

A late callback from a closed `BluetoothGatt` can tear down a newer connection to the same device.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:650`.

## Root cause

Found by reading. Callbacks are bound to a device id, not to a `BluetoothGatt` instance, so the second of two connections to one device cannot tell whose callback it is hearing.

## Notes

Found by finding L3 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 4 (native completions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Related to [I328](I328-android-state-connected-double-init.md) and [I063](I063-android-late-callback-misroute-after-timeout.md): the same completion-by-position cause. Closes in slice 4. No known-defect test yet.
