---
id: I040
title: "`isReadyToUpdateSubscribers` does not retry failed notifications"
category: no-op
severity: medium
platform: ios
status: open
last_verified: 2026-04-23
---

## Symptom

When iOS's `CBPeripheralManager.updateValue(_:for:onSubscribedCentrals:)` returns `false` (queue full), Bluey surfaces an `unknown` error to the caller. iOS then calls `peripheralManagerIsReady(toUpdateSubscribers:)` when the queue drains, but Bluey's handler is empty. The failed notification is dropped; the caller's only option is to retry manually or miss the message.

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:349-352` —

```swift
func isReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
    // The queue has space again for notifications
    // We could retry any failed notifications here
}
```

And the drop site: around line 140-145, where `updateValue` is called and `false` is returned as `BlueyError.unknown`.

## Root cause

No retry queue. The failed notification is surfaced as a synchronous error; the "try again when ready" callback has no state to work with.

## Notes

Fix sketch: a `pendingNotifications: [(characteristic: CBMutableCharacteristic, data: Data, centrals: [CBCentral]?)]` FIFO per server. When `updateValue` returns false, enqueue; when `isReadyToUpdateSubscribers` fires, drain the FIFO calling `updateValue` until another `false` — then wait again.

Per-caller result reporting complicates it: either (a) succeed as soon as enqueued (accept that errors may be silent), (b) keep a per-entry completion and resolve it when the packet gets out. (b) is correct but adds bookkeeping.

This matters for stress-test notification-throughput workloads; currently the cap on Bluey iOS's notification rate is roughly "whatever fits in one drain of the OS queue before we start dropping."
