---
title: Bluey Full-Stack Deep Audit (2026-07-07)
audit_date: 2026-07-07
auditor: Claude Code (orchestrated multi-agent audit; every finding personally re-verified against source)
rubrics: [clean-architecture, domain-driven-design, clean-code, design-as-a-BLE-SDK]
scope: full monorepo incl. native (bluey, bluey_platform_interface, bluey_android [Dart+Kotlin], bluey_ios [Dart+Swift], bluey/example)
baseline: docs/backlog/REVIEW-2026-04-26-deep-review.md, docs/backlog/REVIEW-2026-04-26-ddd-followup.md
---

# Bluey Full-Stack Deep Audit — 2026-07-07

## Preamble

**Scope.** Every production source file in the workspace, read in full: `bluey/lib` (54 files, ~10.6k LOC), `bluey_platform_interface/lib` (~1.5k), `bluey_android` (Dart adapter ~1.6k + Kotlin ~5.7k hand-written), `bluey_ios` (Dart adapter ~1.6k + Swift ~3k hand-written), and `bluey/example` (~10.5k). Pigeon-generated `messages.g.*` were scanned (confirmed unmodified) not audited. The `bluey/test` suite (100 files, ~31k LOC) was assessed for TDD/clean-code discipline; fakes read in full.

**Method.** Fifteen full-coverage deep-read agents partitioned by territory, each judging against all four rubrics (Clean Architecture, DDD, Clean Code, and "design as a BLE SDK as a thing of its kind" with an external field scan vs. `flutter_blue_plus` / `flutter_reactive_ble`). **Every finding below was personally re-verified by re-reading the cited source** — citations are claims until read. The orchestrator ran the gates (deep-readers stayed static); over-flagged severities were re-graded on one ladder, and overstated/false claims were discarded (see *Adjusted / discarded claims*).

**Gates (run by the orchestrator).** `flutter analyze` → **No issues found**. `bluey` Dart tests → **1017 passing**. Android Kotlin `gradlew test` → **BUILD SUCCESSFUL**. Coverage `bluey/lib` → **90.1 %** (just meets the 90 % domain target). iOS XCTest was **not** run (needs a simulator/Xcode toolchain) — the Swift findings rest on static reading cross-checked against the Pigeon contract and Dart side.

---

## Verdict

**Bluey is a healthy, unusually well-crafted codebase with a sound architectural spine and a strong test culture. There are no CRITICAL findings and the build/test gates are green.** The Clean Architecture backbone is genuinely correct — the dependency rule holds graph-wide, there are no cycles, the port is the most-stable inward node, the public API leaks no platform DTOs, capability gating for asymmetric features is complete, and the layout screams the domain. The April 2026 review recommendations largely **landed and held** (handle-based identity, platform-tagged extensions, peer/connection composition, value objects, capability honesty). The SDK out-designs its field peers on API safety and honesty (`maxWritePayload` over `mtu-3`, built-in GATT op serialization, compile-time-visible platform asymmetry, a sealed actionable exception taxonomy, stable `ServerId`).

The gap between this codebase and excellent is a **long tail of latent correctness hazards and honesty leaks**, not structural rot. Three themes dominate:

1. **The flagship handle-based-identity design (post-I088) is silently bypassed on several live paths** — notifications are routed by UUID everywhere (domain, port DTO, both natives), and the iOS client's discovery-completion and op-routing still key by UUID string. Minting is correct; the *use* of handles is incomplete. For a device that exposes duplicate-UUID attributes (spec-legal), this produces cross-delivery and non-deterministically incomplete discovery.
2. **Several subsystems promise more than they deliver.** The README advertises bonding/PHY/connection-parameters as "✅ COMPLETE" while they throw `UnimplementedError` (no native impl exists); the user-op-accounting path (I097) is wired but inert in production; `ConnectionException`/`GattException` are documented-as-thrown but never constructed; four domain events (incl. `DisconnectedEvent`) are never emitted; the example app's "heartbeat tolerance" UI configures nothing; `Advertisement.isConnectable` is hardcoded `true`.
3. **Native server-side concurrency (Android) and iOS op-slot edge cases lag the disciplined client-side cores.** The Android client stack is rigorously main-thread-confined; the Android GATT *server* mutates shared maps on binder threads and doesn't serialize notifies. iOS's lockless-on-main design is sound, but its `OpSlot` timeout-drop accounting and server completion slots have latent poison/clobber failure modes.

Per-rubric one-liners:

| Rubric | Grade | One-line |
|---|---|---|
| **Clean Architecture** | Strong | Backbone verified clean; residue is DRY (state-mapper ×4) and a couple of documented ACL bypasses. |
| **Domain-Driven Design** | Strong | VOs immutable with construct-time invariants; bounded contexts respected; residue is a few anemic/leaky VOs, a domain concept in a platform enum, and business logic in the facade. |
| **Clean Code** | Good | Naming and docs are excellent; residue is God-objects, dead taxonomy, duplicated boilerplate, and test-timing discipline. |
| **Design as a BLE SDK** | Strong-but-narrow | Out-designs the field on safety/honesty; over-builds the peer layer; under-delivers on long-lived-connection resilience; docs oversell. |

**Count that actually needs fixing:** 1 MAJOR, ~30 MODERATE (clustered below), plus a long MINOR/OBSERVATION tail. Recommend fixing the MAJOR and MODERATE clusters M-A (handle identity) and M-B (error handling) first.

---

## Baseline disposition (April 2026 reviews)

The two April 2026 external reviews were verified against HEAD. A prior report's "fixes landed" is itself a claim; each was re-checked.

