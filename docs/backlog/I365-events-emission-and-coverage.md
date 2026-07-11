---
id: I365
title: Emit the missing domain events, test the event bus, and define the events-vs-logs split
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

`bluey.events` shows every connect but no disconnect:
`DisconnectedEvent`, `DebugEvent`, `ReadRequestEvent`,
`WriteRequestEvent` are declared but never emitted, 13 *emitted* event
types have zero test assertions, and every lifecycle signal
double-emits on both `events` and `logEvents` with inconsistent guards
— the dual-maintenance that let the dead events rot (audit DA-22,
DA-36).

## Location

`bluey/lib/src/events.dart`; emission sites across connection/server;
`lifecycle_client.dart` double-emission.

## Notes

Emit `DisconnectedEvent` at the disconnect site; wire or delete the
request/debug events; assert the event bus in connect/server
integration tests; document which channel owns what and make the
address guards consistent.
