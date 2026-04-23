---
id: I002
title: GATT operations not gated by connection state
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#4
---

## Symptom

Calling `services`, `readCharacteristic`, `writeCharacteristic`, `readRssi`, `requestMtu`, etc. on a disconnected connection throws a raw `PlatformException` instead of the domain-level `DisconnectedException`. Callers writing reconnection logic can't pattern-match on Bluey's own exception types.

## Location

`bluey/lib/src/connection/bluey_connection.dart:719-754` — `read()` / `write()` / all GATT paths. None call `_ensureConnected()` or equivalent; they go straight to the platform.

## Root cause

There's no pre-flight check that the connection is still in `ConnectionState.connected` before delegating to the platform layer. The platform call fails with whatever native error surfaces, which bypasses Bluey's typed exception hierarchy.

## Notes

Fix sketch: add a private `_ensureConnected()` that throws `DisconnectedException(deviceId, DisconnectReason.unknown)` if `_state != connected`. Call it at the top of every public GATT-op method on `BlueyConnection` and pass a connection reference to `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor` so they can call it too.

Also add a post-hoc check: if a platform error is thrown and `_state` has since changed to `disconnected`, rewrap as `DisconnectedException(..., DisconnectReason.linkLoss)`.

Related: I001 (ensures `_state` transitions are clean so this check is reliable).
