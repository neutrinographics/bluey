---
id: I033
title: Connection priority request not exposed
category: unimplemented
severity: medium
platform: android
status: open
last_verified: 2026-04-23
related: [I032]
---

## Symptom

Android's `BluetoothGatt.requestConnectionPriority(HIGH|BALANCED|LOW_POWER|DCK)` is the standard knob for trading battery vs latency vs throughput. Bluey has no API to call it. Apps can't tune power on long-lived connections.

## Location

No implementation exists. Domain API gap.

## Root cause

Feature was not in the initial cut. Reference `bluetooth_low_energy_android` exposes it via `requestConnectionPriority(address, priority)`.

## Notes

Tightly coupled to I032 — the "connection parameters" API on Android *is* the priority request, since raw parameters aren't exposed. A combined fix would expose:

- `Connection.requestConnectionPriority(ConnectionPriority)` returning `Future<void>`.
- `ConnectionPriority` enum: `high`, `balanced`, `lowPower`, `dck` (digital car key, API 34+).

Not symmetric with iOS, and that's fine — domain API can check `platform.capabilities.canRequestConnectionPriority` and throw `UnsupportedOperationException` on iOS (see I053).