**Fixed and verified (protect these):**
- **I035** — Android bond/PHY/conn-param stubs now throw `UnimplementedError`; `Capabilities.android` honestly reports `canBond:false` etc. (no more silent-success lie).
- **I055 / I056 (connect leg)** — peer discovery filters the scan by control-service UUID; each probe's *connect* is bounded by `probeTimeout` (3 s default).
- **I057** — the duplicated, broken MAC→UUID coercion is gone; `DeviceAddress`/`ClientAddress` opaque value objects replace it.
- **I058 / I059** — `startAdvertising` threads the advertising `mode`; `removeService` is now `Future<void>` and awaited.
- **I065 / I066** — capability gating is load-bearing for asymmetric ops; `Connection` exposes only cross-platform members with `android`/`ios` typed extensions.
- **I088 (minting) / I300 / I301 / I302** — handles minted by identity; `PeerConnection` is composition (not upgrade-in-place); connection VOs carry construct-time invariants; glossary/vocabulary consistent.
- **I017** — `peerSilenceTimeout` unified at 30 s everywhere, rationale documented.
- **I098 (client side)** — Android `ConnectionManager` is main-thread-confined; `GattOpQueue` reentrancy/timeout handling is sound.
- **I045** — iOS `disconnectCentral` "lying no-op" removed entirely from Pigeon + native (deliberate: neither platform can honor it). See DA-01 for the residual doc reference.

**Partial / still-open (carried into findings below):**
- **I054** → *partial*. Read/write/notify/servicesDiscovered events are now emitted; `DisconnectedEvent`/`DebugEvent`/`ReadRequestEvent`/`WriteRequestEvent` are still dead → **DA-22**.
- **I088 (usage)** → *incomplete*. Handles are minted but notification routing and iOS client discovery/op-routing still key by UUID → **DA-02/03/04/05**.
- **I086** → *open*. `removeService`↔notify race is live on the domain side (stale handle table) → **DA-28**.
- **I098 (server side)** → *open*. Android GATT server has binder-thread races the client side doesn't → **DA-14..19**.
- **I097** → *reversed/inert*. User-op accounting landed but is inert in production (characteristics carry no lifecycle client) → **DA-20**.
- **I047** → the respond-to-first behavior is the Apple-mandated contract (as the April review suspected); residual is the multi-emit smell → MINOR K8.
- **I048** → still open (no iOS state restoration) → OBSERVATION / DA-35.

---

## Findings

