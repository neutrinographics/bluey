---
id: I076
title: "`_handleServiceChange` swallows all exceptions silently"
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
---

## Symptom

`BlueyConnection._handleServiceChange()` re-discovers services and re-runs the Bluey-control-service upgrade path. Both can fail (discovery timeout, disconnect mid-discovery, bogus services). The catch at line 478 is `catch (_)` with a comment "Service discovery failed -- stay as raw connection" — no log, no error propagation to callers, no `onError` on the state stream. If upgrade was supposed to happen and failed, the user has no visibility.

## Location

`bluey/lib/src/connection/bluey_connection.dart:471-482`.

## Root cause

Defensive catch-all with no logging or escalation path.

## Notes

Fix: at minimum, `dev.log(...)` with `level: 900` (warning) or `1000` (severe) so the failure lands in Flutter's devtools logs. Optionally, surface as an error on a dedicated "lifecycle events" stream or re-enter the control service discovery on the next state event.

Low-to-medium: most users don't observe service-change events frequently. But when it bites, it's confusing — "the peer's services changed and now nothing works" with no diagnostic trace.
