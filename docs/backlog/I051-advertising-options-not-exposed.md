---
id: I051
title: Advertising options not exposed (TX power, mode, connectable)
category: unimplemented
severity: medium
platform: both
status: open
last_verified: 2026-04-23
---

## Symptom

`Server.startAdvertising()` (or its equivalent) exposes a small set of fields: name, service UUIDs, (on Android) manufacturer data. It doesn't expose:

- **Advertising mode** (Android): `ADVERTISE_MODE_LOW_POWER` (1000ms), `BALANCED` (250ms), `LOW_LATENCY` (100ms). Apps can't trade battery for discovery speed.
- **TX power** (Android): `ADVERTISE_TX_POWER_ULTRA_LOW` / `LOW` / `MEDIUM` / `HIGH`. Affects range and battery.
- **Connectable / non-connectable** (Android): connectable is hardcoded. Beacons need non-connectable; service-based advertisers need connectable. Currently always connectable.
- **Include device name / include TX power in advertisement** (Android flags).
- **Extended advertising / coded PHY advertising** (Android, API 26+).
- **Advertise timeout** (Android): auto-stop after N ms.
- **iOS-specific**: advertising options are essentially fixed by the platform (name + UUIDs only) — see I204.

## Location

`bluey_android/.../Advertiser.kt` — hardcoded `AdvertiseSettings.Builder().setAdvertiseMode(...).setTxPowerLevel(...).setConnectable(true).build()`.

Domain API: `Server.startAdvertising(AdvertiseConfig)` on the domain side — the `AdvertiseConfig` shape doesn't carry these fields.

## Root cause

Initial cut picked a sensible default for each knob. The DTO and the Kotlin settings builder weren't parameterized.

## Notes

Fix sketch:

- Extend `AdvertiseConfig` (domain) with `mode`, `txPower`, `connectable`, `includeDeviceName`, `includeTxPower`, `timeout`. Most are `enum?` — null means "platform default."
- Android: thread through to `AdvertiseSettings.Builder`.
- iOS: silently ignore unsupported fields (already the pattern — see I204). Capability flags (I053) advertise which are supported.

Extended advertising / coded PHY is a larger feature that deserves its own entry if it becomes a real requirement.
