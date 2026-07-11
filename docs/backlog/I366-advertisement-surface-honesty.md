---
id: I366
title: Fill or remove the advertisement fields the pipeline never populates
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-07-10
related: [I014, I052]
---

## Symptom

Scan results promise data that is never real: `isConnectable` is
hardcoded `true`, `serviceData` is always empty, `txPowerLevel` always
null (the platform DTO carries neither), and the `ScanMode` enum has
zero references (audit DA-23).

## Location

`bluey/lib/src/discovery/bluey_scanner.dart` (hardcoded fields);
`bluey_platform_interface` `PlatformDevice` (missing fields); native
advertisement parsing on both platforms.

## Notes

Thread the fields through `PlatformDevice` and native parsing — or
remove them until supported. Wire or delete `ScanMode`. Adjacent to
[I014](I014-manufacturer-data-only-first-entry.md) and
[I052](I052-scan-options-not-exposed.md); consider doing the
advertisement-data plumbing as one pass.
