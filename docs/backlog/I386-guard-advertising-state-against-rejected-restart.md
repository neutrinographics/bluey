---
id: I386
title: Guard advertising state against a rejected restart
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-11-17
related: [I385]
---

## Symptom

`startAdvertising` has no state guard. A rejected restart rolls the state back to `idle` while the radio still advertises, and `stopAdvertising()` becomes a no-op. A platform error during stop strands the state in `stopping`.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart:606`, `:709`.

## Root cause

The advertising state is rolled back by hand on each failure path, so a failure that leaves the radio in a different state than the rollback assumes leaves the domain stale.

## Notes

Found by finding L1 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 2 (scanning and advertising sessions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Closes with the advertising session in slice 2. Test: group `L1 (I386)` in `bluey/test/known_defects/domain_known_defects_test.dart`.