Grouped by severity, then by theme. IDs are `DA-##` (Deep Audit, audit #1). Each carries rubric tag(s) and the originating territory. `[latent]` = real but requires a specific device topology or error condition.

### CRITICAL

None. (Gates green; the sophisticated concurrency cores are verified sound. This is the expected result for healthy code.)

### MAJOR

**DA-01 — Docs advertise unshipped features as complete; product-facing honesty gap** · `sdk-design`, `docs`
`README.md:7-8,23-25` mark "Phase 2: Android Platform ✅ COMPLETE" and "✅ Bonding/pairing support / ✅ PHY configuration / ✅ Connection parameter control". A repo-wide grep of `bluey_android/android` finds **no** native `createBond`/`setPreferredPhy`/`requestConnectionPriority` implementation, the Pigeon schema declares none, and the Dart adapter throws `UnimplementedError('… (I035)')`; `Capabilities.android` reports `canBond:false` etc. So on Android these features throw, and on iOS `connection.android` is null — *no* platform ships them. A consumer selects the library partly for advertised capability it does not have. Same doc-staleness family: `CLAUDE.md:142` glossary still lists a removed `disconnectCentral`, and the header claims "543 tests" (actual: 1017). **Fix:** mark bond/PHY/conn-params as "planned (Stage B)" in README/CHANGELOG; correct the CLAUDE.md glossary and test count. (The runtime is already honest — this is purely a documentation defect, but it is the first thing a consumer reads.)

### MODERATE

#### Cluster M-A — Handle-based identity (post-I088) is bypassed on live paths
The flagship correctness design (opaque handles disambiguate duplicate-UUID attributes) is not carried through to several paths. All `[latent]` — they bite only when a peripheral exposes duplicate-UUID attributes (spec-legal; e.g. repeated standard characteristics or two instances of a service).

- **DA-02 — Notifications routed by UUID, not handle** · `correctness`, `ddd` · A2/G2/K10 · `[latent]` — `PlatformNotification` carries no handle (`platform_interface.dart:611-614`); the domain demux filters by lowercased UUID string (`bluey_connection.dart:1325-1331`); both natives emit UUID-only `NotificationEventDto`. Two same-UUID notifying characteristics cross-deliver to both subscribers. **Fix:** add `characteristicHandle` to `PlatformNotification` + native DTOs (reverse-lookup via the handle store) and route by handle.
- **DA-03 — iOS client discovery-completion tracker keyed by UUID** · `correctness` · K1 · `[latent]` — `pendingCharacteristicDiscovery` is a `Set<String>` keyed by UUID (`CentralManagerImpl.swift:667`, removal `:696`) while minting is by object identity (`:677`). Duplicate-UUID characteristics collapse to one Set entry; `checkDiscoveryComplete` can fire before the second characteristic's descriptors are discovered → a non-deterministically incomplete `ServiceDto`. **Fix:** key the pending Sets by minted handle / `ObjectIdentifier`.
- **DA-04 — iOS client op-slots + callback routing keyed by UUID** · `correctness` · K2 · `[latent]` — read/write/notify/descriptor `OpSlot` caches and delegate-callback routing key by `characteristic.uuid` (`CentralManagerImpl.swift:312-314, 803-868`). Overlapping ops on two same-UUID attributes share one slot; a callback completes the wrong op. **Fix:** key op-slots/routing by minted handle.
- **DA-05 — Server notify collapses (service,char) 2-tuple to char** · `correctness`, `sdk-design` · D3 · `[latent]` — `_resolveLocalHandle` returns the first UUID match ignoring service (`bluey_server.dart:548-554`); the public notify API can't address a char UUID hosted under two services. Documented foot-gun, but re-introduces the exact collapse the handle table was built to avoid. **Fix:** add an optional `service`/handle-typed overload; throw on ambiguity (mirror the client-side singular-accessor policy).

#### Cluster M-B — Error handling swallows or mis-signals
- **DA-06 — Peer-upgrade `catch(_)` conflates transient failure with "not a peer"** · `clean-code`, `sdk-design` · E1 — `_tryBuildPeerConnection`'s outer `catch (_) { return null; }` (`bluey.dart:779-782`) wraps `services()`, `lifecycleClient.start`, and `PeerConnection.create`; any transient GATT failure becomes a permanent "not a peer", which `connectAsPeer` turns into `throw NotABlueyPeerException` (`:528-533`). **Fix:** only the explicit "control service absent" branch maps to not-a-peer; let discovery/read exceptions propagate.
- **DA-07 — Failed/absent ServerId read fabricates a random identity** · `ddd`, `correctness` · E2 — on a ServerId read/decode failure with the control service present, `serverId ?? ServerId.generate()` (`bluey.dart:740-748,776`) mints a fresh random UUID, silently defeating the stable-identity guarantee that is the Peer module's reason to exist. A caller persisting it later targets a nonexistent server. **Fix:** treat "control service present but identity unreadable" as an explicit failure, never fabricate a stable identity.
- **DA-08 — Raw platform errors leak onto domain streams / not translated** · `clean-arch (ACL)` · A4/I1 — `stateChanges`/`bondStateChanges`/`phyChanges`/`notifications` `onError` re-emit the raw platform error without `translatePlatformException` (`bluey_connection.dart:220-222,254-256,272-274,1348-1350`); iOS `respondToWriteRequest` drops the `bluey-not-found` translation the read path has (`ios_server.dart:200-229`). Consumers can receive a `PlatformException` where the sealed `BlueyException` contract is promised. **Fix:** route stream `onError` through the ACL; give the write-respond path the same translation as read.
- **DA-09 — `readRequests`/`writeRequests` throw `StateError` into the consumer's stream** · `clean-code`, `sdk-design` · D5 · `[latent]` — a client-gone race makes the `.map` throw `StateError` (`bluey_server.dart:790-796`), delivered as a stream error; a consumer without `onError` gets an unhandled error and may lose the subscription. **Fix:** capture the `Client` at the eviction chokepoint (membership already proven) or drop/respond-error the orphaned request.

#### Cluster M-C — Latent runtime hazards
- **DA-10 — Heartbeat busy-loop on a malformed/zero interval** · `correctness`, `battery` · B2 · `[latent]` — `decodeInterval` guards only `length < 4` (`lifecycle.dart:232-239`); a 4-byte value decoding to 0/negative yields `heartbeatInterval ~/ 2 == 0`, and `_beginHeartbeat(Duration.zero)` (`lifecycle_client.dart:348-352`) busy-loops — the only downstream guard is an `assert` (stripped in release). **Fix:** clamp/reject non-positive decoded intervals to `defaultLifecycleInterval`.
- **DA-11 — iOS `OpSlot.pendingDrops` poison cascade** · `correctness` · K3 · `[latent]` — `pendingDrops` is a bare count (`OpSlot.swift:114-124,152-161`); a genuinely lost callback leaves it at 1, so the *next* op's real completion is consumed as a "drop", spuriously times out, and re-poisons — self-healing only on disconnect. **Fix:** correlate each expected drop with the timed-out entry id.
- **DA-12 — iOS server completion clobbering** · `correctness` · K4 · `[latent]` — `addService`/`startAdvertising` store completions in single-value slots keyed by UUID / a lone optional (`PeripheralManagerImpl.swift:134-136,218`); a concurrent/duplicate call overwrites the first caller's completion, orphaning its `Future` forever. **Fix:** queue completions (OpSlot-style) or reject a second in-flight call.
- **DA-13 — `ConnectionParameters` invariant omits the BLE-spec ×2 factor** · `ddd`, `correctness` · B1 — `minTimeout = (1 + latency) * interval` (`connection_parameters.dart:26`); the spec (Vol 6 Pt B §4.5.2) requires the supervision-timeout floor to be `(1 + latency) * interval * 2`. The VO accepts sub-spec triples the controller will reject — the exact band that risks premature teardown. **Fix:** add the `× 2`; pin with a boundary test.

#### Cluster M-D — Android native GATT-server concurrency (client side is clean)
The Android *client* stack is rigorously main-thread-confined; these are all on the *server*/advertiser side.
- **DA-14 — `GattServer` mutates shared maps on binder threads** · `correctness` · J1 · `[latent]` — `connectedCentrals`/`centralMtus`/`characteristicByHandle` (plain `mutableMapOf`) are written on binder-thread callbacks (`GattServer.kt:695-696,754-776`) while read on main; risk of `ConcurrentModificationException` in `handleForCharacteristic` and dropped centrals in `notifyCharacteristic`. **Fix:** marshal mutations onto `handler.post` (as STATE_DISCONNECTED already does for `subscriptions`) or use concurrent structures.
- **DA-15 — Server notify has no per-central serialization + ignores send status** · `correctness` · J3 — `sendNotification` fires all recipients back-to-back and discards `notifyCharacteristicChanged`'s return (`GattServer.kt:363-366,1229-1236`); Android requires waiting for `onNotificationSent`. Under load: silent drops + FIFO desync of `pendingNotifications`. **Fix:** a per-central send queue gated on `onNotificationSent` (mirror the iOS `PendingNotificationQueue`).
- **DA-16 — `Thread.sleep(100)` on the main thread** · `correctness`, `clean-code` · J4 — `ensureServerOpen` sleeps on the platform thread on the retry path (`GattServer.kt:638-641`), an ANR risk. **Fix:** `handler.postDelayed` continuation.
- **DA-17 — Binder-thread Pigeon reply + map mutation** · `correctness` · J5 · `[latent]` — `onServiceAdded` and the Advertiser callbacks invoke the Pigeon reply and mutate `pendingServiceCallbacks`/`isAdvertising` on a binder thread (`GattServer.kt:840-848`, `Advertiser.kt:136-167`). **Fix:** wrap in `handler.post`.
- **DA-18 — `connect()` returns idempotent success during in-flight disconnect** · `correctness` · J6 · `[latent]` — `connect` checks `connections` but not `pendingDisconnects` (`ConnectionManager.kt:143-152`); a connect issued in the disconnect window returns success, then STATE_DISCONNECTED tears it down. **Fix:** reject/chain when `pendingDisconnects` contains the device.
- **DA-19 — `GattOpQueue` misattributes a late callback to the next op** · `correctness` · J2 · `[latent]` — no per-op correlation; a post-timeout stray callback completes whatever `current` is (`GattOpQueue.kt:53-57`), giving op B op A's bytes. **Fix:** pass the callback's target attribute into `onComplete` and verify it matches.

#### Cluster M-E — Promised-but-not-delivered surface
- **DA-20 — User-op-accounting (I097) is inert in production** · `clean-code`, `sdk-design` · A3 — characteristics are built with no `lifecycleClient` and `_lifecycle` defaults to `() => null` (`bluey_connection.dart:1029-1034,1209`), so every `lifecycleClient: _lifecycle()` hook and `recordActivity()` is a permanent no-op; the "defer probes while a user op is in flight" optimization never engages outside tests. **Fix:** remove the inert plumbing, or wire it for real via the peer path.
- **DA-21 — Dead-but-documented exception taxonomy** · `clean-code`, `sdk-design` · F1/F2 — `ConnectionException` is never constructed (only defined) yet three docs promise "Throws [ConnectionException]" (`bluey.dart:412,496`, `peer.dart:40`); `GattException`+`GattStatus` are dead, superseded by `GattOperationFailedException`. Consumers catch types that never fire. **Fix:** delete the dead types and correct the docs, or make the ACL emit them.
- **DA-22 — Dead/unemitted domain events; observability slice untested** · `clean-code`, `test` · F3/O3 — `DisconnectedEvent`, `DebugEvent`, `ReadRequestEvent`, `WriteRequestEvent` are never emitted (`events.dart`), so `bluey.events` shows every connect but no disconnect. Separately, 13 *emitted* event types have zero test assertions (the 25 %-covered `events.dart`). **Fix:** emit `DisconnectedEvent` at the disconnect site and wire request events; assert the event bus in connect/server integration tests.
- **DA-23 — Advertisement/scan surface promises data the pipeline never fills** · `ddd`, `sdk-design` · C1/C6/C7 — `isConnectable` is hardcoded `true` on every scan result (`bluey_scanner.dart:385`); `serviceData` is always `{}` and `txPowerLevel` always null (the `PlatformDevice` DTO carries neither); the `ScanMode` enum is dead (zero refs). **Fix:** thread the fields through `PlatformDevice`/native parsing, or remove them until supported; wire or delete `ScanMode`.

#### Cluster M-F — Duplication of knowledge (DRY)
- **DA-24 — `BluetoothState` mapper duplicated verbatim ×4** · `clean-arch`, `clean-code` · L1 — the identical 5-case platform→domain switch lives in `bluey.dart:965`, `bluey_connection.dart:311`, `bluey_server.dart:293`, `bluey_scanner.dart:86` — directly contradicting the codebase's own principle (stated in `error_translation.dart`) that ACL mappings must live in exactly one place. **Fix:** hoist one `mapBluetoothState` into `shared/`.
- **DA-25 — Peer-upgrade sequence triplicated + business logic in the composition root** · `clean-arch (SRP)`, `ddd` · E3 — the "connect → discover → find control service → read+decode ServerId → start heartbeat → wrap" sequence is implemented three times (`bluey.dart:_tryBuildPeerConnection`, `peer_discovery.dart`, `bluey_peer.dart`), the first being ~85 lines of domain logic inside the `Bluey` facade that should only wire+delegate. **Fix:** extract a `PeerConnectionFactory` into `src/peer/`; the facade delegates.

#### Cluster M-G — Resource lifecycle
- **DA-26 — `dispose()` doesn't invalidate → post-dispose resurrection** · `clean-code`, `sdk-design` · C4/D7 — neither `BlueyScanner.dispose` (`bluey_scanner.dart:340-366`) nor `BlueyServer.dispose` sets the `_invalidated` flag that `_ensureValid` checks, so a post-dispose `scan()`/`addService` passes validation and partially restarts over closed controllers. **Fix:** set a terminal `_disposed` flag; reject in `_ensureValid`.
- **DA-27 — Per-device stream controllers leak on failed/spontaneous disconnect** · `sdk-design` · H2/I2 · `[latent]` — both adapters insert per-device controllers before the `await connect` and prune only on explicit `disconnect()` (`android_connection_manager.dart:91-101`, `ios_connection_manager.dart:92-112`); a failed connect, a remote drop, or reconnect-without-disconnect leaks/orphans them. The domain never calls `_platform.disconnect()` on spontaneous drops. **Fix:** prune+close in the terminal-disconnect callback and around the connect failure.
- **DA-28 — `removeService` never prunes the handle table** · `correctness`, `ddd` · D1 · `[latent]` — `_localCharHandles` is written and read but never pruned (`bluey_server.dart:519-560`); after `removeService`, `notify` resolves a stale handle → platform error / the live domain side of the still-open I086. **Fix:** evict the removed service's `(svc,char)` entries.

#### Cluster M-H — Value-object / DTO integrity
- **DA-29 — Mutable `Uint8List` escapes `@immutable` value objects** · `ddd` · F4/C9/D10 · `[latent]` — `ManufacturerData` (`manufacturer_data.dart:17-22`) and `Advertisement.serviceData` values (`advertisement.dart:36-37`) store/return byte buffers by reference with no defensive copy, though both define value equality over those bytes; `startAdvertising` also stores the caller's `services` list by reference into event state. Post-construction mutation silently corrupts equality/hash. **Fix:** copy on construction (`Uint8List.fromList` / `List.unmodifiable`).
- **DA-30 — Inconsistent value equality across `@immutable` platform DTOs** · `ddd`, `clean-code` · G4 — 12 of 17 `@immutable` DTOs declare no `==`/`hashCode` (reference equality) while 5 do, with no documented rule; any future `Set`/`distinct`/dedup on them silently falls back to identity. **Fix:** add value equality uniformly (matching the exemplary `PlatformLogEvent`) or document the input-vs-output split.

#### Cluster M-I — Structure (God-objects)
- **DA-31 — God-objects across layers** · `clean-arch (SRP)`, `clean-code` · A9/D4/J12/K9 — `BlueyConnection` (~957 LOC in one class), `BlueyServer` (~1099), Kotlin `ConnectionManager` (1088) / `GattServer` (1260), Swift `CentralManagerImpl` (999) each carry ~6–10 responsibilities (state machine + op dispatch + handle tables + DTO mapping + notification aggregation). These sit behind narrow public interfaces (no boundary violation) but concentrate change-risk and are where the M-A/M-D subtle bugs hide. **Fix (incremental):** extract enum/DTO mappers, the stream-replay helper (see MINOR A6), and per-device op registries.

#### Cluster M-J — Domain ↔ platform boundary
- **DA-32 — Domain concepts / types cross into the platform layer** · `ddd`, `clean-arch` · G3/L2 — `PlatformGattStatus.lifecycleEviction` (`platform_interface.dart:813`) embeds a Bluey-protocol concept in an otherwise BLE-spec-generic enum; `lifecycle_client.dart` branches on raw `platform.GattOperation*Exception` types outside the ACL (`:235,721-734`). Both are documented/intentional (the eviction status compensates for the deliberately-removed per-central disconnect; the lifecycle client operates on the pre-translation path) but each is a second place that must change when the platform taxonomy does. **Fix:** model eviction as a generic application-range status; centralize platform-exception classification in one domain helper.

#### Cluster M-K — SDK design bets & gaps
- **DA-33 — Peer/lifecycle heartbeat is an always-on, high-cost, leaky bet** · `sdk-design` · M2/M3 — the only library in the field that manufactures a reliable iOS client-disconnect signal, but it spends continuous heartbeat airtime/battery, exposes two tunable timeouts, and surfaces the iOS shared-`CBPeer` trap as multi-paragraph caveats on `connectAsPeer`/`PeerConnection.disconnect` rather than preventing it. Sound and differentiating for symmetric peer apps; heavy for the central-only consumer. **Fix:** none required (opt-out via `lifecycleInterval: null` exists); document the cost, and consider an internal same-`CBPeer` guard so the safe path is the default.
- **DA-34 — `connection.android.mtu` is a stale cache** · `sdk-design` · M4/H7/I6 — the getter reflects only the last explicit `requestMtu`; peer-initiated `onMtuChanged` is not wired into the cache (documented at `android_connection_extensions.dart:99-108`). A consumer sizing buffers from `mtu` (the `flutter_blue_plus` mental model) can mis-size. Mitigated by steering everyone to `maxWritePayload`. **Fix:** wire `onMtuChanged`, or demote `mtu` to diagnostic-only in the type.
- **DA-35 — Missing long-lived-connection resilience** · `sdk-design` · M5/K14 — no reconnection/autoConnect policy and no iOS state restoration (`CB…OptionRestoreIdentifierKey` absent, `CBCentralManager(delegate:nil, queue:nil)`), where real always-connected BLE apps live. On the roadmap; the most consequential *breadth* gap vs. the field. **Fix:** a reconnection policy object + iOS restoration plumbing.

#### Cluster M-L — Observability & test discipline
- **DA-36 — Two overlapping diagnostic channels double-emit** · `sdk-design` · F7 — every lifecycle signal is emitted on both `bluey.events` and `bluey.logEvents` (`lifecycle_client.dart:570-680`), with an inconsistent `_deviceAddress` guard on one but not the other. Dual-maintenance is what let DA-22's events rot. **Fix:** document the division of labor; make the guards consistent.
- **DA-37 — Tests use real wall-clock waits, violating the "simulate time" rule** · `test` · O1 — 35+ non-zero `Future.delayed` sleeps across 6+ files (e.g. `scanner_test.dart:161` waits out a real `Timer`; `bluey_server_test.dart` uses `ms:10` drains) despite `fakeAsync` being used impeccably in 12 timer-SUT test files. Slow + flaky-under-load; contradicts the standing project rule. **Fix:** `pumpEventQueue()` for stream drains; `fakeAsync`/`elapse` for the timeout tests.
- **DA-38 — Four hand-rolled `MockBlueyPlatform` doubles bypass the mandated fake** · `test` · O2 — `bluey_test.dart`, `bluey_connect_test.dart`, `bluey_connection_test.dart`, `bluey_server_test.dart` each declare a ~52-override `MockBlueyPlatform` and reference `FakeBlueyPlatform` zero times, and the doubles have diverged. CLAUDE.md mandates the fake. Five parallel `BlueyPlatform` implementations must move in lockstep. **Fix:** migrate onto `FakeBlueyPlatform` (extend with the few missing seams).
- **DA-39 — An integration test asserts on the fake, not the SUT** · `test` · O4 — `error_scenarios_test.dart:79-85` ("throws when reading from disconnected device") calls `fakePlatform.readCharacteristicByUuid(...)` directly rather than the domain `char.read()`; it tests the double, not bluey. **Fix:** exercise through the domain object; sweep siblings for the pattern.

#### Cluster M-M — Example app teaches gaps
- **DA-40 — Reference app omits the iOS shared-link guard in a bidirectional app** · `sdk-design (reference quality)` · N1 — the app keeps scanner + server alive together (`app.dart:57`) yet `connect`s with no `isClientConnected` guard (`grep` → zero hits), the exact pattern the library docs mandate against for iOS. A consumer copying it inherits the infinite-reconnect trap. **Fix:** guard the connect path and comment why.
- **DA-41 — Example "heartbeat tolerance" UI is inert** · `sdk-design`, `clean-code` · N2 — the `peerSilenceTimeout` setting is threaded through four layers then dropped (`bluey_connection_repository.dart:13-19` ignores `settings`), and the app uses `connect()` (which has no such parameter) not `connectAsPeer`; the visible disconnect/reconnect on change makes the inert feature look functional. **Fix:** route through `connectAsPeer(peerSilenceTimeout:)`, or remove the feature.
- **DA-42 — Stringly-typed disconnect control flow** · `clean-code` · N3 — the disconnect dialog is keyed off the literal `state.error == 'Device disconnected'` matched across two files (`connection_cubit.dart:117`, `connection_screen.dart:86`). **Fix:** model the reason as an enum on the state.

### MINOR
Real, cheap, low-risk. (Full detail in the audit ledger; grouped here.)

- **API contract:** `descriptor()` throws `CharacteristicNotFoundException` for a missing *descriptor* — no `DescriptorNotFoundException` exists (A5/C5). Documented quick-start example throws because sync `service()` requires a prior `await services()` and conflates not-discovered vs absent (A1). `tryUpgrade` is query-named but starts a live heartbeat (E4/CQS). `notifications` getter mutates state + throws (A8/CQS). `probeTimeout` bounds only the connect leg, not discover/read (E5). Android `indicate` silently downgrades to `notify`, distinction unrecoverable, docstring wrong (H1/G8).
- **Robustness:** `disconnect()` strands in `disconnecting` and leaks subs if the platform call throws (no `finally`, A7). `ConnectionInterval`/float VOs admit `NaN` (B4). iOS Service-Changed/power-off don't drain client op-slots → hang until timeout (K6). iOS read-vs-notification heuristic can misroute (K5). iOS `authorize()` infers permission from adapter power, returns `true` for `.poweredOff`/`.unknown` (K12). Kotlin: `BlueyLog` never unbound on detach (J7); `cleanup()` doesn't clear handle tables (J9); `connect`-timeout races STATE_CONNECTED → zombie queue (J10); `Scanner.onScanFailed` no teardown/error surface (J11); `mapDescriptors` O(n²) + `error()` can hang the discover future (J13); non-volatile `isAdvertising` cross-thread (J8).
- **DRY / naming / consistency:** duplicated control-service lookup in `start`/`_refreshFromServices` (B5); `~/2` heartbeat ratio magic number ×2 (B6); three divergent scan-teardown paths leak a controller (C8); duplicated `_invalidate`/`dispose` teardown, already drifted (D6); `_disconnectionsAnnounced` grows unbounded (D8); unchecked `client as BlueyClient` downcasts → raw `TypeError` (D9); `ServerId.generate`/`fromBytes` duplicate the hex block (E6); `_BlueyPeer.connect` downcast + leak on discovery throw (E7); `BlueyException.toString()` drops the concrete type + `action` (F5); `OperationNotSupportedException` vs `UnsupportedOperationException` name collision (F6); events/logger use `DateTime.now()` not `clock.now()` (F8); server error-translation covers 2 of ~9 host calls (H4); three overlapping translators (H6); Kotlin/Swift magic-number MTU 23 and hardcoded op timeouts (J15/K11); iOS `addService` positional force-cast assumes 1:1 alignment (K15); example: mislabeled "(MS)"/seconds field (N4), dead widgets/helpers (N5), fire-and-forget `close()` cancellation (N6); tests: `Future.delayed(Duration.zero)` as a stream barrier ×157 (O5), doubles named "Mock" that are stubs (O6).

### OBSERVATION
Recorded, no action implied.

- **Structure / scope:** fat `BlueyPlatform` port spanning six contexts (ISP, mitigated by the plugin idiom) (G5/L4); the facade hosts peer orchestration (L5); `ServerId` housed in the Peer context but an inbound dependency of Connection/Server (CLAUDE.md intends this) (E8); example: 15 one-line pass-through use cases + `GetServer` leaking the raw `Server` into presentation (N7); inconsistent state-equality strategy across example features (N8).
- **Design gaps (mostly on the roadmap):** no iOS state restoration (I048/K14); capability matrix omits state-restoration + 5 informational flags (`canScan` etc.) don't gate anything (G1/G11); `indicate*`/`notify*` distinction decorative at the port (G8); included-service characteristics map to handle 0 (K16); `ScanConfigDto.timeoutMs` a Dart-side concern, ignored natively (K18); Bluey streams deliberately error/terminate (arguably better than the field's "never close" but a portability mismatch) (M6).
- **Dead code / hygiene:** `subscribedCentrals` write-only, UUID-keyed (K7); `Data.toFlutterData()` unused (K13); dropped native callbacks — `onMtuChanged`/subscribe/unsubscribe/`onScanComplete` (H7/I4/I5); fire-and-forget `flutterApi.*` events (K17); hand-rolled `_listEquals` to dodge `flutter/foundation` while `flutter` stays a dep (G9); domain imports `flutter/services` `PlatformException` in the ACL (F9/L3); `main.dart` subscribes to events after `create()`, missing create-time events (N9); low-coverage VO/constant files are partial-exercise not dead (O7); Android native mockito use is legitimate (O8).

