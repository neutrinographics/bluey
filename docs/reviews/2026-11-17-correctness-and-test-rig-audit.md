# Bluey audit: correctness and hardware-free testing

- **Date:** 2026-11-17
- **Document:** https://claude.ai/artifact/R6G8npke9CKEDaAakFyR7a

The codebase is in good shape structurally, but this audit found 3 High and 8 Medium defects that the backlog does not track, and 8 of those 11 are reproduced by failing tests. Android can get true hardware-free instrumentation tests; iOS can get close with a simulated radio behind a native port, because the iOS Simulator has no Bluetooth.

## Overall condition

The architecture holds up: the domain layer is free of framework code apart from two tracked leaks (I308, I309), the port is narrow, and the ubiquitous language is applied consistently. The backlog is honest and detailed, so this audit only lists what it does not already track. Audited at commit `a41a2de`.

| Check | Result |
| --- | --- |
| `flutter analyze` (Flutter 3.47.2) | No issues |
| `bluey` tests | 1120 pass, 90.5% line coverage |
| `bluey_platform_interface` tests | 78 pass |
| `bluey_android` Dart tests | 83 pass |
| `bluey_ios` Dart tests | 98 pass |
| Kotlin JVM tests (Gradle) | Not run: the cloud container cannot reach `dl.google.com` |
| Swift XCTest | Not run: needs macOS and Xcode |
| Fresh checkout on Flutter 3.50.0 (current stable) | `pub get` fails: `bloc_test ^9.1.0` needs `analyzer >=13`, `pigeon ^26` needs `analyzer <13` |

Three structural weaknesses explain most of the findings below.

- **State is kept in three places that can disagree.** The domain object, the Dart adapter and the native class each hold their own idea of "scanning", "advertising" and "connected". Nothing reconciles them, so a failure or a race on one level leaves the others stale.
- **Completion is matched by position, not identity.** Android completes "whatever op is current" and iOS completes "the head of the slot for this UUID". Any stray, late or unsolicited callback is credited to the wrong caller.
- **Teardown is only reliable on the path the app initiates.** A disconnect the app asks for cleans up; a disconnect the peer causes does not.

Native findings marked "by reading" were traced through the code but not executed, because neither native test gate runs in the cloud container. They can be run on your Mac if you want them confirmed.

## New findings: High

### H1. Android: an unsolicited callback completes whatever GATT operation is in flight

*By reading. Related to I063, which records only the late-callback-after-timeout case and calls it uncertain.*

`GattOpQueue.onComplete` (`GattOpQueue.kt:53-66`) completes the current op with no check that the callback belongs to it. Every `onMtuChanged` is routed there (`ConnectionManager.kt:912-925`), including the peer-initiated ones that `ANDROID_BLE_NOTES.md:173` says are "not responses to our ops".

- A service discovery in flight completes early as a success and maps whatever `gatt.services` holds at that moment (`ConnectionManager.kt:316-323`). The caller sees an empty or partial tree, and `connectAsPeer` reports a real peer as "not a Bluey peer".
- A write or CCCD write in flight completes as a false success. Its real callback then completes the next op, so results stay shifted by one until the link drops.
- A read or RSSI read in flight hits `it as ByteArray` inside `Result.map` (`GattOp.kt:71`, `:196`). The cast throws, the queue swallows it (`GattOpQueue.kt:58-62`), and the timeout was already cancelled, so the Dart future never completes.

Trigger: any MTU change the app did not request while an op is in flight. iOS peers start an MTU exchange right after connecting, which is when Bluey runs service discovery. How often Android delivers that event to the client callback varies by OS version and needs a device or emulator check. Fix: tag each callback with its op kind and complete only a matching op; use `mapCatching` so a bad cast fails the future.

### H2. Peer discovery disconnects links the app is already using

*Reproduced. Related to I374, which covers only the iOS shared-link case.*

`PeerDiscovery` probes every advertising candidate with a raw `_platform.connect` and then always calls `_platform.disconnect(address)` (`peer_discovery.dart:183`, `:187`, `:238`, `:252`). Bluey servers keep advertising while connected, so `discoverPeers()` or a second `BlueyPeer.connect()` probes a device the app already holds a `Connection` to. The probe's disconnect drops that link. On the real adapters the probe's connect has also replaced the per-device stream controllers (M3), so the original `Connection` is never told and stays `ready` on a dead link.

Fix: give `Bluey` a registry of live connections by address, and have discovery read the server id over the existing link, or skip the address.

### H3. A disconnect the peer causes never finalises the Connection

