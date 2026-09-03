---
id: I035
title: Android Dart-side bonding/PHY/connection-parameter methods return silent success
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-09-03
stage_a_fixed_in: cb1b24f
related: [I030, I031, I032, I033, I034, I065, I066]
---

## Symptom

Bonding, PHY, and connection parameters do not exist on Android (or any
platform). Since Stage A (2026-04-26) the failure is honest and layered:
`Capabilities.android` reports `canBond`, `canRequestPhy`, and
`canRequestConnectionParameters` as `false`; every public
`connection.android` member for those features (and `Bluey.bondedDevices`)
throws `UnsupportedOperationException` from the domain capability gate; and
the Android adapter's ten stubs beneath it throw `UnimplementedError` naming
this item — reachable only if the gate were bypassed. What remains is Stage B:
the Pigeon schema and Kotlin implementation that would let the flags flip to
`true`.

(Historical, pre-Stage-A: the stubs returned hardcoded defaults or empty
streams and resolved successfully, so the API silently lied.)

## Location

Domain gate: `bluey/lib/src/connection/bluey_connection.dart`
(`_AndroidConnectionExtensionsImpl._requireCapability`), `bluey/lib/src/bluey.dart`
(`bondedDevices`). Flags: `bluey_platform_interface/lib/src/capabilities.dart`.
Adapter stubs: `bluey_android/lib/src/android_connection_manager.dart` — ten
methods (`getBondState`, `bondStateStream`, `bond`, `removeBond`,
`getBondedDevices`, `getPhy`, `phyStream`, `requestPhy`,
`getConnectionParameters`, `requestConnectionParameters`), each
`throw UnimplementedError('Android: <op> not yet implemented (I035)')`.
Missing: the corresponding methods in `bluey_android/pigeons/messages.dart` and
their Kotlin implementation.

## Root cause

The Pigeon schema (`bluey_android/pigeons/messages.dart`) doesn't declare these methods, so the Dart-side adapter has nothing to delegate to. The TODO comments correctly identify the missing piece, but the chosen placeholder behaviour (silent success) is the wrong choice for a stub: it makes the bug invisible to consumers.

## Notes

Two-stage fix:

**Stage A — DONE (`cb1b24f`).** Landed 2026-04-26. Each stub now throws `UnimplementedError` with a message naming the operation and pointing at I035. `Capabilities.android.canBond` flipped from `true` to `false` so the matrix reflects reality. Implementation note: the entry's original sketch suggested the domain-layer `UnsupportedOperationException`, but `bluey_android` can't reach the domain layer (it depends on `bluey_platform_interface`, not `bluey`). Used Dart's built-in `UnimplementedError` instead — honest and immediately legible. Future-returning stubs throw asynchronously via the async body; stream-returning stubs throw synchronously.

The full typed-translation path (platform → typed exception → domain `UnsupportedOperationException`) is rolled into [I099](I099-typed-error-translation-rewrite.md). The "consult capabilities before delegating" discipline (so `connection.bond()` checks `capabilities.canBond` before throwing through to the platform) is rolled into [I065](I065-capabilities-matrix-decorative.md).

**Stage A follow-up — domain-side capability gating (2026-04-27).** Stage A made every Android client connect crash: `BlueyConnection`'s constructor unconditionally subscribed to `bondStateStream` and `phyStream` and fetched `getBondState`/`getPhy`/`getConnectionParameters` on every successful connect. With Stage A's stubs throwing synchronously, the constructor itself threw and Android-as-client became unusable, blocking manual verification of [I098](I098-android-connection-manager-rewrite.md). Fix: extended `Capabilities` with `canRequestPhy` and `canRequestConnectionParameters`, set those plus `canBond` to `false` on `Capabilities.android` (and `Capabilities.iOS`, where the same operations are unsupported by CoreBluetooth — see [I200](I200-ios-bonding-not-exposed.md)), and made `BlueyConnection` consult those flags before each subscribe / fetch. When a flag is `false` the connection keeps the seeded defaults (`BondState.none`, `(le1m, le1m)` PHY, 30 ms / 0 / 4 s connection parameters). `FakeBlueyPlatform.capabilities` is now constructor-injectable and its bond/PHY/conn-param stubs throw `UnimplementedError` when the corresponding capability is `false`, mirroring the Android contract so domain-layer regressions get caught in unit tests. Stage B (Pigeon plumbing + Kotlin) remains open.

**Stage B (proper fix, weeks):** add Pigeon methods for bond/PHY/connection-priority, implement the Kotlin side using `BluetoothDevice.createBond()`, `BluetoothGatt.setPreferredPhy(...)`, and `BluetoothGatt.requestConnectionPriority(...)`. Wire up callbacks for bond state changes (BroadcastReceiver on `ACTION_BOND_STATE_CHANGED`) and PHY changes (`onPhyUpdate` / `onPhyRead` in the gatt callback).

This issue is the necessary precondition for I030, I031, I032, I033, I034 — treat I035 as an umbrella for them.

External references:
- Android [`BluetoothDevice.createBond()`](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#createBond()).
- Android [`BluetoothGatt.setPreferredPhy(...)`](https://developer.android.com/reference/android/bluetooth/BluetoothGatt#setPreferredPhy(int,%20int,%20int)).
- Android [`BluetoothGatt.requestConnectionPriority(...)`](https://developer.android.com/reference/android/bluetooth/BluetoothGatt#requestConnectionPriority(int)).
- [`ACTION_BOND_STATE_CHANGED`](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#ACTION_BOND_STATE_CHANGED).
- Martijn van Welie, [*Making Android BLE Work — Part 4* on bonding](https://medium.com/@martijn.van.welie/making-android-ble-work-part-4-72a0b85cb442).

**Severity note (2026-06-02):** Downgraded high→medium — Stage A landed (methods now throw `UnimplementedError` and are capability-gated rather than silently succeeding); only Stage B (Pigeon + native impl) remains, and these are rarely-used APIs (bonding is legacy; PHY/conn-params niche).

## Test-harness note (2026-07-10, absorbs audit NT-11)

When Stage B lands, the fake platform needs bonding *failure* seams to
land with it: today `bond()` on a `canBond=true` fake is an
unconditional no-op success — no bond-rejected / auth-failed /
bond-removed-by-peer outcomes are simulatable, so the domain's failure
handling would ship untested.