---

## What is genuinely healthy (protect on purpose)

These are verified strengths; "fixes" that erode them would be regressions.

- **Clean Architecture backbone (verified graph-wide).** Dependency rule holds — no `bluey_android`/`ios` import anywhere in `bluey/lib`; no cycles; DIP satisfied (inner defines the port, adapters register via `BlueyPlatform.instance = …`); the public API leaks no platform DTOs (all 16 exported interfaces swept clean; only `Capabilities` re-exported); capability gating is **complete** for every asymmetric op; screaming, context-first layout; per-context uni-directional seam translation. This is the load-bearing achievement of the codebase.
- **The exception ACL is total and centralized** — all 8 platform exception types map at one site, with an idempotent re-translation guard and a `PlatformException` + `Object` backstop.
- **Value objects are real** — `UUID`, `Mtu`, `PeripheralLatency`, `SupervisionTimeout`, `AttributeHandle`, `WritePayloadLimit`, `ServerId` are immutable, equality-by-value, with construct-time invariants; sealed `BlueyException`/`BlueyEvent` hierarchies give exhaustive matching.
- **The disciplined concurrency cores.** Android `ConnectionManager` is genuinely main-thread-confined (I062/I098); `GattOpQueue` reentrancy/timeout handling and `gatt.close()` on all four teardown paths are correct; `PendingRequestRegistry` is properly lock-guarded. iOS handle *minting* is by object identity (correct under duplicate UUIDs); the lockless-on-main design is sound given the `queue: nil` + Pigeon-on-main invariant; disconnect drains every op-slot; the `PendingWriteQueue`/`PendingNotificationQueue` (I339/I040) complete-on-hand-off with no silent drops.
- **SDK design bets that pay off** (vs. the field): `maxWritePayload(withResponse:)` clamped to 512 (retires `mtu-3` folklore); built-in native GATT op serialization (others make it opt-in or omit it); compile-time-visible platform asymmetry via `connection.android?`/`ios?` + `Capabilities`; a sealed, `action`-carrying exception taxonomy; handle identity + `AmbiguousAttributeException` (vs. the field's silent first-match); stable `ServerId` (answers `flutter_blue_plus`'s rotating iOS `remoteId`); one merged Dart+native structured log stream.
- **`FakeBlueyPlatform` is production-grade** — mirrors real handle minting, capability-gated throws, CCCD-per-instance handling, with rich typed test seams; `fakeAsync` is used impeccably wherever a timer is the SUT; tests are independent (no `setUpAll` globals); the example app's `maxWritePayload` usage, Android-extension gating, `BlueyException` handling, and resource disposal are exemplary reference patterns.

