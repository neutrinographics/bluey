---
id: I078
title: `LifecycleClient.recordActivity()` silently drops signals during `start()` → interval-read window
category: bug
severity: low
platform: both
status: fixed
last_verified: 2026-04-25
fixed_in: 2faf062
related: [I077]
---

## Symptom

`LifecycleClient.recordActivity()` early-returns when `isRunning == false`. `isRunning` is defined as `_probeTimer != null`, so it reports `false` during the window between `start()` setting `_heartbeatCharUuid` and `_beginHeartbeat()` being called from the interval-char read's `.then` callback. If any `BlueyConnection` GATT op completes during that window, its activity signal is silently discarded.

The window is typically sub-second on real hardware (a Pigeon round-trip for the interval read) but can stretch if the server is slow to respond.

## Location

`bluey/lib/src/connection/lifecycle_client.dart:56-61` — the `isRunning` check at the top of `recordActivity`.

## Root cause

`isRunning` uses `_probeTimer != null` as its sentinel, but the probe timer is only armed inside `_beginHeartbeat()`, which runs after the interval-char read completes. `_heartbeatCharUuid` is set earlier in `start()` (line 84) and is the more accurate "lifecycle is active" sentinel.

The early return is intentionally defensive — it's supposed to prevent lingering notification subscriptions from dirtying monitor state after `stop()`. But conflating "timer armed" with "client active" creates the start-window gap.

## Notes

Pre-existed the I077 deadline-scheduling fix (the old polling code had the same `isRunning` guard). The new scheduler is slightly more sensitive because the deadline is now set strictly from what the monitor knows — a dropped activity signal pushes the next probe forward by less than it should.

Fix sketch: gate `recordActivity()` on `_heartbeatCharUuid != null` instead of `isRunning`. Both resolve to `null` after `stop()` (stop clears both), so the post-stop semantics are preserved; during `start()`, `_heartbeatCharUuid` is set *before* any early returns, closing the window.

Alternative: keep the `isRunning` guard but document the window semantics explicitly (weaker — doesn't fix the drop, just warns).

Low severity — real-world impact is a slightly-early first probe in rare cases. Not a user-visible bug on its own. Surfaced during the I077 code review.
