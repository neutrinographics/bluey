---
id: I025
title: Server-side PHY update/read events are logging-only
category: no-op
severity: low
platform: android
status: open
last_verified: 2026-04-23
related: [I031]
---

## Symptom

`BluetoothGattServerCallback.onPhyUpdate` and `onPhyRead` fire when PHYs are renegotiated on a connection inbound to the server. Bluey only logs them. There's no domain-level `Central.phy` or `Central.phyChanges`.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:555-561`.

## Root cause

Server-side PHY was never modeled in the Pigeon schema or the `Server` / `Central` domain API. Parallels I031 on the client side, but here it's specific to inbound connections.

## Notes

Low priority because very few applications need to observe or request PHY changes. Typical consumer apps don't distinguish between 1M/2M/Coded PHYs. Implement alongside I031 if/when requesting PHY becomes a feature; the server-side observation falls out cheaply.

iOS does not expose PHY at all — see I200.
