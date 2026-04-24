---
id: I070
title: LifecycleClient late promise callbacks can fire after `stop()`
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-25
fixed_in: 136fa47
---

## Symptom

`LifecycleClient.stop()` cancels the periodic probe timer and clears state, but in-flight probe futures (`readCharacteristic` / `writeCharacteristic` issued by a prior tick) are not cancellable. When those futures resolve after `stop()`, their `.then()` / `.catchError()` callbacks still execute:

- The interval-read `.then()` at `lifecycle_client.dart:99-107` calls `_beginHeartbeat()` → **creates a new `Timer.periodic`** even though `stop()` ran. Leaked timer keeps ticking on a supposedly-dead client.
- Probe result callbacks (`recordProbeSuccess` / `recordProbeFailure`) mutate `_monitor` state after the client is supposed to be inert.
- `_tick()` doesn't check `isRunning`, so leaked timers keep calling `shouldSendProbe` and consuming state cycles.

## Location

`bluey/lib/src/connection/lifecycle_client.dart:97-107` (interval-read `.then` re-entering `_beginHeartbeat`), `:153-156` (`_tick` not guarded), `:170-195` (probe completion mutates monitor without guard).

## Root cause

No "running" sentinel checked inside promise callbacks. `stop()` clears local state but can't recall promises that were dispatched before it ran.

## Notes

Fix sketch: add `bool _isRunning` guarded by `stop()`. Every promise callback (`.then` / `.catchError`) checks `if (!_isRunning) return;` before mutating state or scheduling new work. `_tick()` also checks.

Subtler: if `stop()` is called *during* a `.then` callback's execution (reentrant via `onServerUnreachable` → `disconnect` → `_cleanup` → `_lifecycle.stop`), the callback needs to bail before further state mutation. The flag approach handles this.

Consequence in production: a connection that was supposed to be torn down keeps sending heartbeat probes from a leaked timer. Over many disconnect cycles, this compounds into many ghost timers.
