---
id: I044
title: iOS disconnect of an already-disconnected peripheral waits for timeout
category: bug
severity: low
platform: ios
status: open
last_verified: 2026-04-23
---

## Symptom

Calling `disconnect(deviceId)` on a peripheral that is already in state `.disconnected` enqueues a completion with a 30-second timeout, then calls `centralManager.cancelPeripheralConnection(peripheral)` — which is a no-op when the peripheral isn't connected, so `didDisconnectPeripheral` never fires. The caller waits 30 seconds for a timeout error instead of getting an immediate success.

Domain-layer code that defensively "belt-and-suspenders" calls `disconnect()` in cleanup paths will hang for 30 seconds per already-disconnected call.

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift:181-195` — `disconnect()` doesn't check `peripheral.state` before enqueueing.

## Root cause

Missing early-return for the already-disconnected case.

## Notes

Also: the 30-second timeout is hardcoded (line 191), not configurable via `BlueyConfig`. Worth making it match the `connectTimeout` field or adding a dedicated `disconnectTimeoutMs` config field.

Fix sketch:

```swift
if peripheral.state == .disconnected {
    completion(.success(()))
    return
}
```

Before enqueueing. Similar check likely warranted on Android — worth cross-checking as part of I015 or a parallel Android cleanup entry.

Related: the `peripheral.state == .connecting` case is also ambiguous — user says disconnect while connection is in progress. Current behavior: enqueue disconnect slot, call `cancelPeripheralConnection` — this *does* cancel the pending connect per CoreBluetooth semantics, which fires `didFailToConnect`. The connect slot's entry fails; the disconnect slot's entry waits for `didDisconnectPeripheral` which may not fire for a connection-that-never-completed. Needs testing.
