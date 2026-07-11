---
id: I350
title: Give the iOS central role the same delegate seam as the server role
category: enhancement
severity: medium
platform: ios
status: open
last_verified: 2026-07-10
related: [I345]
---

## What this is

The iOS *server* role is now testable end-to-end at the delegate level:
`PeripheralManagerImplCore` is generic over a `PeripheralManaging`
protocol (with `CentralLike` / `ATTRequestLike` stand-ins for the
CoreBluetooth types tests cannot instantiate), so synthetic delegate
sequences — subscribe/unsubscribe, request/respond, TX-gate reopen,
power-off — run under XCTest against fakes (audit R5).

The *central* role (`CentralManagerImpl`) still has no such seam: it is
welded to `CBCentralManager` and `CBPeripheral`, so its delegate wiring
— `didDisconnectPeripheral` draining in-flight operations,
`didFailToConnect`, `peripheralIsReady(toSendWriteWithoutResponse:)`
reopening the write-without-response gate, `didUpdateState(.poweredOff)`
— can only be exercised on hardware.

## Why it matters

The central-role wiring is where iOS regressions have historically
escaped to devices (the write flow-control bug was found on hardware,
not by tests). The building blocks (`OpSlot`, `PendingWriteQueue`) are
well tested in isolation; the seam would let the *wiring between them
and CoreBluetooth events* be tested the same way the server role now is.

## Rough approach

Mirror the server-role pattern: a `CentralManaging` protocol for the
manager calls, plus a `PeripheralLike` abstraction for the subset of
`CBPeripheral` the impl touches (identifier, state, service tree
navigation, read/write/notify calls, `maximumWriteValueLength`). This
is a substantially larger surface than the server role — `CBPeripheral`
appears throughout discovery, GATT ops, and the handle store — so plan
it as its own piece of work, not a quick patch.

## Related

- The shipped server-role seam: `bluey_ios/ios/Classes/PeripheralManaging.swift` and `PeripheralManagerImplCoreTests.swift` (audit R5).
- Audit: [2026-07-10 networking-scenario test audit](../reviews/2026-07-10-networking-scenario-test-audit.md) (finding NT-3 / recommendation R5).
- [I345 — move bluey-ios off the main thread](I345-decouple-bluey-ios-from-main-thread.md) (touches the same class; coordinate).
