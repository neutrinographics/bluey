---
id: I096
title: "iOS `didDisconnectPeripheral` with `error: nil` produces `bluey-unknown` instead of `gatt-disconnected`"
category: bug
severity: high
platform: ios
status: fixed
last_verified: 2026-04-25
fixed_in: c145209
related: [I087, I091, I079]
---

## Symptom

In the failure-injection stress test (post-I079), connection teardown
surfaces as `BlueyPlatformException(bluey-unknown) × 1` followed by
`GattOperationDisconnectedException × 7`. The example app's reconnect
cubit doesn't recognise the leading `bluey-unknown` as a dead-peer
signal and stops attempting to recover. Result: connection is lost
permanently after a single dropped server response.

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift` — `didDisconnectPeripheral`.
Pre-fix, the nil-error branch in:

```swift
let pigeonError: Error = (error as NSError?)?.toPigeonError()
    ?? BlueyError.unknown.toClientPigeonError()
```

falls through to `BlueyError.unknown.toClientPigeonError()` →
`PigeonError(code: "bluey-unknown", ...)`.

## Root cause

Apple's CoreBluetooth calls `peripheral(_:didDisconnectPeripheral:error:)`
with `error: nil` for *graceful* disconnects: either we ourselves called
`cancelPeripheralConnection` (e.g. `LifecycleClient` declared the peer
unreachable and tore down), or the peer initiated a clean shutdown.

`error: nil` does **not** mean "an unknown error occurred" — it means
"no metadata, link is gone." Mapping that to `BlueyError.unknown` is
semantically wrong; the link being gone is itself the meaningful signal,
and `gatt-disconnected` is the established Dart-side shape for that.

Pre-I079, this code path was rarely hit because the *server* tore down
the link in the failure-injection scenario, providing iOS with a
`CBError` (handled correctly by `nsError.toPigeonError()`). I079's
fix shifted the disconnect cause from server-initiated to
self-initiated, exposing this bug.

## Notes

Fixed in `c145209` by mapping the nil-error branch to
`PigeonError(code: "gatt-disconnected", ...)` directly:

```swift
if let nsError = error as? NSError {
    pigeonError = nsError.toPigeonError()
} else {
    pigeonError = PigeonError(code: "gatt-disconnected",
                              message: "Peripheral disconnected",
                              details: nil)
}
```

This also closes [I087](I087-failure-injection-no-auto-reconnect.md) as
a side effect — the example app's reconnect cubit now recognises the
disconnect signal.

The parallel nil-error fall-through in `didFailToConnect` is **not**
changed by this fix. No diagnostic evidence it fires in practice, and
connect-failure semantics differ from disconnect (no established
`gatt-connection-failed` code). Filed as future work if it ever
surfaces.

## Future work

Build a Swift test target for `bluey_ios` so translation logic
(`BlueyError`, `NSError+Pigeon`, `OpSlot`, `CentralManagerImpl`
delegate methods) can have unit tests. This bug would have been a
natural early test target. Not blocking; out of scope for this fix.
