---
id: I382
title: Stop the platform scan when a scanning Scanner is disposed
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-11-27
fixed_in: fcfc6d1
related: [I094]
---

## Symptom

Disposing a `Scanner` while it is scanning never stops the platform scan. The native scan keeps running until the next scan or an explicit stop.

## Location

`bluey/lib/src/discovery/bluey_scanner.dart:349` — `dispose()`.

## Root cause

`dispose()` closes the Dart side and never calls `stopScan`. The domain, the adapter and the native class each hold their own idea of "scanning", and nothing reconciles them.

## Notes

Found by finding M5 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 2 (scanning and advertising sessions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Related to [I094](I094-scanner-controller-never-closed.md). Closes with the scanning session, which owns the state of the scan. Test: group `M5 (I382)` in `bluey/test/known_defects/domain_known_defects_test.dart`.

## Fixed

Slice 2, scanning pull request ([design](../superpowers/specs/2026-11-27-scanning-and-advertising-sessions-design.md)). Disposing a scanner makes each of its scans leave, and the last scan to leave stops the radio (`fcfc6d1`). The known-defect test (M5) moved into the regular suite.