*Reproduced. I369 tracks the adapter-level half.*

On a platform `disconnected` event `BlueyConnection` only calls `_setState` (`bluey_connection.dart:965`). `_cleanup()` runs only from an explicit `disconnect()` (`:815`), and `disconnect()` returns early once the state is already `disconnected` (`:787`). After a remote drop or link loss, which is the most common way a BLE link ends:

- `stateChanges` and every notification stream stay open, so `await for` consumers hang.
- The platform subscriptions and per-characteristic controllers are never released, and no later call can release them.
- A later adapter-off event moves the dead connection from `disconnected` to `invalidated`.

Fix: run the same teardown on the platform `disconnected` event as on `disconnect()`, and make `disconnect()` on a dead connection finish the cleanup.

## New findings: Medium

| ID | Where | What happens | Evidence | Related |
| --- | --- | --- | --- | --- |
| M1 | iOS native. `CentralManagerImpl.swift:803`, `:608`; `OpSlot.swift` `completeHead` | One read timeout breaks every later read of that characteristic until disconnect. The late response fails the `!slot.isEmpty` guard, is forwarded as a notification, and never consumes `pendingDrops`. The next read's real response is then dropped as "late", it times out, and the cycle repeats. Service discovery has the same guard. | By reading | I359 calls this latent; it fires whenever a server answers after the 10 s client timeout |
| M2 | Dart adapters. `android_scanner.dart:27`, `ios_scanner.dart:26` | `startScan` is not awaited. If the native side rejects it (no scan permission, adapter not ready) the error becomes an unhandled async error and the scan stream stays silent. Android's state check looks only at `BLUETOOTH_CONNECT` (`BlueyPlugin.kt:692`), so a first run without scan or location permission lands here. | Reproduced | I013, I092 |
| M3 | Dart adapters. `android_connection_manager.dart` and `ios_connection_manager.dart`, `connect` | A second `connect()` to a connected device replaces the per-device stream controllers. The first `Connection` stops receiving state changes and notifications and never learns the link dropped. | Reproduced | I369, I363 |
| M4 | Domain. `bluey_scanner.dart:332-345` | Restarting a scan without awaiting the cancel (`sub.cancel(); scanner.scan()`), or as the timeout fires, kills the new scan. The suspended `stop()` resumes, cancels the new subscription and sets `stopped`. The radio keeps scanning, the stream is silent, and `stop()` is now a no-op. | Reproduced | I336 covers concurrent scans only |
| M5 | Domain. `bluey_scanner.dart:349` | `Scanner.dispose()` while scanning never calls `stopScan`. The native scan runs until the next scan or stop. | Reproduced | I094 |
| M6 | Domain. `bluey_server.dart:151-152` | If the eager control-service registration fails, the error is unhandled at `server()`, and every later `addService` and `startAdvertising` rethrows the same cached raw platform exception. The server cannot recover. On iOS the peripheral manager can still be starting when the central manager already reports `on`. | Reproduced | I005 |
| M7 | Domain. `bluey_server.dart:244`, `:274` | A read or write that arrives while nothing listens to `readRequests` or `writeRequests` is added to a broadcast controller and lost. The remote central waits out the 30 s ATT timeout, and that client's lifecycle timer stays paused. | Reproduced | I357 |
| M8 | Native. `PeripheralManagerImpl.swift:187-219`, `Advertiser.kt:47-50`, `:78-82` | The advertising `timeout` is ignored on iOS. On Android the radio stops but `isAdvertising` stays true natively and in the domain, so the next `startAdvertising` returns success without advertising. A timeout under 1 s becomes no timeout. | By reading | I081, I051 |

## New findings: Low and latent

