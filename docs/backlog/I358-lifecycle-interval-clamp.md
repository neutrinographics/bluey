---
id: I358
title: Clamp malformed lifecycle intervals to a safe floor
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

A hostile or buggy peer serving a zero/negative heartbeat interval
drives the client's heartbeat scheduling to `Duration.zero` — a
busy-loop guarded only by an `assert` that release builds strip
(audit DA-10, latent).

## Location

`bluey/lib/src/lifecycle.dart` — `decodeInterval` guards length only;
`bluey/lib/src/connection/lifecycle_client.dart` — `_beginHeartbeat`.

## Notes

Clamp/reject non-positive decoded intervals to
`defaultLifecycleInterval`. The A.4 hostile-input tests (2026-07-10)
deliberately skipped this repro because it would hang under fakeAsync —
add the boundary test with the clamp.
