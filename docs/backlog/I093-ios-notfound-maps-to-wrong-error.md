---
id: I093
title: "iOS `BlueyError.notFound` for unknown characteristic maps to `gatt-disconnected`"
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-05-04
fixed_in: 8875f4c
related: [I088]
---

## Symptom

When the iOS side can't find a characteristic or descriptor in its cache (e.g., user passed a UUID that isn't in the current service tree), `CentralManagerImpl` emits `BlueyError.notFound.toClientPigeonError()`. The resulting `PigeonError` code is something that the Dart-side translator maps to `GattOperationDisconnectedException` (because the notFound path uses the disconnected code by convention).

This is misleading: the caller sees a "disconnected" error when the actual problem is "characteristic UUID not in service tree." Debugging becomes confusing — the connection is fine, the lookup just failed.

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift` — multiple sites where `BlueyError.notFound.toClientPigeonError()` is used (e.g., in `readCharacteristic`, `writeCharacteristic`, `readDescriptor`, `writeDescriptor`).

`bluey_ios/lib/src/ios_connection_manager.dart:~35-54` — the `_translateGattPlatformError` switch.

## Root cause

The `BlueyError.notFound` case in iOS's Swift error helper was historically conflated with disconnection because both are "no longer available." The code mapping reflects that but the symptom distinction matters to callers.

## Notes

Fix: introduce a distinct `gatt-notfound` Pigeon error code, map it on Dart side to a domain `CharacteristicNotFoundException` / `DescriptorNotFoundException`. These types likely already exist in `exceptions.dart` (Android emits them); iOS just isn't using them.

Verify the Android side also does this correctly — the expected typed error for "unknown characteristic UUID" should be consistent between platforms.

## Resolution

The original premise — characteristic / descriptor UUID misses
producing `gatt-disconnected` — was resolved by the I088 handle
rewrite (`73656b4`). Post-I088, every characteristic / descriptor
op in `CentralManagerImpl.swift` (lines 253-371) routes a missing
handle through `BlueyError.handleInvalidated.toClientPigeonError()`
→ `gatt-handle-invalidated` → `AttributeHandleInvalidatedException`,
not through `BlueyError.notFound`.

Re-verification on 2026-05-04 found three remaining
`BlueyError.notFound.toClientPigeonError()` sites in
`CentralManagerImpl.swift` (lines 153, 194, 226), all guarding
`peripherals[deviceId]` lookup misses in `connect`, `disconnect`,
and `discoverServices`. These fire when the user passes a deviceId
this iOS plugin instance has never seen. The current mapping to
`gatt-disconnected` was reviewed and left intentionally — the
user-visible truth ("you can't talk to this device right now") is
the same, the case is rare, and introducing a new
`DeviceUnknownException` type would be over-engineering for one
seldom-hit path. See the I091 + I093 design doc at
`docs/superpowers/specs/2026-05-04-ios-error-mapping-cleanup-design.md`
for the rationale.
