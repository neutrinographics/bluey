---
id: I004
title: MTU not synced with platform-initiated changes
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#9
---

## Symptom

`Connection.mtu` returns a stale value (default 23, or last `requestMtu()` result) when the remote device initiates an MTU exchange. Code that chunks writes by `mtu - 3` under-uses the channel on Android when iOS bumps MTU to 185–517, and can over-write on exotic setups.

## Location

`bluey/lib/src/connection/bluey_connection.dart:144` — `_mtu` is initialized to 23 and only written in `requestMtu()` (line ~358).

On Android, `onMtuChanged` fires a Pigeon callback but the Dart side has no `mtuStream` subscription; the event is dropped.

On iOS, MTU is auto-negotiated with no Dart-visible callback (CoreBluetooth exposes `maximumWriteValueLength(for:)` per operation type).

## Root cause

No `mtuChanges` stream on `Connection`, and no platform wiring for remote-initiated MTU changes. Android has the callback but it's unused; iOS doesn't plumb the per-peripheral MTU at all.

## Notes

Fix sketch:

- Add `Connection.mtu` getter backed by a `StreamController<int>` and expose `Connection.mtuChanges`.
- On Android, wire `onMtuChanged` Pigeon callback through `BlueyAndroid` to the per-connection MTU controller. Update `_mtu` on every event.
- On iOS, poll `maximumWriteValueLength(for: .withResponse)` after `didConnect` / `peripheralIsReady(toSendWriteWithoutResponse:)` and emit the change.

Related to I051 (scan/advertising options) only in the sense that MTU is a first-class parameter that deserves first-class plumbing.
