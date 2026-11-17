---
id: I372
title: Decompose the five god-objects incrementally
category: refactor
severity: medium
platform: both
status: open
last_verified: 2026-11-17
---

## Symptom

`BlueyConnection` (~957 LOC), `BlueyServer` (~1099), Kotlin
`ConnectionManager` (1088) / `GattServer` (1260), Swift
`CentralManagerImpl` (999) each carry 6-10 responsibilities. No
boundary violations — but they concentrate change-risk and are where
the subtle handle/concurrency bugs hide (audit DA-31).

## Notes

Incremental, not big-bang: extract enum/DTO mappers, the stream-replay
helper, per-device op registries. The Swift decomposition pairs
naturally with [I350](I350-ios-central-manager-delegate-seam.md).

## Audit 2026-11-17

Measured by the `oversized` list in `test/architecture/known_violations.dart` of each of the four packages. Closed by slices 1, 4 and 5 for the largest classes, and slice 6 (what is left) emptying the lists. Each entry on those lists leaves in the commit that fixes it, so the lists show how far this has come. See [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md) and the architecture foundation [design](../superpowers/specs/2026-11-17-architecture-foundation-design.md).