---

## Adjusted / discarded claims (verification made visible)

Deep-readers over-flag; the orchestrator re-graded or discarded these on re-reading source:

- **DISCARDED — E9 (import ordering in `bluey.dart`).** `flutter analyze` is clean, so there is no `directives_ordering` violation. Dropped.
- **DOWNGRADED — C2 (ScanResult `lastSeen` "defeats dedup", MAJOR→MINOR).** Confirmed `_mapScanResult` drops `lastSeen` (fresh `DateTime.now()`), but `BlueyScanner` has **no** dedup relying on `ScanResult` equality — the "dedup defeated" consequence was overstated. Residue is only the wall-clock-in-a-VO / `clock.now()` rule violation → MINOR.
- **DOWNGRADED — G10 (no per-central disconnect primitive, MODERATE→MINOR) / re-scoped.** `disconnectCentral` was **deliberately removed** from all three packages (CHANGELOGs + IOS_BLE_NOTES: neither platform can honor a force-disconnect) — this resolves I045, it is not a missing-primitive *defect*. The only residue is the stale `CLAUDE.md` glossary reference (folded into DA-01).
- **DOWNGRADED — B1/A1/C1/C6/D1/E1/E2/H1/I1/M1 (MAJOR→MODERATE where noted).** Several agents graded latent or error-path defects as MAJOR; re-graded to MODERATE per the ladder (a real defect that needs a specific device topology or error condition is the hazard it is, not broken-now). M1 (docs) is kept MAJOR as the sole one, being live and consumer-facing.
- **CONFIRMED-BUT-CONTEXTUALIZED — K8 (iOS batched-write respond-to-first).** The single `respond(to: requests.first, …)` is the Apple-mandated contract for a batched write (as the April I047 review suspected); the residual is only the multi-emit-with-shared-requestId smell → MINOR.
- **CONFIRMED, agent's own caveat noted — B2, K1, J1** re-read and confirmed by the orchestrator against source (busy-loop guard absent; UUID-keyed Set vs identity mint; binder-thread map mutation the code itself comments on).

