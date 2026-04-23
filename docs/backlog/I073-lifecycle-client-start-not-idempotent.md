---
id: I073
title: "`LifecycleClient.start()` is not idempotent"
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-23
related: [I070]
---

## Symptom

Calling `LifecycleClient.start(allServices:)` twice before the first's interval-read has resolved overwrites `_heartbeatCharUuid` and schedules a second chained flow. If both `.then` callbacks fire, two `Timer.periodic` instances end up running — classic double-start.

## Location

`bluey/lib/src/connection/lifecycle_client.dart:64-65` (approximately — `start()` entry).

## Root cause

No guard at `start()` entry checking for already-started.

## Notes

Fix: `if (_heartbeatCharUuid != null) return;` (or better, a `_started` flag that's only cleared by `stop()`). The `_heartbeatCharUuid` field isn't reliable as a sentinel because the interval read might not have completed yet — use a dedicated flag.

Low severity because the caller (`BlueyConnection._tryUpgrade`) only calls `start()` once in normal flow. This is defensive hygiene against a future caller that doesn't know the invariant.
