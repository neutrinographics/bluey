---
id: I204
title: "iOS advertising: no manufacturer data, background limits, GAP name"
category: limitation
severity: low
platform: ios
status: wontfix
last_verified: 2026-04-23
---

## Rationale

iOS's advertising surface is deliberately narrow:

- **No manufacturer data**: `CBPeripheralManager.startAdvertising(_:)` supports only `CBAdvertisementDataLocalNameKey` and `CBAdvertisementDataServiceUUIDsKey`. The `manufacturerData` key is ignored.
- **Background advertising strips the name**: when the app is backgrounded, iOS drops `CBAdvertisementDataLocalNameKey` and moves service UUIDs to a special "overflow area" only visible to iOS devices scanning for those specific UUIDs. Android scanners may not discover a backgrounded iOS peripheral.
- **28-byte limit on foreground name+UUIDs combined**: iOS silently truncates to a "Shortened Local Name" if the advertisement is too large.
- **GAP device name not controllable**: after connection, the GAP Device Name characteristic (`0x2A00`) is managed by iOS from the system device name (Settings → General → About → Name), independent of what was advertised.
- **TX power, connectable/non-connectable, advertising mode**: none exposed. Always connectable, always the default mode.

## Current behavior

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:97-98` — manufacturer data explicitly dropped with a source comment.

## Decision

Wontfix for iOS. The Dart domain API can still accept these fields for platform parity; on iOS they're silently ignored (see I051 for the discussion of whether "silent ignore" or "throw UnsupportedOperationException" is better — I053 is where that decision is tracked).

## Notes

Apps that advertise on both platforms should put anything critical in the service UUIDs (universally honored), not the manufacturer data. For beacon-style apps, iOS is not a great peripheral-role choice.