No fabricated citations were found; agent line references matched HEAD (minor ±drift only).

---

## Recommendations

| # | Action | Finding IDs | Rubric | Effort |
|---|---|---|---|---|
| R1 | Correct the README/CHANGELOG/CLAUDE.md to match shipped capability (bond/PHY/conn-params = planned; fix test count + removed `disconnectCentral`) | DA-01 | sdk/docs | S |
| R2 | Complete the handle-identity migration: add `handle` to `PlatformNotification` + native DTOs; key iOS client discovery/op-routing by handle; add a service-qualified server notify | DA-02..05 | correctness | L |
| R3 | Fix the error-handling seams: narrow the peer-upgrade catch; never fabricate a `ServerId`; translate stream `onError`; don't throw into request streams | DA-06..09 | correctness/clean-arch | M |
| R4 | Close the latent hazards: clamp decoded interval; correlate `OpSlot` drops; queue iOS server completions; add the ×2 to `ConnectionParameters` | DA-10..13 | correctness/ddd | M |
| R5 | Harden Android GATT-server concurrency to the client side's standard (marshal to main; serialize notifies; no `Thread.sleep`) | DA-14..19 | correctness | M–L |
| R6 | Delete or deliver the promised-but-inert surface (lifecycle hooks, dead exceptions/events, unfillable ad fields, `ScanMode`) | DA-20..23 | clean-code/sdk | M |
| R7 | DRY the state-mapper; extract a `PeerConnectionFactory` from the facade | DA-24..25 | clean-arch | S–M |
| R8 | Resource lifecycle: terminal `_disposed` flag; prune controllers on drop; prune handles on `removeService` | DA-26..28 | clean-code | S–M |
| R9 | VO/DTO integrity: defensive-copy byte buffers; uniform DTO equality | DA-29..30 | ddd | S |
| R10 | Test discipline: migrate off `MockBlueyPlatform` to the fake; replace real-time waits with `fakeAsync`/`pumpEventQueue`; assert the event bus; fix the SUT-vs-fake test | DA-22,37,38,39 | test | M |
| R11 | Example app: add the iOS shared-link guard; make (or remove) the tolerance feature; de-stringly-type the disconnect flow | DA-40..42 | sdk/reference | S–M |
| R12 | Incremental de-God-object-ing behind the existing interfaces (mappers, stream-replay helper, op registries) | DA-31 | clean-arch | M (ongoing) |

