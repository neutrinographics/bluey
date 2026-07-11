---
id: I354
title: Key iOS client discovery tracking and op routing by handle, not UUID
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-07-10
related: [I088, I350, I041]
---

## Symptom

Duplicate-UUID attributes on iOS can produce a non-deterministically
incomplete service tree, and overlapping operations on two same-UUID
characteristics can complete each other's futures with the wrong data.

## Location

`CentralManagerImpl.swift` — `pendingCharacteristicDiscovery` keyed by
UUID string (audit DA-03) and read/write/notify/descriptor OpSlot
caches + delegate-callback routing keyed by `characteristic.uuid`
(audit DA-04). Both latent: bite only on duplicate-UUID peripherals.

## Root cause

The I088 handle-identity design stops at the wire format on these
paths; internal iOS bookkeeping still uses UUID strings while handle
minting is by object identity.

## Notes

Key the pending-discovery sets and op-slot/routing maps by minted
handle or `ObjectIdentifier`. Testability depends on the central-role
delegate seam ([I350](I350-ios-central-manager-delegate-seam.md)) —
sequence after it so the fix lands test-first.
