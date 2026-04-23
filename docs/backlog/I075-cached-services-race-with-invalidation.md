---
id: I075
title: "`_cachedServices` race between `services()` and service-change invalidation"
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
---

## Symptom

`BlueyConnection.services()` returns `_cachedServices` if non-null; otherwise it re-discovers and caches. `_handleServiceChange()` (fired on a platform service-change event) sets `_cachedServices = null` and re-discovers. Between the two async paths, a caller can:

1. Call `services()`, see `_cachedServices == null`, start discovery.
2. Service-change fires; `_handleServiceChange` nulls `_cachedServices` and starts its own discovery.
3. Both complete, both write `_cachedServices`, last-writer-wins determines what the caller sees.

Or even more subtly: caller's local reference to `_cachedServices` from step 1's read is stale by the time they use it. Subsequent characteristic lookups may reference objects that were orphaned when `_handleServiceChange` replaced them.

## Location

`bluey/lib/src/connection/bluey_connection.dart:284-299` (the `services()` getter) and `:471-482` (`_handleServiceChange`).

## Root cause

Concurrent async access to a shared cache without a guard. `_upgrading` exists but doesn't cover the general service re-discovery case.

## Notes

Fix: a single async mutex / `Future<List<RemoteService>>?` sentinel. If a discovery is in flight, subsequent calls `await` the existing future. Service-change cancels the sentinel and starts a new one. Standard memoize-in-flight pattern.

Subtle additional concern: any `BlueyRemoteCharacteristic` references held by callers across a service-change are now orphaned — their underlying platform characteristic handle may be stale. Not a bug per se, but worth a doc note that characteristic references must not be cached across `onServicesChanged`.
