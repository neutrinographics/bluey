---
id: I021
title: GATT server auto-respond on characteristic read
category: no-op
severity: critical
platform: android
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#7
related: [I020]
---

## Symptom

On a central's read request, the Android GATT server auto-responds with `characteristic.value` — the Android-managed cached value, typically empty or stale — instead of whatever the Dart-side `onReadRequest` handler would return. The Dart-side `server.respondToRead(..., value: ...)` is a no-op. Dynamic read handlers are impossible, read authorization can't be enforced, and the value every client sees is whatever the native layer happens to have cached.

## Location

Auto-response: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:422-434` (inside `onCharacteristicReadRequest`).

No-op: `GattServer.kt:188-205` — `respondToReadRequest()` returns `Result.success(Unit)` without touching `gattServer`.

## Root cause

Same design as I020, labelled *"Auto-respond with success for now (simplified implementation). A production version would wait for respondToReadRequest."*

## Notes

Fix sketch: same shape as I020, but with value payload.

1. `pendingReadRequests: MutableMap<Long, PendingRead>` (device + offset).
2. `onCharacteristicReadRequest`: stash, post to Flutter, do NOT `sendResponse`.
3. `respondToReadRequest(requestId, status, value)`: pop, `sendResponse(device, requestId, status.toAndroidStatus(), offset, value ?: ByteArray(0))`.
4. Drain on disconnect.

Should land in the same PR as I020 since they share the `pendingXxxRequests` scaffolding, the lock, the status mapping, and the disconnect drain.
