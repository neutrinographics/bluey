---
id: I061
title: "`ConnectionManager.cleanup()` orphans pending callbacks"
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`cleanup()` is called during activity destroy / engine detach. It calls `gatt.disconnect()` on every connection, clears `connections` and `queues` maps, clears `pendingConnections`, but does **not invoke** the orphaned callbacks. Any `Future` waiting on an in-flight connect, read, write, MTU request, etc. hangs forever.

In practice this shows up as: user calls `bluey.connect(device)` which returns a pending future; the host app is killed / backgrounded / Bluetooth disabled, triggering `cleanup()`; the future never resolves. The Dart-side resource (including the caller's own cleanup logic) is stuck.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:406-446` — `cleanup()`:

```kotlin
fun cleanup() {
    for (deviceId in deviceIds) {
        try { connections[deviceId]?.disconnect() } catch (...) {}
    }
    connections.clear()
    queues.clear()                        // ← queued ops lost; their completions never fire
    // ... (removes timeouts) ...
    pendingConnections.clear()            // ← pending connect callbacks orphaned
    pendingServiceDiscovery.clear()
    pendingReads.clear()                  // ← (note: these legacy maps are dead, but the contract is still broken)
    // ... etc ...
}
```

## Root cause

Two-part issue:

1. `queues.clear()` discards the `GattOpQueue` instances without calling `drainAll` on each. Pending ops inside the queues (with their Dart-side callbacks) are orphaned.
2. `pendingConnections.clear()` removes connect callbacks without invoking them.

## Notes

Fix sketch:

```kotlin
fun cleanup() {
    val error = FlutterError("gatt-disconnected", "cleanup in progress", null)
    for ((_, queue) in queues) {
        queue.drainAll(error)
    }
    queues.clear()

    val connectError = BlueyAndroidError.GattConnectionCreationFailed // or dedicated cleanup error
    val callbacksToFail = pendingConnections.values.toList()
    pendingConnections.clear()
    for (cb in callbacksToFail) {
        cb(Result.failure(connectError))
    }

    // ... rest of existing cleanup ...
}
```

Note the order: drain queues and fail pending connects **before** calling `gatt.disconnect()` / `gatt.close()` so the completions don't race with `onConnectionStateChange(DISCONNECTED)` callbacks that might re-fire them.

Related: I060 (disconnect fire-and-forget). If I060 is fixed by adding `pendingDisconnects`, that map also needs cleanup-time failure.
