---
id: I007
title: Connection state init race (mitigated, not prevented)
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#1
---

## Symptom

`BlueyConnection` starts with `_state = ConnectionState.connected` on the assumption that it's constructed after a successful platform connect. If the link drops between the platform's connect-success callback and the first GATT op, `state` returns `connected` for a window even though the peer is gone.

## Location

`bluey/lib/src/connection/bluey_connection.dart:141-143` — `_state = ConnectionState.connected` initial assignment.

## Root cause

The initial value is a guess, not a query. The stream listener at line ~182 eventually corrects it, but there's no `await` gate: the connection is handed to the caller before the platform stream has emitted anything.

Mitigation already in place: the state listener will emit the correct value as soon as the platform reports it, so time-in-wrong-state is bounded by platform-callback latency.

## Notes

Low priority because the window is typically milliseconds. Proper fix: await a `getConnectionState(deviceId)` query (once that's exposed on the platform interface, currently it isn't) before returning from `Bluey.connect()`. Or simply start `_state` as `connecting` and require the platform stream to transition it — accept that callers see one intermediate `connecting` state right after construction.

Related: I002 (ops gated by state) depends on the state actually being trustworthy, so this and I002 share a motivation.
