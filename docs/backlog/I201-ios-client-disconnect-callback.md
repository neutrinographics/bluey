---
id: I201
title: iOS has no client disconnect callback (mitigated)
category: limitation
severity: low
platform: ios
status: wontfix
last_verified: 2026-04-23
---

## Rationale

`CBPeripheralManagerDelegate` does not fire a callback when a connected central disconnects. This is a known CoreBluetooth gap, unchanged since iOS 6. Every major Flutter/Swift BLE peripheral library has this problem.

## Current mitigation

Bluey ships a built-in "lifecycle control service" — a hidden GATT service with a heartbeat characteristic. Bluey clients write heartbeats periodically; the server uses timeouts to infer disconnect. Implemented and documented in `bluey_ios/IOS_BLE_NOTES.md`.

Limits: non-Bluey clients connecting to a Bluey server can't send heartbeats and will time out after `lifecycleInterval` (default 10s). Users who want to support third-party clients must pass `lifecycleInterval: null` and accept that disconnects are inferred only from subscription cleanup (see I040's cousin — `didUnsubscribeFrom`).

## Decision

Wontfix at the platform level. The workaround is the best available in the ecosystem.

## Notes

Alternative approaches considered (from IOS_BLE_NOTES.md):

- L2CAP channels (iOS 11+) — definitive disconnect via `NSStream endEncountered`. Requires client cooperation and adds protocol-level complexity. Rejected for the general case.
- Polling `subscribedCentrals` — not event-driven, unreliable.
- Application-level heartbeat — what Bluey does.
