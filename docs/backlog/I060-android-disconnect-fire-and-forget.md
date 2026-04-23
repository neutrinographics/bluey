---
id: I060
title: Android `disconnect()` is fire-and-forget, doesn't wait for confirmation
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`ConnectionManager.disconnect()` calls `gatt.disconnect()` (async) then immediately invokes `callback(Result.success(Unit))`. The caller's `await connection.disconnect()` resolves before the peripheral has actually disconnected — `onConnectionStateChange(STATE_DISCONNECTED)` fires later. Subsequent code that assumes "disconnect is complete" can race with the actual teardown: pending ops still in flight, `gatt.close()` not called, connection state briefly still `.disconnecting`.

iOS's implementation correctly enqueues a `disconnectSlot` and waits for the platform callback before completing. Android doesn't.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:176-192`:

```kotlin
fun disconnect(deviceId: String, callback: (Result<Unit>) -> Unit) {
    val gatt = connections[deviceId]
    if (gatt == null) {
        callback(Result.success(Unit))
        return
    }

    try {
        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
        gatt.disconnect()
        callback(Result.success(Unit))  // ← fires immediately, not on STATE_DISCONNECTED
    } catch (e: SecurityException) { ... }
}
```

## Root cause

Missing pending-disconnect-callback map and wire-up from `onConnectionStateChange(STATE_DISCONNECTED)`.

## Notes

Fix sketch (mirror iOS):

1. Add `pendingDisconnects: MutableMap<String, (Result<Unit>) -> Unit>`.
2. In `disconnect()`: stash callback, call `gatt.disconnect()`, return without invoking callback.
3. In `onConnectionStateChange(STATE_DISCONNECTED)`: if `pendingDisconnects[deviceId]` exists, invoke it with success (and remove); otherwise proceed to the existing connect-failure path.
4. Also gate on `peripheral.state` to early-complete if already disconnected (parallel to I044 on iOS).
5. Add a disconnect timeout (e.g., 10s) — if `onConnectionStateChange` never fires, fail the callback. Android's `disconnect()` is fire-and-forget at the OS level; occasionally the callback genuinely doesn't arrive.

Related: this bug compounds with I062 (threading violation in `onConnectionStateChange`) — fix both together to avoid introducing new races in the disconnect handler.
