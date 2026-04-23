---
id: I006
title: BlueyCentral MAC → UUID truncation
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#12
---

## Symptom

`BlueyCentral.id` converts a MAC-format `platformId` (e.g. `AA:BB:CC:DD:EE:FF` — 17 ASCII chars) into a 16-byte array by truncating. Two MACs that differ only in their 17th character (i.e. the low nibble of the final byte) collide into the same `UUID`.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart:502-517` — the conversion loop `for (var i = 0; i < bytes.length && i < 16; i++)` drops the 17th ASCII character.

## Root cause

The code treats ASCII characters as raw bytes and pads/truncates to fit a 16-byte UUID. It's conflating "number of ASCII characters" with "bytes of significance" and doesn't do a MAC→hex parse.

Worth noting the historical BUGS_ANALYSIS described this as silently dropped. A prior pass may have attempted to mitigate (ordering of the `&&` check), but the collision surface remains.

## Notes

Fix sketch: treat the input semantically. If `platformId` matches the MAC regex, strip colons, parse as 12 hex digits, and zero-pad to the UUID's 128 bits (`00000000-0000-0000-0000-{MAC}`). If it's already a UUID, pass through. Otherwise, hash it (SHA-256, first 16 bytes) for a collision-resistant deterministic mapping.

Platforms also differ: Android supplies `AA:BB:CC:...`, iOS supplies a random resolvable-address-derived UUID. The MAC→UUID path only matters on Android-as-server.
