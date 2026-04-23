---
id: I022
title: Descriptor read auto-responded; no Dart API
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

The Android GATT server auto-responds to `onDescriptorReadRequest` with `descriptor.value ?: ByteArray(0)` without notifying Flutter. There's no corresponding Pigeon event or `respondToDescriptorReadRequest` method, so server apps can't handle descriptor reads at all — the only thing a client ever sees is the native-cached descriptor value (typically empty).

This doesn't break CCCD, because the CCCD read returns its own state which Android maintains correctly. It does break any server that exposes user-description, presentation-format, or custom descriptors.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:476-494` — `onDescriptorReadRequest` auto-responds without a Pigeon call.

## Root cause

The Pigeon API surface was designed for characteristic-level reads/writes only. Descriptor operations on the server side were never modeled.

## Notes

Fix shape depends on scope choice:

- **Narrow fix**: add `onDescriptorReadRequest` / `respondToDescriptorReadRequest` Pigeon pair, mirroring the characteristic versions. Same `pendingReadRequests` pattern as I020/I021. Symmetric addition on the Dart domain-layer `Server` class.
- **Broader design question**: whether the library should expose server-side descriptor operations at all, or auto-handle CCCD + CUD and treat arbitrary descriptors as out of scope.

iOS exposes this via `CBPeripheralManagerDelegate.peripheralManager(_:didReceiveRead:)` where `request.characteristic` is the descriptor's host; the current iOS code only handles characteristic reads too (not a regression — intentional).

Coupled with `onDescriptorWriteRequest` — currently auto-responds for non-CCCD writes, and that's also not surfaced to Flutter. If we decide to expose descriptor ops, both should land together.
