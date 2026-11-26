---
id: I397
title: Emit Android's DISCONNECTING only after gatt.disconnect() succeeds
category: bug
severity: low
platform: android
status: open
last_verified: 2026-11-18
related: [I395]
---

## Symptom

None an app sees today. A local disconnect request that the plugin then fails still sends a `DISCONNECTING` connection state, so Dart is told the link is closing although it stays up. The Dart side filters it: `DisconnectEcho` (`bluey_android/lib/src/disconnect_echo.dart`), which the Android connection manager asks before it passes a report on, drops the next `disconnecting` report after a disconnect is asked, so a failed `disconnect()` leaves the Connection usable.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:257` (the `notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)` call), before `gatt.disconnect()` and its two `catch` blocks (`:259-268`).

## Root cause

The plugin reports the request as a state: it emits `DISCONNECTING` before it calls `gatt.disconnect()`, on every local request, so the two failure paths that leave the link up come with the echo. On those paths the failed answer reaches Dart before the echo.

## Notes

Move the emit after a successful `gatt.disconnect()`. Once it moves, `DisconnectEcho` and its two call sites in `AndroidConnectionManager` can stay (they are inert when no echo comes) or go. Found by the whole-branch review of slice 1's first pull request (link lifecycle, [design](../superpowers/specs/2026-11-18-link-lifecycle-design.md)).
