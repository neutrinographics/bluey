---
id: I040
title: "`isReadyToUpdateSubscribers` does not retry failed notifications"
category: no-op
severity: medium
platform: ios
status: open
last_verified: 2026-04-30
related: [I311]
---

## Symptom

When iOS's `CBPeripheralManager.updateValue(_:for:onSubscribedCentrals:)` returns `false` (queue full), Bluey surfaces an `unknown` error to the caller. iOS then calls `peripheralManagerIsReady(toUpdateSubscribers:)` when the queue drains, but Bluey's handler is empty. The failed notification is dropped; the caller's only option is to retry manually or miss the message.

The current code's failure mode is *worse* than just "no retry." When `peripheralManager.updateValue(...)` returns `false` (which is iOS's documented backpressure signal — queue full, retry later), the Dart-side caller receives `BlueyError.unknown.toServerPigeonError()`, which surfaces as `BlueyPlatformException(code: 'bluey-unknown')`. The caller sees a generic error, has no signal that the data was simply queued behind backpressure, and may log/retry/double-send.

The proper handling has two components:
(a) accept the value into a Swift-side retry queue and re-emit from `peripheralManagerIsReady(toUpdateSubscribers:)`;
(b) report success to Dart from the original call (the value will be sent eventually) — OR introduce a distinct `notify-backpressure` Pigeon code so callers can choose to pace themselves.

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

External references:
- Apple [`peripheralManager(_:isReadyToUpdateSubscribers:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanagerdelegate/peripheralmanagerisready(toupdatesubscribers:)).
- Apple [`peripheralManager.updateValue(_:for:onSubscribedCentrals:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/updatevalue(_:for:onsubscribedcentrals:)) — return value documentation.
- WWDC 2017 Session 712, [What's New in Core Bluetooth](https://developer.apple.com/videos/play/wwdc2017/712/) — covers `canSendWriteWithoutResponse` and the analogous flow-control story on the central side; the peripheral side mirrors it.

## Reproduction (2026-04-30)

Confirmed reproducing during the example app's notification-throughput stress
test with iOS-as-server / Android-as-client. The Android client sends a
`BurstMeCommand` to the iOS server's stress characteristic; the iOS server
loops `count` times calling `server.notify(...)`. Under load, iOS's TX queue
fills, `peripheralManager.updateValue(...)` returns `false`, and the iOS
plugin emits `BlueyError.unknown.toServerPigeonError()` from
`PeripheralManagerImpl.swift:192` (`notifyCharacteristic`) and `:225`
(`notifyCharacteristicTo`).

The example app's `StressServiceHandler.onWrite` re-raises through
`server_cubit.dart:194`, surfaced as
`Write handler error: PlatformException(bluey-unknown, ...)`.

The wrapper-type half of the symptom (raw `PlatformException` instead of a
typed `BlueyPlatformException`) is tracked separately as I311 — server-side
methods bypass the I099 typed-translation helper.
