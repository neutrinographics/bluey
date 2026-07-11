---
id: I373
title: Move Bluey-protocol concepts out of the platform enum; centralize exception classification
category: refactor
severity: low
platform: domain
status: open
last_verified: 2026-07-10
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
