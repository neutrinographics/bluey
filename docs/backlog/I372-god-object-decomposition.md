---
id: I372
title: Decompose the five god-objects incrementally
category: refactor
severity: low
platform: both
status: open
last_verified: 2026-07-10
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