**Suggested order.** R1 first (cheap, stops the docs from misleading). Then R2 + R3 (the two highest-value correctness clusters — the handle-identity gap undermines a headline guarantee across the whole stack, and the error seams are on core paths). R4 and R5 next (latent hazards, native concurrency). R6–R9 are mostly small, high-clarity wins that can land opportunistically. R10 (test discipline) should ride alongside R2–R5 so the new behavior is TDD-pinned with the fake and `fakeAsync`. R11/R12 last. Per the audit method, each fix lands test-first at the root cause, in the home the design assigns, with the whole gate green before merge.

---

## Coverage

| Territory | Read | By |
|---|---|---|
| `bluey/lib/src/connection` (core) | in full | deep-reader A + orchestrator re-verify |
| `bluey/lib/src/connection` (lifecycle + value objects) | in full | deep-reader B + re-verify |
| `bluey/lib/src/discovery` + `gatt_client` | in full | deep-reader C + re-verify |
| `bluey/lib/src/gatt_server` | in full | deep-reader D + re-verify |
| `bluey/lib/src/peer` + `src/bluey.dart` facade + export barrel | in full | deep-reader E + re-verify |
| `bluey/lib/src/shared` + `events` + `event_bus` + `log` + `platform` | in full | deep-reader F + re-verify |
| `bluey_platform_interface/lib` | in full | deep-reader G + re-verify |
| `bluey_android/lib` (Dart adapter) | in full (generated `messages.g.dart` scanned) | deep-reader H |
| `bluey_ios/lib` (Dart adapter) | in full (generated scanned) | deep-reader I |
| `bluey_android` native Kotlin (11 hand-written files) | in full (`Messages.g.kt` scanned) | deep-reader J + spot re-verify |
| `bluey_ios` native Swift (15 hand-written files) | in full (`Messages.g.swift` scanned) | deep-reader K + spot re-verify |
| Whole-graph Clean Architecture (imports, seam, gating, cycles) | full boundary sweep | deep-reader L + re-verify |
| Design-as-BLE-SDK + external field scan | public surface + web research | deep-reader M |
| `bluey/example/lib` | all logic-bearing files in full; pure-UI widgets skimmed | deep-reader N |
| `bluey/test` (100 files) | fakes read in full; 8–12 files deep-read; all enumerated + grep-swept | deep-reader O |

**Not covered (declared gaps):** Pigeon-generated files (`messages.g.*`) were confirmed unmodified, not audited. `bluey_ios` XCTest and `bluey_android` instrumentation tests were not executed (no simulator/device in the audit environment); Swift findings are static + cross-checked against the Pigeon contract. `hosted_gatt.dart` (75 % cov) was noted but not deep-read for test coverage. No production source file in scope was left unowned.
