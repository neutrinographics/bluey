---
id: I016
title: iOS server `characteristics` dict keyed by UUID alone (mirror of I010)
category: bug
severity: high
platform: ios
status: fixed
last_verified: 2026-04-28
fixed_in: 73656b4
related: [I010, I011, I088]
---

## Symptom

`PeripheralManagerImpl` stores hosted characteristics in a flat `[String: CBMutableCharacteristic]` map keyed by characteristic UUID. If a server hosts two services that both define a characteristic with the same UUID, the second `addService` call overwrites the first characteristic in the lookup table. Subsequent operations on that UUID (e.g., `notifyCharacteristic`) target the wrong characteristic, silently.

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:18, 53`.

## Root cause

Same dimensional error as I010/I011 on the central side, mirrored on the server side. Lookup key is a 1-tuple `(charUuid)` when it should be a 2-tuple `(serviceUuid, charUuid)`.

## Notes

The fix is bound up with I088 (Pigeon-schema rewrite for GATT identity context). Any redesign that adds `serviceUuid` to the wire schema for client-side reads/writes/notifies should also propagate service context through the server-side hosted-characteristic table.

In the interim, a defensive workaround on the iOS side: change `characteristics: [String: CBMutableCharacteristic]` to `characteristics: [String: [String: CBMutableCharacteristic]]` keyed by `(serviceUuid, charUuid)`. The Pigeon schema doesn't need to change yet — server-internal calls already know the service context at `addService` time.

External references:
- BLE Core Specification 5.4, Vol 3, Part G, §3.1 — duplicate characteristic UUIDs across services are spec-allowed.
- Apple [`CBMutableService.characteristics`](https://developer.apple.com/documentation/corebluetooth/cbmutableservice).

## Resolution

Fixed in the bundled handle-rewrite via I088 (the iOS server-side hosted-characteristic table is now keyed by handle, mirroring the central-side rewrite; duplicate characteristic UUIDs across services no longer collide). See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design and `docs/superpowers/plans/2026-04-28-pigeon-gatt-handle-rewrite.md` for the execution sequence.
