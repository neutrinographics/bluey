---
id: I392
title: Make `services()` cache, dispose and announce consistently
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-11-17
---

## Symptom

`services()` re-discovers on every call by default, swaps the cached service objects without disposing the old ones, and does not emit on `servicesChanges`.

## Location

`bluey/lib/src/connection/bluey_connection.dart:632`.

## Root cause

Found by reading. The discovery result is cached, replaced and announced by three code paths that do not agree.

## Notes

Found by finding L7 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 6 (what is left) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Closes in slice 6, when GATT Client is placed. No known-defect test yet.
