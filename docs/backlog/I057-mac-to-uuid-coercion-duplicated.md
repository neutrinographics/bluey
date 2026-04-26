---
id: I057
title: MAC-to-UUID coercion duplicated in two places
category: bug
severity: low
platform: domain
status: fixed
last_verified: 2026-04-26
fixed_in: 510278e
related: [I006]
---

## Symptom

Same code (truncate-and-pad MAC to UUID format) exists in two places, and both are broken in the same way (I006 documents the brokenness). Fixing one without the other leaves the bug in place.

## Location

- `bluey/lib/src/bluey.dart:587-598` — `_deviceIdToUuid`.
- `bluey/lib/src/peer/peer_discovery.dart:130-137` — `_addressToUuid`.

The two functions are byte-identical except for variable names.

## Root cause

Copy-paste during the peer module addition. The underlying issue is that `Device.id` (a `UUID`) and `device.address` (the platform's native identifier) are conflated — synthesizing a fake UUID from a MAC is a workaround, not a model.

## Notes

Fixed in `510278e` by extracting the coercion to a top-level `deviceIdToUuid(String)` in a new `bluey/lib/src/shared/device_id_coercion.dart`. Both call sites now delegate; both private definitions deleted. The `peer_discovery.dart` `uuid.dart` import was no longer needed and was dropped.

Behaviour is byte-identical to the previous duplicated implementation. The synthesis itself remains a workaround flagged by [I006](I006-mac-to-uuid-truncation.md) (typed `DeviceIdentifier` value object). I057's contribution is that the eventual I006 fix now has a single site to rewrite rather than two.

A new `bluey/test/device_id_coercion_test.dart` covers the helper directly (iOS pass-through, MAC strip-and-pad, case normalization, colonless MAC, length+hyphen detection).
