---
id: I031
title: PHY API stubbed (hardcoded returns)
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-09-03
---

## Symptom

`connection.android?.txPhy`, `rxPhy`, `phyChanges`, and `requestPhy(...)`
throw `UnsupportedOperationException` on Android; `Capabilities.android.canRequestPhy`
is `false`. The exception comes from the domain capability gate (action: "Check bluey.capabilities before calling"); the Android adapter's underlying stubs throw `UnimplementedError` (I035 Stage A) but are unreachable from the public API. This is honest — nothing silently succeeds any more — but the feature does not exist on any platform.

(Historical, pre-2026-04-26: `requestPhy` resolved without sending anything,
`phyChanges` was empty, and the PHY read back as `(le1m, le1m)`.)

## Location

Capability gate: `bluey/lib/src/connection/bluey_connection.dart`
(`_AndroidConnectionExtensionsImpl._requireCapability`). Flag:
`bluey_platform_interface/lib/src/capabilities.dart`. Adapter stubs:
`bluey_android/lib/src/android_connection_manager.dart` (`getPhy`, `phyStream`,
`requestPhy` throw `UnimplementedError`).

## Root cause

Android exposes `BluetoothGatt.setPreferredPhy(txPhy, rxPhy, phyOptions)` and `BluetoothGattCallback.onPhyUpdate` / `onPhyRead` since API 26. Pure plumbing gap.

## Notes

Fix sketch:

1. Pigeon: `setPreferredPhy(deviceId, txPhy, rxPhy, phyOptions)`, `readPhy(deviceId) → PhyPairDto`, event `onPhyChanged(deviceId, txPhy, rxPhy)`.
2. Kotlin: thread through `ConnectionManager`; remember to **queue** these via the existing `GattOpQueue` (PHY ops also occupy the single-op slot).
3. Dart wiring in `AndroidConnectionManager`; remove stubs.

API-level gate: `Build.VERSION.SDK_INT < Build.VERSION_CODES.O` → return / throw a Bluey-typed exception. `minSdkVersion` in Bluey's Gradle config should be compared; if it's ≥26 this is a pure implementation.

iOS does not expose PHY at all — see I200, `wontfix`.

**Severity note (2026-06-02):** Downgraded high→medium — Stage A landed (methods now throw `UnimplementedError` and are capability-gated rather than silently succeeding); only Stage B (Pigeon + native impl) remains, and these are rarely-used APIs (bonding is legacy; PHY/conn-params niche).
