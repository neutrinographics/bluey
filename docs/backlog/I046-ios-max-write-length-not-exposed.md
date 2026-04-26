---
id: I046
title: iOS `getMaximumWriteLength` implemented but not exposed via Pigeon
category: unimplemented
severity: medium
platform: ios
status: open
last_verified: 2026-04-26
related: [I034]
---

## Symptom

A consumer that wants to chunk a large value at the optimal size for the negotiated MTU has no way to query `peripheral.maximumWriteValueLength(for: writeType)`. The information exists on iOS but isn't crossed over the FFI boundary.

## Location

- iOS implementation present: `bluey_ios/ios/Classes/CentralManagerImpl.swift:407`.
- Pigeon schema missing the method: `bluey_ios/pigeons/messages.dart` — no `getMaximumWriteLength` declaration.
- Platform interface lacks the abstract method: `bluey_platform_interface/lib/src/platform_interface.dart`.

## Root cause

The iOS-side Swift function exists from earlier implementation work, but the corresponding Pigeon HostApi method, Dart-side wrapper in `IosConnectionManager`, and `BlueyPlatform` abstract method were never added. The Swift function is dead code as shipped.

## Notes

Companion to I034 (Android side has the same gap). Fix should be coherent across both platforms:

1. Add `getMaximumWriteLength(deviceId, withResponse) -> int` to `BlueyPlatform`.
2. Declare it in both `pigeons/messages.dart` files.
3. Implement Android side via `BluetoothGatt` (Android exposes this indirectly — derive from `mtu - 3` for write-with-response, or `min(mtu - 3, 512)` for write-without-response chunked).
4. Wire iOS through to the existing `peripheral.maximumWriteValueLength`.
5. Surface on `Connection` as `maximumWriteValueLength({withResponse: true})`.

External references:
- Apple [`CBPeripheral.maximumWriteValueLength(for:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)).
- Punch Through, [BLE Write Requests vs. Write Commands](https://punchthrough.com/ble-write-requests-vs-write-commands/) — discusses the relationship between MTU and write-type-specific limits.
