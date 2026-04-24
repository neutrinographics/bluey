---
id: I020
title: GATT server auto-respond on characteristic write
category: no-op
severity: critical
platform: android
status: fixed
last_verified: 2026-04-24
fixed_in: 3539a42
historical_ref: BUGS-ANALYSIS-#7, BUGS-ANALYSIS-ANDROID-A4
---

## Symptom

The Android GATT server sends `GATT_SUCCESS` to the remote central the instant `onCharacteristicWriteRequest` fires, before Flutter has a chance to see the write. The Dart-side `server.respondToWrite(...)` is a no-op — the ATT response was already on the wire. This breaks the stress-test `DelayAckCommand` and `DropNextCommand`, makes write-rejection impossible, and means the value sent in the response is `value` (echoed) instead of the empty payload the spec requires.

## Location

Auto-response: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:460-473` (inside `onCharacteristicWriteRequest`).

No-op: `GattServer.kt:207-219` — `respondToWriteRequest()` returns `Result.success(Unit)` without touching `gattServer`.

## Root cause

Comments in the source admit it: *"Auto-respond if needed (simplified implementation)"* and *"This is a simplified implementation - a production version would track pending requests with their associated device."* The `pendingWriteRequests` tracking was never wired.

## Notes

Fix sketch (mirrors iOS `PeripheralManagerImpl.respondToWriteRequest` at `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:164-172`):

1. Add `pendingWriteRequests: MutableMap<Long, PendingWrite>` (device + offset), guarded by a lock — binder thread writes, main thread pops.
2. In `onCharacteristicWriteRequest`: if `responseNeeded && !preparedWrite`, stash the entry and post to Flutter; do NOT call `sendResponse`.
3. In `respondToWriteRequest`: pop the entry; call `sendResponse(device, requestId, status.toAndroidStatus(), offset, null)` — write responses have no payload (current code incorrectly echoes `value`).
4. Drain `pendingWriteRequests` for the device on disconnect.
5. Leave `preparedWrite=true` and the `responseNeeded=false` paths alone (for now — see I050 for prepared writes).

Missing glue: `GattStatusDto.toAndroidStatus()` may not exist yet; add if needed. Mirror the mapping from the iOS `toCBATTError()` extension.

This is the entry point for fixing the stress-test timeout probe when Android is the server.

Related: I021 (same pattern for reads — coherent to fix together), I022 (descriptor read has no Dart API at all).
