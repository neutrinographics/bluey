---
id: I314
title: Example app's ConnectionCubit doesn't refresh services on Service Changed
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 53d5764
related: [I305]
---

## Symptom

Cold-start cross-platform reproduction (iOS as server / Android as
client): the example app's "Stress Tests" button — gated on
`state.services` containing the stress service UUID — does not appear
when the Android client first connects, even though the BLUEY badge
correctly identifies the iOS device as a Bluey peer. Pressing the
services refresh icon makes the button appear. After one disconnect /
reconnect cycle the button shows immediately on subsequent connects.

## Location

`bluey/example/lib/features/connection/presentation/connection_cubit.dart`
— `connect()` was calling `loadServices()` once on connect, but did
not subscribe to `connection.servicesChanges`.

## Root cause

The library's `BlueyConnection` clears its cache and re-discovers
whenever a Service Changed indication arrives (or a stale-cache
refresh fires on Android), then emits the fresh list on
`Connection.servicesChanges`. `Bluey.watchPeer`
(`bluey/lib/src/bluey.dart:563`) subscribes to that hook and re-runs
`tryUpgrade` on each emission — that's why the BLUEY badge appears
even when the initial discovery was incomplete.

`ConnectionCubit` did not have an equivalent subscription. After the
initial `loadServices()`, `state.services` stayed frozen at the stale
snapshot. The cubit's only paths to update it were:

1. A `ready → ready` re-emit on `stateChanges` (won't fire on
   re-discovery — `_setState` no-ops same-state transitions).
2. The user pressing the refresh button.

Likely upstream cause for the stale initial discovery: Android
`BluetoothGatt` cache from a prior session returns a partial service
tree on the first connect; iOS pushes Service Changed (or the cache
self-invalidates) and the library re-discovers — but the cubit doesn't
notice. The library does the right thing; the consumer just had to
listen.

## Notes

Fixed in `53d5764`. `ConnectionCubit` now subscribes to
`connection.servicesChanges` in `connect()` and emits
`state.copyWith(services: ...)` on each emission. Cancellation
parallels `_stateSubscription` / `_peerSubscription` (settings change,
`disconnect()`, `close()`).

Refresh button removed. With auto-update wired up, the only remaining
purpose was force-rediscovery for debugging, which disconnect/reconnect
already provides. The demo app should demonstrate the right consumer
pattern, not a "click here when broken" affordance. `SectionHeader`
hides the refresh icon and spinner when `onRefresh: null` and
`isRefreshing: false`, leaving just the count badge — preserves the
visual on screens that still pass a callback (scanner, service
explorer).

Library was already correct (post-I088 / I307). This was a
consumer-pattern bug: `Bluey.watchPeer`'s `servicesChanges`
subscription is the canonical pattern that any UI gating on specific
services must mirror.

**Documentation follow-up worth considering** (not blocking): mention
on `Connection.services` / `Connection.servicesChanges` dartdoc that
consumers gating UI on specific services should subscribe to
`servicesChanges`. Filed mentally; not tracked separately.
