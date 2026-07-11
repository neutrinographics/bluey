---
id: I368
title: Make dispose terminal: reject post-dispose use of Scanner and Server
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
related: [I094, I095]
---

## Symptom

Neither `BlueyScanner.dispose` nor `BlueyServer.dispose` sets the
invalidation flag `_ensureValid` checks, so a post-dispose `scan()` /
`addService` passes validation and partially restarts over closed
controllers (audit DA-26).

## Location

`bluey/lib/src/discovery/bluey_scanner.dart`,
`bluey/lib/src/gatt_server/bluey_server.dart`.

## Notes

Set a terminal disposed flag; reject in `_ensureValid`. Same lifecycle
family as the never-closed controllers
([I094](I094-scanner-controller-never-closed.md),
[I095](I095-server-controllers-never-closed.md)) — consider one pass.
