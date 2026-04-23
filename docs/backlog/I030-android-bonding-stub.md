---
id: I030
title: Bonding API stubbed (hardcoded returns)
category: no-op
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`Connection.bondState` always returns `BondState.none` on Android. `Connection.bond()` returns success without initiating pairing. `Connection.removeBond()` is a no-op. `Connection.bondStateChanges` is `Stream.empty()`. `Bluey.getBondedDevices()` returns `[]`. All of these are advertised as working in the domain-level `Connection` API (`bluey/lib/src/connection/connection.dart:210-237` and `bluey/lib/src/bluey.dart:458`).

Silent "success" for something that didn't happen is worse than a thrown error — users ship apps assuming bonding works, because it visibly returns without throwing.

## Location

`bluey_android/lib/src/android_connection_manager.dart:211-236` — all five bonding methods are stubs with `// TODO: Implement when Android Pigeon API supports bonding`.

## Root cause

Android natively supports bonding — `BluetoothDevice.createBond()`, `BluetoothDevice.getBondState()`, and a `BluetoothDevice.ACTION_BOND_STATE_CHANGED` broadcast. The work that's missing is pure plumbing: extend the Pigeon schema, implement the Kotlin side, remove the stubs.

## Notes

Fix sketch:

1. Pigeon additions: `getBondState(deviceId) → BondStateDto`, `bond(deviceId)`, `removeBond(deviceId)`, `getBondedDevices() → List<DeviceDto>`, event `onBondStateChanged(deviceId, state)`.
2. Kotlin: new `BondingManager` (or fold into `ConnectionManager`) that holds a `BroadcastReceiver` for `ACTION_BOND_STATE_CHANGED`, maintains per-device listener counts, and calls `createBond()` / `removeBond()` (latter is a hidden API requiring reflection — standard pattern).
3. Wire up Dart side in `AndroidConnectionManager` — replace all five stubs.

Permission implications: Android 12+ requires `BLUETOOTH_CONNECT` for bonding ops. Already requested, so no manifest change.

iOS bonding is handled transparently by CoreBluetooth — no corresponding stub to fix. The iOS `ios_connection_manager.dart` correctly returns empty streams (see I200, `wontfix`).
