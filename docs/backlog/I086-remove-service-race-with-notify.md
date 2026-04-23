---
id: I086
title: "`removeService` races with in-flight notify fanout"
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-04-23
---

## Symptom

On both platforms, `removeService(uuid)` mutates subscription / centrals bookkeeping and pulls the `BluetoothGattService` / `CBMutableService` out of the server. If a `notifyCharacteristic` fanout is executing concurrently (iterating the subscription set and dispatching per-central notifies), the characteristic's service becomes invalid mid-fanout. Behavior depends on the stack: some deliveries fail, some reach centrals that have just been untracked.

## Location

iOS: `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:63-81` — `removeService` clears `subscribedCentrals` without coordination with notify fanout.

Android: analogous pattern in `GattServer.kt` (`removeService` + notify paths).

## Root cause

No coordination. Removal and notify fanout operate on overlapping state without a coordination primitive.

## Notes

Fix: make removeService block on any in-flight notify fanout completing, or defensively copy the subscription set at fanout entry (the I082 fix) — the copy covers this case incidentally, since a removed service's subscribers aren't in the snapshot if removal completed before fanout started.

Practical risk is lower than I082 because `removeService` is typically called at app teardown or reconfiguration — not during steady-state operation. But worth noting as a companion to I082.
