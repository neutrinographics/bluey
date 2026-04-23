---
id: I083
title: "iOS `peripheralManagerDidUpdateState(.poweredOff)` doesn't clear server state"
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-23
---

## Symptom

When Bluetooth turns off while a Bluey server is running, iOS fires `peripheralManagerDidUpdateState(.poweredOff)`. Bluey emits the state change to Flutter but doesn't clear internal caches — `services`, `subscribedCentrals`, `centrals`, `pendingReadRequests`, `pendingWriteRequests` remain populated. When Bluetooth comes back on and the server restarts, it inherits stale entries that refer to `CBCentral` references that are no longer valid.

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:227-229` — the delegate handler for `peripheralManagerDidUpdateState`. Only emits `onStateChanged`, doesn't clear state.

## Root cause

No state-machine response to `.poweredOff`. The assumption is that re-enabling Bluetooth and calling `startAdvertising` again will overwrite whatever's stale. In practice, subscriptions and pending requests don't get overwritten by normal flow and can survive.

## Notes

Fix: in the `.poweredOff` branch (and `.unauthorized` / `.unsupported`), clear all cached state and drain any pending read/write requests with a "bluetooth-off" error. On `.poweredOn` after a power cycle, the user is expected to call `startAdvertising` again.

Equivalent concern on the Android side: `BluetoothAdapter.STATE_OFF` broadcast — currently no Bluey-side listener for this on the server side; the GATT server just stops working silently. Worth a parallel entry if confirmed.
