---
id: I345
title: bluey-ios runs its CoreBluetooth delegates, Pigeon handlers, and lifecycle timers on iOS main thread — UIKit hangs back up BLE I/O and produce burst-flushes
category: tech-debt
severity: medium
platform: ios
status: open
last_verified: 2026-06-03
related: [I339, I343, I344]
---

## Symptom

Whenever iOS main thread is wedged (UIKit doing IPC, autolayout under
load, modal presentation, keyboard XPC cold-start, 1Password autofill,
network reachability transitions, foreground/background switches, etc.),
bluey-ios's entire I/O pipeline stalls in lockstep:

- No `CBCentralManagerDelegate` or `CBPeripheralManagerDelegate` callbacks
  are delivered (they're queued on main).
- No Pigeon handlers are invoked (Flutter's binary messenger dispatches
  on main by default).
- The `OpSlot` timeout timers don't fire (they use
  `DispatchQueue.main.asyncAfter`).
- The consumer's Dart `Future`s for in-flight writes / reads / RSSI /
  service discovery don't resolve.

When the main thread unblocks, everything flushes at once: every queued
Pigeon hop fires, every queued delegate callback fires, every queued
`writeValue` hits CoreBluetooth in rapid succession. This burst-flush
is the trigger for I343 (and the proximate cause of the dogfood-visible
"iOS Dart hang → unidirectional silence on the Android side" that I343,
I339, and I338 jointly chase).

Reproduced 2026-06-02 / 2026-06-03 in the `gossip_chat` dogfood app
between a Pixel 6a (Android peripheral) and an iPhone (iOS central).
The trigger was an ordinary iOS keyboard XPC cold-start (the first
`UITextField` focus in the app lifetime, ~10–16 s wall-clock under a
debugger). What's pathological is not the keyboard hang itself
(unavoidable iOS lazy-load behavior on first focus, and ~10× shorter
in release builds) — it's that **a UIKit hang has any effect on BLE at
all**. CoreBluetooth's `peripheral.writeValue(...)` would happily ship
bytes on its own dispatch queue if bluey gave it one. It doesn't.

## Where bluey is bound to main thread today

- `bluey_ios/ios/Classes/CentralManagerImpl.swift:60`
  ```swift
  centralManager = CBCentralManager(delegate: nil, queue: nil)
  ```
  Apple's documented behavior when `queue: nil`: "If nil, the central
  manager dispatches events on the main queue." Every
  `centralManager(_:didDiscover:advertisementData:rssi:)`,
  `peripheral(_:didUpdateValueFor:error:)`,
  `peripheralIsReady(toSendWriteWithoutResponse:)`, etc. lands on
  main and waits behind any UIKit work in front of it.
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:63` — same shape:
  ```swift
  peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)
  ```
  Every `peripheralManager(_:didReceiveWrite:)`,
  `peripheralManagerIsReadyToUpdateSubscribers(_:)`,
  `peripheralManager(_:central:didSubscribeTo:)`, etc. queues on main.
- `bluey_ios/ios/Classes/OpSlot.swift:21`
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
  ```
  Every op-timeout (write, read, descriptor read, descriptor write,
  read-RSSI, etc.) is gated by a main-queue timer. A main-thread hang
  silently extends the effective timeout by the hang duration —
  meaning timeouts that should have failed during the hang instead
  fire much later (or not at all if the connection drops in the
  interim).
