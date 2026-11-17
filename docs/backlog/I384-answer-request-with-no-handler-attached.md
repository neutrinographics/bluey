---
id: I384
title: Answer a request that arrives with no handler attached
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-11-17
related: [I357]
---

## Symptom

A read or write that arrives while nothing listens to `readRequests` or `writeRequests` is lost. The remote central waits out the 30 s ATT timeout, and that client's lifecycle timer stays paused meanwhile.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart:244`, `:274`.

## Root cause

The request is added to a broadcast controller, which drops events when it has no listener, and nothing answers the platform request in that case.

## Notes

Found by finding M7 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 5 (server and peer) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Related to [I357](I357-stream-errors-bypass-acl.md). The slice also takes the Bluey protocol out of the server, so a request with no app handler has one owner. Test: group `M7 (I384)` in `bluey/test/known_defects/domain_known_defects_test.dart`.
