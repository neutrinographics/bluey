---
id: I072
title: "`LifecycleServer.recordActivity` races with timer cancellation"
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
---

## Symptom

`LifecycleServer` tracks a per-client timeout timer. `recordActivity(clientId)` resets the timer when any activity is seen. `cancelTimer(clientId)` clears it on disconnect. Both check `containsKey(clientId)` before accessing the timer map. With async gaps, the check-then-mutate isn't atomic: `containsKey` returns true, then a concurrent `cancelTimer` removes the entry, then the reset tries to operate on the now-missing entry.

## Location

`bluey/lib/src/gatt_server/lifecycle_server.dart:125-129` (approximately — `recordActivity` path).

## Root cause

No guard; check-and-act pattern on a map mutated from multiple async contexts (write handler, disconnect handler, scheduled timer callbacks).

## Notes

Dart is single-threaded at the isolate level, so this isn't a true data race — the execution is serialized by the event loop. But async gaps between `await` points create reentrancy windows indistinguishable from a race for the developer. The fix is to make every path that touches the timer map atomic within its synchronous block, or to coalesce operations into a single method guarded by a single lookup.

Severity downgraded from Agent A's "high" based on Dart's single-threaded semantics — most interleavings are benign. Worth fixing defensively.
