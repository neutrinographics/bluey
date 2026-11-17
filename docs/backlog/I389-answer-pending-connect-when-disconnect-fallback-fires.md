---
id: I389
title: Answer a pending connect when the disconnect fallback fires
category: bug
severity: low
platform: android
status: open
last_verified: 2026-11-17
---

## Symptom

When the 5 s disconnect fallback fires, the disconnect completes but a pending connect to the same device is left unanswered, and the domain has no way to cancel a connect in flight.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:249-280`.

## Root cause

Found by reading. The fallback completes only the disconnect callback and does not fail the connect that was waiting on the same device.

## Notes

Found by finding L4 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 4 (native completions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Closes in slice 4. No known-defect test yet.
