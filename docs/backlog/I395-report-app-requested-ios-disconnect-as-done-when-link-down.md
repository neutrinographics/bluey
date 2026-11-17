---
id: I395
title: Report an app-requested iOS disconnect as done when the link is down
category: bug
severity: low
platform: ios
status: open
last_verified: 2026-11-17
---

## Symptom

A disconnect the app requested reports failure when the link happened to drop with an error, although the link is down. `closeServer` also leaves pending requests and a pending advertising completion unanswered.

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift:561-567`.

## Root cause

Found by reading. The disconnect completion treats any error on the drop as a failed disconnect, and `closeServer` does not drain what is pending.

## Notes

Found by finding L10 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 4 (native completions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Closes in slice 4, after the iOS central seam of [I350](I350-ios-central-manager-delegate-seam.md) makes it testable. No known-defect test yet.
