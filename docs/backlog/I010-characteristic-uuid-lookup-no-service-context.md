---
id: I010
title: Characteristic UUID lookup ignores service context
category: bug
severity: critical
platform: android
status: open
last_verified: 2026-04-26
historical_ref: BUGS-ANALYSIS-ANDROID-A1
related: [I011, I016, I088]
---

## Symptom

If a device exposes two services that each contain a characteristic with the same UUID, all GATT operations on that UUID silently operate on whichever characteristic the tree walk reaches first — typically the one in the lowest-indexed service. The second service's characteristic is unreachable.

## Location

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:749-759` — `findCharacteristic(gatt, uuid)` iterates services in order and returns the first match.
- iOS server-side mirror: `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:18, 53` — `characteristics: [String: CBMutableCharacteristic]` keyed by charUuid alone. Same dimensional error in the hosted-service bookkeeping. (See also I016.)

## Root cause

Lookup key is `characteristicUuid` alone. No service UUID is propagated from the Dart domain layer (which does know the service context) into the Pigeon-level read/write/notify calls.

## Notes

Fix shape: add a `serviceUuid: String` parameter to every characteristic-targeting Pigeon method (`readCharacteristic`, `writeCharacteristic`, `setNotification`) and thread it through `BlueyRemoteCharacteristic` in the Dart layer. The Android side uses both UUIDs; iOS uses both too (CoreBluetooth's `discoveredServices` / `characteristics` already carry the binding, but keying lookups on both is defensive).

Alternative: use Android's `BluetoothGattCharacteristic.instanceId` (hash code) as the stable key, the way `bluetooth_low_energy_android` does. Higher-fidelity but requires lifetime tracking of the native instance.

Related: I011 (same pattern for descriptors, which is where the bug actually bites in practice via CCCD); I016 (iOS server-side mirror); I088 (architectural rewrite of Pigeon GATT schema, which is the principled coherent fix).
