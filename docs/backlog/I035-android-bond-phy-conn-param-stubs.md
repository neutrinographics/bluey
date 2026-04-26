---
id: I035
title: Android Dart-side bonding/PHY/connection-parameter methods return silent success
category: no-op
severity: high
platform: android
status: open
last_verified: 2026-04-26
stage_a_fixed_in: cb1b24f
related: [I030, I031, I032, I033, I034, I065, I066]
---

## Symptom

`connection.bond()` on Android completes successfully with no error, but does not initiate a bond. `connection.bondState` returns `BondState.none` permanently. `connection.bondStateChanges` is an empty stream that never emits. `connection.requestPhy(...)` resolves successfully but does not send the HCI command. `connection.connectionParameters` returns hardcoded default values regardless of the actual link state.

This is **worse** than throwing `UnimplementedError`: the API silently lies. A consumer reading the docstring on `Connection.bond()` ("This will start the bonding process") sees the future complete and assumes bonding succeeded. They then attempt to read an encryption-required characteristic, which fails — and the failure is opaque.

## Location

`bluey_android/lib/src/android_connection_manager.dart:211-281`. All ten stub methods (`getBondState`, `bondStateStream`, `bond`, `removeBond`, `getBondedDevices`, `getPhy`, `phyStream`, `requestPhy`, `getConnectionParameters`, `requestConnectionParameters`) follow the same pattern — return hardcoded defaults or empty streams, do nothing.

```dart
// Representative example:
Future<void> bond(String deviceId) async {
  // TODO: Implement when Android Pigeon API supports bonding
}
```

## Root cause

The Pigeon schema (`bluey_android/pigeons/messages.dart`) doesn't declare these methods, so the Dart-side adapter has nothing to delegate to. The TODO comments correctly identify the missing piece, but the chosen placeholder behaviour (silent success) is the wrong choice for a stub: it makes the bug invisible to consumers.

## Notes

Two-stage fix:

**Stage A — DONE (`cb1b24f`).** Landed 2026-04-26. Each stub now throws `UnimplementedError` with a message naming the operation and pointing at I035. `Capabilities.android.canBond` flipped from `true` to `false` so the matrix reflects reality. Implementation note: the entry's original sketch suggested the domain-layer `UnsupportedOperationException`, but `bluey_android` can't reach the domain layer (it depends on `bluey_platform_interface`, not `bluey`). Used Dart's built-in `UnimplementedError` instead — honest and immediately legible. Future-returning stubs throw asynchronously via the async body; stream-returning stubs throw synchronously.

The full typed-translation path (platform → typed exception → domain `UnsupportedOperationException`) is rolled into [I099](I099-typed-error-translation-rewrite.md). The "consult capabilities before delegating" discipline (so `connection.bond()` checks `capabilities.canBond` before throwing through to the platform) is rolled into [I065](I065-capabilities-matrix-decorative.md).

**Stage B (proper fix, weeks):** add Pigeon methods for bond/PHY/connection-priority, implement the Kotlin side using `BluetoothDevice.createBond()`, `BluetoothGatt.setPreferredPhy(...)`, and `BluetoothGatt.requestConnectionPriority(...)`. Wire up callbacks for bond state changes (BroadcastReceiver on `ACTION_BOND_STATE_CHANGED`) and PHY changes (`onPhyUpdate` / `onPhyRead` in the gatt callback).

This issue is the necessary precondition for I030, I031, I032, I033, I034 — treat I035 as an umbrella for them.

External references:
- Android [`BluetoothDevice.createBond()`](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#createBond()).
- Android [`BluetoothGatt.setPreferredPhy(...)`](https://developer.android.com/reference/android/bluetooth/BluetoothGatt#setPreferredPhy(int,%20int,%20int)).
- Android [`BluetoothGatt.requestConnectionPriority(...)`](https://developer.android.com/reference/android/bluetooth/BluetoothGatt#requestConnectionPriority(int)).
- [`ACTION_BOND_STATE_CHANGED`](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#ACTION_BOND_STATE_CHANGED).
- Martijn van Welie, [*Making Android BLE Work — Part 4* on bonding](https://medium.com/@martijn.van.welie/making-android-ble-work-part-4-72a0b85cb442).
