---
id: I057
title: MAC-to-UUID coercion duplicated in two places
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-26
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

Fixing this properly is bound up with I006's resolution (introduce a typed `DeviceIdentifier` value object that distinguishes `MacAddress`, `IosUuid`, and `BlueyServerId` variants). In the interim, extract the coercion into a single utility function in `bluey/lib/src/shared/` and have both call sites delegate.

Since I006 captures the underlying issue, this entry exists to flag the duplication to whoever fixes I006. Consider closing I057 with `status: subsumed-by` once the proper fix lands.
