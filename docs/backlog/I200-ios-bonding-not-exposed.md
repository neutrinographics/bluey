---
id: I200
title: iOS does not expose bonding / PHY / connection parameters
category: limitation
severity: low
platform: ios
status: wontfix
last_verified: 2026-04-23
---

## Rationale

CoreBluetooth intentionally does not expose:

- **Bonding / pairing state**: iOS auto-pairs when a characteristic read/write requires encryption. The process is transparent. There is no `getBondState`, no `createBond`, no `bondStateChanges`. The user sees a system-level pairing prompt.
- **PHY negotiation**: CoreBluetooth handles PHY selection transparently. No API to request 2M / coded PHY or observe PHY changes.
- **Connection parameters**: no way to read or request interval / latency / timeout from the central role. `CBPeripheralManager` can suggest a range, but `CBCentralManager` cannot. On iOS the radio stack picks values based on its own power-model heuristics.
- **Bonded device list**: iOS does not expose a list of "paired" devices to apps. The "Bluetooth" Settings list is not app-accessible.

## Current behavior

`bluey_ios/lib/src/ios_connection_manager.dart`:

- `getBondState` returns a stable default; `bondStateStream` returns `Stream.empty()` (line 248-250).
- `getPhy` returns `(tx: le1m, rx: le1m)`; `phyStream` returns `Stream.empty()` (line 278-281).
- `getConnectionParameters` returns a fabricated default; `requestConnectionParameters` is a no-op.
- `getBondedDevices` returns `[]` (line 267-269).

## Decision

Wontfix for iOS-native-API reasons. The domain API stays the same for platform parity; iOS silently reports defaults. To make failures loud rather than silent, see I053 — if the platform capability matrix grows a flag for each of these, the domain layer can throw `UnsupportedOperationException('bond', 'ios')` instead of returning a lie.

## Notes

Do not combine this entry with I030–I032 (Android versions), which are genuine fixable gaps, not platform limitations.

If and when CoreBluetooth exposes any of these (no sign as of iOS 18), revisit.
