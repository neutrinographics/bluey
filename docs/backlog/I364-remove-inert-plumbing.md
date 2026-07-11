---
id: I364
title: Remove or wire the inert plumbing: user-op accounting and dead exception types
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

Two promised mechanisms don't exist at runtime (audit DA-20, DA-21
remainder):

- user-op accounting (defer heartbeat probes while a user GATT op is
  in flight, I097) is permanently disengaged — characteristics are
  built with no lifecycle client, so every hook is a no-op outside
  tests
- `GattException` + `GattStatus` are dead types superseded by
  `GattOperationFailedException`; consumers can write catch blocks
  that never fire

(The other half of DA-21 — `ConnectionException` never constructed —
was fixed 2026-07-10.)

## Location

`bluey/lib/src/connection/bluey_connection.dart` (inert hooks);
`bluey/lib/src/shared/exceptions.dart` (dead types).

## Notes

Decide per mechanism: wire it for real via the peer path, or delete
the plumbing. Dead types should be removed with a CHANGELOG note.
