---
id: I062
title: "Threading violation: `onConnectionStateChange` mutates main-thread state from binder thread"
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-26
related: [I060, I061, I064, I098]
---

## Symptom

Android's `BluetoothGattCallback` methods fire on binder IPC threads. Phase 2a's threading contract states *"all state mutation on the main-looper thread"* and most ops correctly wrap their queue access in `handler.post { ... }`. But `onConnectionStateChange` (both `STATE_CONNECTED` and `STATE_DISCONNECTED` branches) mutates non-queue maps directly on the binder thread while those same maps are read and written from main-thread code paths.

Data race territory. Lost writes, stale reads, map corruption, and occasional inexplicable hangs are the classic JVM-level consequences of concurrent `MutableMap` access.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:500-558` — the `onConnectionStateChange` override.

Specific offenders:

- **Line 509** (STATE_CONNECTED): `pendingConnectionTimeouts.remove(deviceId)` — mutates map on binder thread. The map is written on main (line 159) and read/removed in the timeout Runnable on main (line 142). Three-way race.
- **Line 527** (STATE_DISCONNECTED): `queues.remove(deviceId)` — mutates the queues map on binder. The map is read on every public GATT-op entry point (via `queueFor`) on main thread.
- **Line 537** (STATE_DISCONNECTED): `cancelAllTimeouts(deviceId)` — mutates every `pendingXxxTimeouts` map on binder.
- **Line 539** (STATE_DISCONNECTED): `pendingConnections.remove(deviceId)` — mutates map on binder. Map is written on main (line 137) and cleared on main (line 438).
- **Line 551** (STATE_DISCONNECTED): `connections.remove(deviceId)` — mutates map on binder. Map is read on every op entry point on main.

Only the queue-operation branch inside STATE_CONNECTED (line 510-517) is correctly wrapped in `handler.post`. The timeout removal at line 509 *outside* that block is the race.

## Root cause

Phase 2a's design cleanly threaded queue state through `handler.post`, but the surrounding non-queue bookkeeping was left on the binder thread. Easy to miss: the queue is the most visibly "concurrent" thing in the file, so it got the attention.

## Notes

Fix sketch: wrap the entire body of each `when` branch in `handler.post { ... }`, not just the queue access. Pattern:

```kotlin
BluetoothProfile.STATE_CONNECTED -> {
    notifyConnectionState(deviceId, ConnectionStateDto.CONNECTED)
    handler.post {
        pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
        queues[deviceId] = GattOpQueue(gatt, handler)
        pendingConnections.remove(deviceId)?.invoke(Result.success(deviceId))
    }
}
```

`notifyConnectionState` already internally posts to main, so keeping it outside the wrapper is fine. `handler.removeCallbacks` and `Handler.post` are thread-safe, but everything else isn't.

Symptom profile when this bites: intermittent "connection succeeded but GATT ops fail with DeviceNotConnected" (because `connections.remove` from binder raced with `connections[deviceId]` read from main), or "connection failed silently" (timeout-cancel raced with timeout-fire). Hard to reproduce, hard to diagnose — classic data-race fingerprints.

Worth a targeted test: use `ThreadPoolExecutor`-based multi-connect stress in the example app with `StrictMode` enabled to catch cross-thread violations.

Related: may manifest most easily with the stress test's soak scenario, which hammers GATT ops across connect/disconnect cycles.

**2026-04-26 deep-review confirmation:** External review confirms the diagnosis is exact and the fix sketch is the correct approach. Bundle with I060/I061/I064 per I098 (rewrite spec) for coherent single-PR fix.
