---
id: I396
title: Bound and validate lifecycle intervals before acknowledging them
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-11-17
---

## Symptom

`LifecycleInterval.decode` has a floor but no ceiling, and a malformed heartbeat is acknowledged before it is decoded.

## Location

`bluey/lib/src/lifecycle.dart`, `bluey/lib/src/gatt_server/lifecycle_server.dart`.

## Root cause

Found by reading. Decoding and acknowledging are in the wrong order, and the value object does not bound its upper end.

## Notes

Found by finding L11 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 5 (server and peer) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Follows [I358](I358-lifecycle-interval-clamp.md), which added the floor. Closes in slice 5. No known-defect test yet.
