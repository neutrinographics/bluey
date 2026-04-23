---
id: I041
title: "iOS `didUpdateCharacteristicValue` conflates read response with notification"
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-23
---

## Symptom

A notification that arrives for characteristic X while a read on characteristic X is in flight is **delivered as the read's response**, and the notification itself is lost to Flutter. The read caller gets the notification payload believing it's the read response. The actual read response arrives later and is treated as a notification (or dropped if the slot is empty).

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift:628-653` — `didUpdateCharacteristicValue`:

```swift
if let slot = readCharacteristicSlots[deviceId]?[charUuid], !slot.isEmpty {
    // treat as read response — pop slot head
}
// Otherwise treat as notification
```

## Root cause

`CBPeripheralDelegate.peripheral(_:didUpdateValueFor:error:)` fires for **both** `readValue(for:)` completions and notification deliveries. The delegate signature gives no flag to distinguish them. The standard workaround — "if I have a pending read, this is a read response" — is racy: a notification arriving during the read window is consumed as the read response.

## Notes

Fix sketch (requires careful CoreBluetooth semantics reasoning):

- One option: track notification *subscription state* separately. If the characteristic is currently subscribed (`characteristic.isNotifying`), AND we have a pending read, a callback could be either. Use the ordering assumption: CoreBluetooth delivers the read response in-order relative to its own issuance. If a notification fires *before* our `readValue` was dispatched to the peripheral, we'd see one `didUpdate` before issuing the read — that's a pure notification path.
- Another option: compare `characteristic.value` bytes against the `readCharacteristicSlots` entry's expected state. Fragile.
- Most defensive: always route to both — deliver the value to the notification stream AND pop the read slot. Duplicate delivery is safer than lost delivery. But this changes semantics visibly for callers that explicitly aren't subscribed.

Worth an empirical test before choosing: attempt to reproduce with a peripheral that notifies frequently while the app reads the same characteristic.

This is a known CoreBluetooth anti-pattern; most BLE libraries have this exact problem. Worth looking at `bluetooth_low_energy_ios` (reference) to see how it handles it.