| ID | Where | What happens | Evidence |
| --- | --- | --- | --- |
| L1 | Domain. `bluey_server.dart:606`, `:709` | `startAdvertising` has no state guard. A rejected restart rolls the state back to `idle` while the radio still advertises, and `stopAdvertising()` becomes a no-op. A platform error during stop strands the state in `stopping`. | Reproduced |
| L2 | Android native. `GattServer.kt:737-765` | The GATT server callback announces every new link as a central. Android also fires it for links this device opened as a client, so a peripheral we connect to can appear as a phantom `Client`. | By reading; needs a device check |
| L3 | Android native. `ConnectionManager.kt:650` | Callbacks are bound to a device id, not to a `BluetoothGatt` instance. A late callback from a closed gatt can tear down a newer connection to the same device. | By reading; related to I328 |
| L4 | Android native. `ConnectionManager.kt:249-280` | The 5 s disconnect fallback completes the disconnect but leaves a pending connect for the same device unanswered. The domain has no way to cancel a connect in flight. | By reading |
| L5 | Android native. `GattServer.kt:505-557` | `cleanup()` clears pending `addService` callbacks without calling them and emits no client disconnects, so Dart state goes stale if the engine outlives the activity. | By reading |
| L6 | Domain. `bluey_connection.dart:526` | `_setState` blocks only `ready` to `linked`. A re-emitting platform stream can move a `disconnected` connection back to `linked`. | By reading |
| L7 | Domain. `bluey_connection.dart:632` | `services()` re-discovers on every call by default, swaps the cached objects without disposing the old ones, and does not emit on `servicesChanges`. | By reading |
| L8 | Domain. `bluey.dart:565` | `tryUpgrade` called twice on one connection starts two lifecycle clients, so heartbeats and presence subscriptions double. | By reading |
| L9 | Domain. `peer_discovery.dart:166-190` | A device seen as the scan window closes is probed after `discover()` has returned, and can collide with the caller's next connect. A `stopScan` failure hides the results. | By reading |
| L10 | iOS native. `CentralManagerImpl.swift:561-567` | A disconnect the app requested reports failure when the link happened to drop with an error, although the link is down. `closeServer` leaves pending requests and a pending advertising completion unanswered. | By reading |
| L11 | Domain. `lifecycle.dart`, `lifecycle_server.dart` | `LifecycleInterval.decode` has a floor but no ceiling. A malformed heartbeat is acknowledged before it is decoded. | By reading |
| L12 | Repo | A fresh checkout does not resolve on current Flutter stable. No lockfile is committed and no SDK version is pinned. | Reproduced; related to I351 |

## Backlog items this audit would re-rate

| Item | Now | Suggested | Why |
| --- | --- | --- | --- |
| I063 Android late callback misroute | Medium, "uncertain" | High | H1 gives it a trigger that needs no timeout: any peer-initiated MTU change |
| I359 iOS pending-drops poison | Medium, latent | Medium, reachable | M1: the guards in `CentralManagerImpl` keep the drop from being consumed, so the fix is not only in `OpSlot` |
| I369 adapter controller leaks | Medium | Fix together with H3 and M3 | Same lifecycle gap seen from three layers |
| I336 overlapping scans | Low | Medium | M4 is the everyday trigger: restart a scan without awaiting the cancel |
| I350 iOS central seam | Open | Next up | `CentralManagerImpl` is 1005 lines with no direct test; M1 cannot be regression-tested without it |
| I351 continuous integration | Open | Next up | L12: the repo does not resolve on current stable, and nothing would have noticed |
| I013 scan failure code discarded | Medium | Fix together with M2 | Both are the missing error channel for scanning |

## Test setup today

Your read is right: the pure domain logic is well covered and the fake platform is strong. The gap is below the port, and between the layers.

| Layer | What exists | What it cannot do |
| --- | --- | --- |
| Domain (Dart) | 1120 tests on `FakeBlueyPlatform`: fault queue, latency, held operations, `FakeBleLink` for two roles on one link | Nothing checks that the fake behaves like the real adapters. It already differs: a new stream per scan (the adapters share one), no advertising timeout, no rejected scan start, no unsolicited MTU event |
| Dart adapters | 181 tests that stub single `BlueyHostApi` calls with mocktail | No model of the native side, so no multi-step scenario. M2 and M3 sat here |
| Kotlin | 12 JVM test files driving a captured `BluetoothGattCallback` through mockk | The mocked `Handler` runs `post` inline and makes `postDelayed` a no-op, so ordering and timeouts are not really exercised. Each test wires its own mocks; there is no reusable simulated peer |
| Swift | XCTest for `OpSlot`, the queues, the handle stores, and the server role through the `PeripheralManaging` seam | The central role has no seam (I350) |
| Across the Pigeon boundary | Nothing | No test runs Dart, the Pigeon codec and native code together. No `integration_test` exists |
| Automation | Six manual gates | No CI (I351) |
| Real radios | Example app stress tests on device pairs | Manual, slow, not repeatable |

All eight reproduced findings were reachable with today's fakes. They were missed because the scenarios are written from known bugs, and no test asks the general question "do the domain and the platform still agree after this sequence?".

## Proposed rig: scenarios without hardware

Hardware-free instrumentation is fully possible on Android and mostly possible on iOS. The Android emulator has a virtual Bluetooth radio that a scripted peer can join. The iOS Simulator has no Bluetooth at all, so iOS needs a simulated radio behind a native port.

