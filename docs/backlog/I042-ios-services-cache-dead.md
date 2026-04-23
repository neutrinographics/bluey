---
id: I042
title: "iOS `services` dict is dead storage"
category: bug
severity: low
platform: ios
status: open
last_verified: 2026-04-23
---

## Symptom

Cosmetic — no functional bug. `CentralManagerImpl.services: [String: [String: CBService]]` is written in two places and read in zero places. The code uses `peripheral.services` (CoreBluetooth's own cache) everywhere it needs service lookups.

## Location

Writes: `bluey_ios/ios/Classes/CentralManagerImpl.swift:530` (in `didDiscoverServices`) and `:546` (in `didDiscoverIncludedServices`).

Clears: `:471` (disconnect), `:731` (services changed).

Reads: grep confirms none.

## Root cause

Leftover from an earlier design that probably used the Bluey-side cache, before the switch to `peripheral.services`. Never removed.

## Notes

Trivial cleanup: delete the `services` dict, the writes, and the clear calls. Zero behavior change. Can roll into any other CentralManagerImpl change.

No parallel `characteristics` / `descriptors` problem — those dicts *are* read in `findCharacteristic` / `findDescriptor`.
