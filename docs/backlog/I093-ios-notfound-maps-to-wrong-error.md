---
id: I093
title: "iOS `BlueyError.notFound` for unknown characteristic maps to `gatt-disconnected`"
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-23
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
