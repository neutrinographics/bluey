---
id: I393
title: Make `tryUpgrade` idempotent
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-11-17
---

## Symptom

Calling `tryUpgrade` twice on one connection starts two lifecycle clients, so heartbeats and presence subscriptions double.

## Location

`bluey/lib/src/bluey.dart:565`.

## Root cause

Found by reading. Nothing records that a connection has already been upgraded.

## Notes

Found by finding L8 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 5 (server and peer) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Closes in slice 5, when Peer owns both halves of the lifecycle protocol. No known-defect test yet.
