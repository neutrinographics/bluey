---
id: I034
title: Maximum write length query not exposed
category: unimplemented
severity: medium
platform: android
status: fixed
fixed_in: 47c3e5b
last_verified: 2026-06-02
related: [I004]
---

## Symptom

To chunk large writes without triggering prepared-writes (see I050), an app needs to know the maximum ATT attribute value length, which is `mtu - 3` for writes-with-response and `mtu - 3` for writes-without-response on most stacks. Bluey doesn't expose this; apps have to track MTU themselves and compute the chunk size.

## Location

No API. Domain-level `Connection` has no `maxWriteLength` getter.

## Root cause

Feature was not in the initial cut. iOS exposes it directly via `CBPeripheral.maximumWriteValueLength(for: .withResponse | .withoutResponse)`. Android has no direct API; apps compute `mtu - 3`.

## Notes

Fix direction:

- Domain: `Connection.maxWriteLength({required bool withResponse})` returning an `int`.
- iOS: straight delegation to `maximumWriteValueLength(for:)`.
- Android: computed as `mtu - 3` (with the caveat that write-without-response can actually be larger on some stacks — Android's convention is that it also caps at `mtu - 3`, matching iOS).

Depends on I004 (MTU actually tracked correctly). Without I004, this getter would be wrong on both platforms when the peer initiates an MTU change.

## Resolution (verified 2026-06-02)

I325 wired `getMaximumWriteLength` through `android_connection_manager.dart` to the native `mtu - 3` query and surfaced it via `maxWritePayload`. Verified in HEAD.