- `bluey_ios/ios/Classes/BlueyLog.swift:82` —
  `DispatchQueue.main.async` is used for forwarding logs to the
  FlutterApi. This one is fine to leave on main (logs are diagnostic
  and don't need throughput guarantees) but worth a comment after the
  refactor lands so future readers know it's intentional rather than
  overlooked.
- **Pigeon-generated handlers** for the host APIs (the
  `CentralManagerHostApi` / `PeripheralManagerHostApi` setUp methods)
  dispatch incoming method calls on the Flutter platform thread, which
  on iOS is main. Bluey accepts the dispatch as-is and does all the
  body work synchronously on main.

The net effect is that bluey's *entire* iOS surface — discovery,
connection, GATT operations, lifecycle timers, log emission — is
serialized through iOS main thread.

## What this costs in practice

- **I343 trigger.** Any main-thread stall ≥ a few seconds produces a
  post-resume burst of `peripheral.writeValue(...type: .withoutResponse)`
  calls. I343's chunk-boundary 2-byte-loss bug needs that burst as its
  trigger; without it, the bug has nothing to fire on.
- **Lifecycle-heartbeat starvation.** During a long main-thread stall
  the heartbeat-write timer doesn't run, so the peer's silence-timeout
  fires (I338 Pattern B now correctly suppresses the disconnect signal
  but still emits the advisory event, and SWIM probes start failing
  4–5 seconds in). This is misleading: the BLE link is healthy, the
  remote peer is reachable — but bluey can't say anything because its
  own dispatch is stuck.
- **Timeouts don't.** A 30 s op-timeout becomes a 30+N second
  op-timeout where N is the hang duration. For consumer error
  handling that bounds latency, this is a silent contract violation.
- **Bad reproducer behavior.** Half the diagnostic capture work in
  the I338/I339/I343 saga has been disambiguating "did bluey see this
  event at time T?" from "did the main thread receive it at time T?".
  Decoupling makes the log timestamps mean what consumers think they
  mean.

## Proposed fix

### A. Dedicated serial dispatch queue for CoreBluetooth managers

Construct both managers with an explicit serial queue, used for all
CoreBluetooth delegate callbacks and for outgoing CoreBluetooth calls:

```swift
private let bleQueue = DispatchQueue(label: "com.neutrinographics.bluey.ble",
                                     qos: .userInitiated)

// CentralManagerImpl.init
centralManager = CBCentralManager(delegate: nil, queue: bleQueue)

// PeripheralManagerImpl.init
peripheralManager = CBPeripheralManager(delegate: nil, queue: bleQueue)
```

One queue, shared between both managers, so the existing
"one-state-mutation-at-a-time" implicit contract that holds today
(both managers' delegates run on main, which is itself a serial queue)
is preserved by construction. No new `DispatchQueue.sync` / barriers
needed for any shared dictionary (`peripherals`, `pendingServiceDiscovery`,
`pendingCharacteristicDiscovery`, `writeCharacteristicSlots`,
`pendingWriteQueues`, etc.).

### B. Move Pigeon-handler bodies onto the BLE queue

Pigeon's setUp dispatches into the host API method, but the body is
plain Swift — it can hop to the BLE queue first thing:

```swift
func writeCharacteristic(
    deviceId: String,
    characteristic: CBCharacteristic,
    value: FlutterStandardTypedData,
    withResponse: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    bleQueue.async {
        self.writeCharacteristicOnQueue(
            deviceId: deviceId,
            characteristic: characteristic,
            value: value,
            withResponse: withResponse,
            completion: completion
        )
    }
}
```

Slightly more boilerplate per method but mechanical. The hop is
sub-microsecond. The completion still gets called by the queued
delegate path (now also on `bleQueue`), so the result still reaches
Pigeon, which serializes back to Flutter's binary messenger on its
own thread.

### C. Move `OpSlot` timers off main

```swift
// OpSlot.swift — production factory
private let timerQueue: DispatchQueue
init(timerQueue: DispatchQueue = ...) { self.timerQueue = timerQueue }
internal func schedule(...) -> ... {
    timerQueue.asyncAfter(deadline: .now() + seconds, execute: item)
}
```

Use the same `bleQueue` so the timer's `execute:` block sees the
same state-mutation context the rest of bluey-ios runs in.

### D. Leave `BlueyLog` on main (intentional)

Comment the `DispatchQueue.main.async` at `BlueyLog.swift:82` to record
that log forwarding *deliberately* uses main, since Flutter's
`flutterApi.onLog(...)` is itself a method-channel call that
ultimately runs on Flutter's platform thread anyway, and there's no
throughput requirement for diagnostic emission.

## Risks / what to watch for

- **Hidden assumptions about main-thread state mutation.** Any code
  in `CentralManagerImpl` or `PeripheralManagerImpl` that reads/writes
  shared state from a *non-delegate, non-Pigeon-handler* path (e.g.,
  KVO observers, NotificationCenter handlers, Combine subscriptions)
  needs auditing — those run on whatever thread posts the event, not
  on `bleQueue`. A quick `grep` for `addObserver`, `sink(`,
  `assign(to:)`, `NSNotificationCenter`, `KVO` should flush the list.
- **CoreBluetooth API calls from other threads.** Apple documents
  `CBPeripheral`/`CBCentralManager` methods as thread-safe; they
  internally serialize. But the *result observation* (delegate
  callbacks) is queue-specific. The fix means every consumer must be
  prepared for its completion to land on `bleQueue` rather than main
  — this is internal to bluey, but worth verifying every
  `completion(.success(()))` site is queue-agnostic (most should be:
  Pigeon's `FlutterResult` itself is thread-safe).
- **Logging during init.** `BlueyLog` may be invoked from
  `init(messenger:)` before any queue context exists. Confirm the log
  path is still safe to call from any caller thread.
- **Tests.** `PendingWriteQueue` and `PendingNotificationQueue` tests
  are queue-agnostic today; should stay so. Any new tests that exercise
  the delegate path should explicitly schedule on a test-controlled
  queue rather than blocking on `RunLoop.main.run(...)`. The existing
  `OpSlot.Production` timer factory was already abstracted for
  testability; the new constructor parameter just needs to thread
  through.

## Why severity is medium, not high

- The user-visible effect is degraded BLE throughput during UIKit
  hangs, not silent corruption. I343 is the silent corruption — once
  that's fixed, this issue downgrades to "BLE pauses during hangs but
  recovers cleanly," which is a reasonable thing to wait for a
  scheduled refactor on rather than urgent fire.
- That said, this issue is the *upstream cause* of I343's trigger and
  of multiple "this looks like a hang but is actually two unrelated
  things stacked" debugging sessions in the gossip dogfood. If I343's
  fix turns out to need this decoupling anyway, severity bumps to high.
- Mitigation cost is real: this is a multi-day refactor that touches
  every Pigeon handler, every delegate method, every shared
  dictionary's access pattern, and the timer-factory injection
  signature. Not a one-PR fix.

## Notes

- Android's bluey doesn't have an exact analogue of this issue because
  the GATT callbacks dispatch onto the Bluetooth stack's binder
  threads — not on the Android UI thread — so a UI-thread hang on
  Android doesn't directly stall BLE. The analogous risk on Android is
  the Pigeon `flutterApi.on*` hops back to Dart, which *are* on the
  platform thread; but bluey-android already `handler.post {}` for
  most of these (see `GattServer.kt:960` and friends), which posts
  back via the main looper. A main-looper hang on Android would back
  up Pigeon delivery the same way iOS does — call out as a parallel
  audit ("are there places we forward back to Dart synchronously vs.
  via Looper?") but not part of this issue's scope.
- The pattern proposed here (one serial queue shared between both CB
  managers + Pigeon handler bodies + lifecycle timers) is the
  approach the major BLE wrappers on iOS (e.g. RxBluetoothKit,
  AsyncBluetooth) take, with the same rationale.
- Read alongside I343 (chunk-boundary 2-byte loss) and I339
  (TX-gate flow control). All three are part of the same surface —
  "make iOS `WriteNoResponse` reliable under arbitrary main-thread
  load" — but each is a separate fix with independent value.

## Acceptance

- Both `CBCentralManager` and `CBPeripheralManager` constructed with
  the same dedicated serial queue.
- All Pigeon handler bodies (every `func` on `CentralManagerHostApi`
  and `PeripheralManagerHostApi`) hop to the BLE queue before
  touching state.
- `OpSlot.Production` (or whatever the production timer factory ends
  up being named) uses the BLE queue for `asyncAfter`.
- Manual dogfood reproduction: trigger a 10+ second iOS main-thread
  hang (debug build with keyboard cold-start), then confirm in logs
  that
  - heartbeat-write logs continue at the configured cadence through
    the hang (because the timer fires on `bleQueue`, not on main),
  - SWIM probes / gossip rounds continue completing through the hang
    on the iOS side (Dart-isolate work is already off main; what was
    missing was the Pigeon round-trip resolving),
  - on resume, there is no burst of queued writes — they were
    flowing throughout the hang.
- A regression note in `bluey_ios/IOS_BLE_NOTES.md` documenting the
  threading model so future contributors don't accidentally
  `DispatchQueue.main.async` something back onto main.
