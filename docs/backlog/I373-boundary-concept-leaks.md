---
id: I373
title: Move Bluey-protocol concepts out of the platform enum; centralize exception classification
category: refactor
severity: medium
platform: domain
status: open
last_verified: 2026-11-17
---

## Symptom

`PlatformGattStatus.lifecycleEviction` embeds a Bluey-protocol concept
in an otherwise BLE-generic platform enum, and `lifecycle_client.dart`
classifies raw platform exception types outside the ACL — two extra
places that must change when the platform taxonomy does (audit DA-32;
both currently intentional and documented).

## Notes

Model eviction as a generic application-range status; extract one
domain helper for platform-exception classification on the
pre-translation path.

## Audit 2026-11-17

Measured by the `boundaries` list in `test/architecture/known_violations.dart`. Closed by slice 5 (server and peer). Each entry on those lists leaves in the commit that fixes it, so the lists show how far this has come. See [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md) and the architecture foundation [design](../superpowers/specs/2026-11-17-architecture-foundation-design.md).
