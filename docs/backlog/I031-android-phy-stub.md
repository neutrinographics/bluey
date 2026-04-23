---
id: I031
title: PHY API stubbed (hardcoded returns)
category: no-op
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`Connection.requestPhy()` returns success without requesting a PHY change. `Connection.phyChanges` is `Stream.empty()`. `Connection.getPhy()` always returns `(tx: le1m, rx: le1m)`.

Domain API advertises this at `bluey/lib/src/connection/connection.dart:267` — callers assume it works.

## Location

`bluey_android/lib/src/android_connection_manager.dart:241-259` — three stubs with `// TODO: Implement when Android Pigeon API supports PHY`.

## Root cause

Android exposes `BluetoothGatt.setPreferredPhy(txPhy, rxPhy, phyOptions)` and `BluetoothGattCallback.onPhyUpdate` / `onPhyRead` since API 26. Pure plumbing gap.

## Notes

Fix sketch:

1. Pigeon: `setPreferredPhy(deviceId, txPhy, rxPhy, phyOptions)`, `readPhy(deviceId) → PhyPairDto`, event `onPhyChanged(deviceId, txPhy, rxPhy)`.
2. Kotlin: thread through `ConnectionManager`; remember to **queue** these via the existing `GattOpQueue` (PHY ops also occupy the single-op slot).
3. Dart wiring in `AndroidConnectionManager`; remove stubs.

API-level gate: `Build.VERSION.SDK_INT < Build.VERSION_CODES.O` → return / throw a Bluey-typed exception. `minSdkVersion` in Bluey's Gradle config should be compared; if it's ≥26 this is a pure implementation.

iOS does not expose PHY at all — see I200, `wontfix`.
