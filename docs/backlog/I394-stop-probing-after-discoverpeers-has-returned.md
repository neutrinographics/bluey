---
id: I394
title: Stop probing after `discoverPeers` has returned
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-11-17
related: [I380]
---

## Symptom

A device seen as the scan window closes is probed after `discover()` has returned, and the probe can collide with the caller's next connect. A `stopScan` failure also hides the results.

## Location

`bluey/lib/src/peer/peer_discovery.dart:166-190`.

## Root cause

Found by reading. Probes started during the scan are not awaited before the result is returned, and the `stopScan` call is not guarded.

## Notes

Found by finding L9 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 1 (link lifecycle) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Fixed with [I380](I380-stop-peer-discovery-disconnecting-links-in-use.md), which reworks the same probing. Closes in slice 1. No known-defect test yet.
