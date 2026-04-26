---
id: I089
title: Rewrite Connection interface to use platform-tagged extensions for asymmetric features
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I066, I030, I031, I032, I035, I045, I065, I200]
---

## Symptom

Same as I066 — the cross-platform Connection interface declares platform-asymmetric methods (bond, removeBond, requestPhy, requestConnectionParameters, etc.). This entry is the architectural-rewrite counterpart, intended for spec hand-off.

## Location

`bluey/lib/src/connection/connection.dart:205-287` — Bonding, PHY, and Connection-Parameters sections.

## Root cause

See I066 — the interface was modeled as the union of features rather than the intersection plus platform-tagged extensions.

## Notes

See I066 for the proposed shape. The rewrite touches:

- `bluey/lib/src/connection/connection.dart` — interface.
- `bluey/lib/src/connection/bluey_connection.dart` — implementation; bond/PHY/conn-param logic moves to platform-tagged subclass or composition.
- All call sites in user code — breaking API change.

**Spec hand-off.** Suggested spec name: `2026-XX-XX-platform-tagged-connection-extensions-design.md`.
