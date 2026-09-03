---
id: I030
title: Bonding API stubbed (hardcoded returns)
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-09-03
---

## Symptom

`connection.android?.bondState`, `bondStateChanges`, `bond()`, and `removeBond()`
throw `UnsupportedOperationException` on Android; `Bluey.bondedDevices` throws
the same. `Capabilities.android.canBond` is `false`. The exception comes from the domain capability gate (action: "Check bluey.capabilities before calling"); the Android adapter's underlying stubs throw `UnimplementedError` (I035 Stage A) but are unreachable from the public API. This is honest — nothing silently succeeds any more — but the feature does not exist on any platform.

(Historical, pre-2026-04-26: the stubs returned `BondState.none`, an empty
stream, and silent success — the "API silently lies" shape this entry was
filed against.)

## Location

Capability gate: `bluey/lib/src/connection/bluey_connection.dart`
(`_AndroidConnectionExtensionsImpl._requireCapability`) and
`bluey/lib/src/bluey.dart` (`bondedDevices`). Flag:
`bluey_platform_interface/lib/src/capabilities.dart` (`Capabilities.android`).
Adapter stubs: `bluey_android/lib/src/android_connection_manager.dart`
(`throw UnimplementedError('Android: bond not yet implemented (I035)')` etc.).

## Root cause

Android natively supports bonding — `BluetoothDevice.createBond()`, `BluetoothDevice.getBondState()`, and a `BluetoothDevice.ACTION_BOND_STATE_CHANGED` broadcast. The work that's missing is pure plumbing: extend the Pigeon schema, implement the Kotlin side, remove the stubs.

## Notes

Fix sketch:

1. Pigeon additions: `getBondState(deviceId) → BondStateDto`, `bond(deviceId)`, `removeBond(deviceId)`, `getBondedDevices() → List<DeviceDto>`, event `onBondStateChanged(deviceId, state)`.
2. Kotlin: new `BondingManager` (or fold into `ConnectionManager`) that holds a `BroadcastReceiver` for `ACTION_BOND_STATE_CHANGED`, maintains per-device listener counts, and calls `createBond()` / `removeBond()` (latter is a hidden API requiring reflection — standard pattern).
3. Wire up Dart side in `AndroidConnectionManager` — replace all five stubs.

Permission implications: Android 12+ requires `BLUETOOTH_CONNECT` for bonding ops. Already requested, so no manifest change.

iOS bonding is handled transparently by CoreBluetooth — no corresponding stub to fix. The iOS `ios_connection_manager.dart` correctly returns empty streams (see I200, `wontfix`).

**Severity note (2026-06-02):** Downgraded high→medium — Stage A landed (methods now throw `UnimplementedError` and are capability-gated rather than silently succeeding); only Stage B (Pigeon + native impl) remains, and these are rarely-used APIs (bonding is legacy; PHY/conn-params niche).
