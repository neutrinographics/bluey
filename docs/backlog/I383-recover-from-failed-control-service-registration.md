---
id: I383
title: Recover from a failed control-service registration
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-11-17
related: [I005]
---

## Symptom

If the eager control-service registration fails, the error is unhandled at `server()`, and every later `addService` and `startAdvertising` rethrows the same cached raw platform exception. The server cannot recover. On iOS the peripheral manager can still be starting when the central manager already reports `on`.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart:151-152`.

## Root cause

The registration future is started once, unsupervised, and its failure is cached as the answer to every later call instead of being retried or translated.

## Notes

Found by finding M6 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 5 (server and peer) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Related to [I005](I005-async-init-without-error-handling.md), the same unsupervised-init shape on the client side. Test: group `M6 (I383)` in `bluey/test/known_defects/domain_known_defects_test.dart`.