*The diagram is in the audit's Claude Doc: one scenario language over five backends, tiers 0 to 4 as in the table below.*

A scenario is written once against a `ScenarioDriver` port. Each tier supplies a driver, so the same scenario proves the same behaviour with more real code underneath each time, and the fake can no longer drift from the real adapters unnoticed.

| Tier | What has to be built | Feasibility | Rough effort |
| --- | --- | --- | --- |
| 0 | A scenario vocabulary over `FakeBlueyPlatform`. Invariant checks after random operation sequences, for example `scanner.isScanning == platform.isScanning` and "a disconnected Connection has closed streams". | Certain; pure Dart | Days |
| 1 | A scripted fake of `BlueyHostApi` with state, replacing the per-call mocktail stubs. A contract suite that runs against the fake platform and both real Dart adapters. | Certain; pure Dart | Days |
| 2 | Kotlin: move the JVM tests to Robolectric so `Handler` ordering and `postDelayed` timeouts run on a virtual clock, plus a reusable simulated peer. Swift: the central seam from I350 and a fake peripheral. | High; standard tooling | 1 to 2 weeks |
| 3 | A native port over the OS Bluetooth API in each plugin, a simulated radio behind it for test builds, and a test-only Pigeon API so the Dart test can script that radio. The radio can deliver callbacks on background threads the way binder threads do. | High on both platforms. The Android port is the large part: `ConnectionManager` and `GattServer` call the framework directly today | 3 to 5 weeks; overlaps with I372 |
| 4 | A Bumble script per scenario, attached to the emulator's netsim controller, and a CI job with emulator support. | Android only. Bumble documents the android-netsim transport for emulator 33.1.4.0 or later and calls the feature still evolving; I have not run it against this project | 1 to 2 weeks, after tier 3 |

What no simulated tier can do is discover OS behaviour nobody knew about. Each quirk in `ANDROID_BLE_NOTES.md`, `IOS_BLE_NOTES.md` and the cross-platform quirks document should become a named behaviour of the simulated radio, so a quirk found once on a real device stays tested at every tier.

Two alternatives deserve a mention. Nordic's CoreBluetoothMock runs in the Simulator and covers both the central and the peripheral role, so it could stand in for a home-built iOS simulated radio at tier 3. The cost is that production code must use its `CBM` types in place of the CoreBluetooth ones, and it does not simulate prepared writes or connection events. It is worth a one-day spike before committing to a home-built iOS radio. Building the iOS code for macOS and driving a USB dongle with Bumble would exercise real CoreBluetooth, but it needs hardware and a Mac.

## Suggested order of work

1. **Fix the lifecycle gap from the failing tests.** H3, M3 and I369 are one change seen from three layers. H2 follows from it, because discovery needs the same registry of live connections.
2. **Give scanning and advertising one owner of state.** M2, M4, M5, M8, L1, I013 and I336 all come from the domain, the adapter and the native class each tracking the same fact.
3. **Correlate native completions.** H1 with I063 on Android, M1 with I359 on iOS. The Kotlin half is testable in today's harness; the Swift half needs the I350 seam first. Check the H1 trigger and L2 on a device or emulator while there.
4. **Harden the server.** M6 and M7.
5. **Put a floor under it.** CI (I351), a pinned Flutter version and a committed lockfile (L12), then tier 0 invariants and the tier 1 contract suite.
6. **Build tier 2, then decide on tier 3** with evidence of what tiers 0 to 2 caught.

The reproductions come as two test files with this report: `domain_audit_repro_test.dart` for `bluey/test/` and `android_adapter_audit_repro_test.dart` for `bluey_android/test/`. Each test asserts the expected behaviour and fails today, so each is a ready red step. Nothing was committed to the repository.

## Sources

- [Bumble: Android emulator transport](https://google.github.io/bumble/transports/android_emulator.html) for the `android-netsim` transport and its modes
- [Bumble: Android platform notes](https://google.github.io/bumble/platforms/android.html) for the emulator version and the stated limitations
- [Nordic CoreBluetoothMock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) for Simulator support, the roles covered and what is not simulated
- Repository documents read: `docs/roadmap.md`, `docs/backlog/`, both earlier reviews in `docs/reviews/`, `docs/testing-conventions.md` and `bluey_android/ANDROID_BLE_NOTES.md`

The statement that Android delivers peer-initiated MTU changes to the client callback rests on the project's own notes and my recollection of the platform, not on a page opened for this report.
