# Networking-Scenario Test Audit — 2026-07-10

## Preamble

**Scope.** Every test suite in the monorepo — `bluey/test/` (98 Dart test files, ~31k lines, incl. `fakes/`), `bluey_platform_interface/test/` (6 files), `bluey_android/test/` (5 files), `bluey_ios/test/` (5 files), the Android native Kotlin suite (12 files, ~3.9k lines), and the iOS native Swift suite (10 files, ~1.4k lines) — judged against a single question: **how well can this codebase simulate and test different networking scenarios** (disconnects, connect failures, timeouts, latency, packet loss, flaky links, backpressure, adapter transitions, concurrency/races)?

**Rubric (explicit, this is a domain-specific audit).** A BLE library's test harness should be able to express, deterministically and in virtual time:
1. Connect-phase outcomes: success, failure (incl. status codes 133/8/19), timeout, cancellation.
2. Established-link faults: idle disconnect, disconnect racing an in-flight op, silent link loss.
3. Per-operation faults: read/write/subscribe/discover errors, timeouts, typed status failures — targetable per device/characteristic, and scriptable (fail N times, then succeed).
4. Transport conditions: latency, packet/notification loss, out-of-order and duplicate events, MTU negotiation outcomes (including negotiate-down and failure), flow-control backpressure.
5. Environment transitions: adapter off/on mid-scan/mid-connect/mid-op, permission revocation, scan and advertising failures.
6. Both roles end-to-end: client-side and server-side of the same scenario, ideally against each other.

**Method.** Three deep-read agents by territory (bluey Dart suite + fakes; native Kotlin/Swift + platform-package Dart suites; production failure-path inventory + docs sweep). I read `fake_platform.dart` (2,017 lines) in full myself, and personally re-verified every load-bearing claim against source (citations spot-checked at every seam: fake seams, integration-test bypasses, real sleeps, Kotlin connect-timeout handling, Swift CB-double absence, never-constructed exceptions). The `bluey` Dart gate was run as part of this audit. Native gates (Gradle JVM tests, XCTest) were **not** run — see Coverage.

**Baseline.** The 2026-07-07 full-stack audit (`docs/reviews/2026-07-07-full-stack-audit.md`, DA-## findings) already owns several adjacent findings. Where a DA finding covers the ground, this report references it rather than re-owning it.

Finding IDs here: **NT-#** (networking-test audit, first of its kind).

---

## Verdict

**Where you stand: strong bones, uneven reach.** This is one of the better-equipped BLE test harnesses I've seen at this size — 543+ Dart tests driven by a genuinely platform-faithful `FakeBlueyPlatform` (typed one-shot fault seams, held in-flight operations, handle-invalidation fidelity, the empirically-honest iOS silent-link-loss model), disciplined `fakeAsync` virtual time for all lifecycle/heartbeat timers, a Kotlin native suite that captures the real `BluetoothGattCallback` and drives arbitrary event sequences deterministically, and a Swift suite with a clean virtual clock and the sharpest late/duplicate-callback modeling in the repo.

But the reach is uneven in a specific, fixable way: **the harness is excellent at simulating faults on an established link, and nearly blind before the link exists and below the operation level.** You cannot make a connect fail or time out for a known device — on any layer, in any language. You cannot inject latency, so nothing ever truly interleaves; the "concurrent operations" integration tests bypass the domain API and prove nothing about the library. You cannot make MTU negotiation fail or negotiate down, cannot fail a scan, cannot script a flaky link ("fail twice, then succeed"), and the fake's server role never actually delivers notifications to its own client role, so no end-to-end dual-role scenario exists. On iOS, the queues are unit-tested but the CoreBluetooth delegate wiring — where the I338/I339-class bugs actually lived — has no test coverage at all.

Count: **0 Critical, 3 Major, 7 Moderate, 4 Minor, 2 Observations.** No finding says existing tests are wrong; every Major is a scenario class the harness cannot currently express.

---

## Findings

### MAJOR

**NT-1 — Connect-phase failures cannot be simulated anywhere in the stack.**
- Fake: `connect()` succeeds instantly and unconditionally for any registered peripheral (`bluey/test/fakes/fake_platform.dart:958-984`); it throws only for an *unknown* device (`:960-963`). `lastConnectConfig.timeout` is captured (`:296, :959`) but never enforced. There is no `simulateConnectFailure`, no `simulateConnectTimeout`, no held-connect, and no intermediate `connecting` state.
- Android native: a connect-timeout runnable is scheduled when `timeoutMs` is set and its *cancellation* is tested (`ConnectionManagerLifecycleTest.kt`, I061 test), but no test **fires** it to assert the timeout outcome; no test drives `onConnectionStateChange(status=133/8/19, STATE_DISCONNECTED)` during a pending connect. `0x85` appears in the Kotlin suite only as a notify status (`GattServerNotifyCompletionTest.kt:252`).
- iOS: untestable end-to-end (see NT-3).
- Production compounding: `ConnectionException` with its six `ConnectionFailureReason`s is defined but **never constructed** (`bluey/lib/src/shared/exceptions.dart:62`; verified — sole reference is its own definition; already owned as audit DA-21), so even if the fake could fail a connect, the domain has no typed path to surface it.
- Consequence: the single most common real-world BLE networking scenario — a connection attempt that doesn't succeed — has zero test expression. `Bluey.connect` failure handling, `PeerDiscovery` probe-failure skipping (`peer_discovery.dart:85-93`), and every consumer retry pattern are untestable against realistic outcomes.
- Fix direction: add connect-phase seams to `FakeBlueyPlatform` (fail with reason / timeout honoring `lastConnectConfig.timeout` under `fakeAsync` / held-connect mirroring the existing `holdNext*` pattern); fire the Kotlin connect-timeout runnable and drive connect-status events in `ConnectionManagerLifecycleTest`; wire `ConnectionFailureReason` construction (that half belongs to DA-21).

**NT-2 — No latency model, so no test can create genuine interleaving; the "concurrent operations" integration suite tests the fake, not the library.**
- Every fake operation resolves synchronously (or is manually held); there is no delay/latency knob anywhere in `fake_platform.dart`. Without an await-point window, domain-level operations cannot interleave, so races are structurally unreachable from the public API.
- Direct consequence, verified: `integration/concurrent_operations_test.dart` "reads from multiple characteristics in parallel" calls `fakePlatform.readCharacteristicByUuid(...)` inside `Future.wait` — bypassing `Bluey`/`Connection` entirely; same for parallel writes. These assert the fake's map semantics, not library behavior. (The SUT-bypass pattern generally is audit DA-39; the *cause* — no latency to make real API-level concurrency meaningful — is this finding.)
- The only genuine mid-op race tests exist where the held-op seams are used (`connection/bluey_connection_disconnect_test.dart:47` disconnect-races-held-write, I074; held reads in `lifecycle_client_test.dart`) — the pattern works, it's just not deployable at scale because "hold" targets only *the next* op globally.
- Fix direction: a per-op latency knob (`Duration`, scheduled via `Timer` so `fakeAsync.elapse` controls it) plus per-device/per-op fault targeting (see NT-5); then rewrite the concurrent-operations integration tests through the public API.

**NT-3 — iOS native wiring (CoreBluetooth delegate sequences) has no test coverage; only the extracted components do.**
- The Swift suite tests building blocks in isolation — `OpSlot`, `PendingWriteQueue`, `PendingNotificationQueue`, handle stores, error mappers — with a clean virtual clock (`OpSlotTests.swift:6-35`). But there is no double for `CBCentralManager`/`CBPeripheralManager`; the tests state CB types "cannot be instantiated by client code" and that wiring "is exercised separately at integration level" (`CentralManagerHandleTests.swift:8-16`) — an integration level that does not exist.
- So: `didDisconnectPeripheral` draining, `centralManagerDidUpdateState(.poweredOff)`, `peripheralIsReady(toSendWriteWithoutResponse:)` actually reopening the write gate, subscribe/unsubscribe fan-in — none of it is driven by any test. These seams are exactly where the recent high-severity bugs lived (I338 Pattern B, I339 flow control — both found on-device, not by tests). The 2026-07-07 audit additionally notes XCTest wasn't runnable in its gate environment, making Swift findings static-only.
- Consequence: the platform with the most empirically flaky behavior has the least behavioral test coverage; regressions in delegate wiring will keep being discovered on hardware.
- Fix direction: introduce thin protocol wrappers over `CBCentralManager`/`CBPeripheralManager` (the same seam pattern `FakeTimerFactory` and `FakeBlueyFlutterApi` already establish) so `CentralManagerImpl`/`PeripheralManagerImpl` can be driven by synthetic delegate sequences — the Swift equivalent of the Kotlin captured-callback harness. Get XCTest into the routine gate.

### MODERATE

**NT-4 — Adapter-off mid-operation is never driven as a transport event.** `setBluetoothState(off)` only emits a state event (`fake_platform.dart:529-534`); it does not tear down live connections, fail an in-flight connect/scan, or drain pending ops — so domain *reaction to the event* is tested, transport-level teardown is not. Natively, adapter-unavailable exists only as a pre-thrown `PlatformException` in the Dart translation tests (`android_connection_manager_test.dart:884-933`, iOS equivalent); no Kotlin test drives `STATE_OFF`, no Swift test can drive `.poweredOff` (NT-3). Related open backlog: I083 (iOS power-off doesn't clear server state). Fix direction: make the fake's `off` transition optionally cascade (drop connections with `linkLoss`, error in-flight ops), and add native adapter-transition tests.

**NT-5 — Fault injection is global and boolean; no per-device/per-characteristic targeting, no scripting, no flakiness.** The write/read seams are single global flags or one-shots on the whole fake (`simulateWriteTimeout` `fake_platform.dart:380`, `simulateWriteFailure` `:373`, `simulateReadError` `:524`, etc.). Multi-peer scenarios can't fault one device; "fail 2 times then succeed" requires manual flag-flipping between attempts; persistent booleans leak across a shared fake if a reset is forgotten. Fix direction: a small fault-rule queue — `enqueueFault({op, deviceId?, characteristicUuid?, error, times})` — subsuming the existing flags (keep them as sugar).

**NT-6 — The fake's two roles aren't wired to each other: server notify/indicate delivers nothing.** `notifyCharacteristic`/`indicateCharacteristic`/`...To` are no-ops whose bodies say "In a real implementation, this would send over BLE" (`fake_platform.dart:1678-1745`). Client-side notifications must be hand-injected via `simulateNotification` (`:812-825`). Consequence: no true end-to-end dual-role test (our server ↔ our client) exists, though the fake's doc header advertises exactly that ("simulates both central and peripheral roles... allowing integration tests to verify client-server interactions", `:9-13`); also means notification *loss* and *ordering* scenarios are trivially expressible but delivery correctness itself is untested. Fix direction: loop server sends back into the subscribed central connection's notification stream; then lifecycle/presence tests can run against the real protocol both ways.

**NT-7 — MTU negotiation outcomes cannot fail or negotiate down.** Fake `requestMtu` echoes the request (`fake_platform.dart:1391-1398`); native `onMtuChanged` is asserted only "does not throw" (`android_connection_manager_test.dart:320-345`, `ios_connection_manager_test.dart:251-260`). Ties to open I004/I024/I326 (MTU-change propagation) — when those land, tests will need a negotiate-down seam that doesn't exist. Fix direction: `simulateMtuResult(deviceId, {negotiated, error})`.

**NT-8 — Scan failures cannot be simulated.** Fake `scan()` never errors (`fake_platform.dart:927-950`); `onScanComplete` natively asserted only "does not throw" (`android_scanner_test.dart:119-123`). This is the test-side twin of open backlog **I013** (Android scan-failure codes discarded in production) — fixing I013 without a `simulateScanFailure` seam will land untested. Fix direction: add the seam alongside the I013 fix.

**NT-9 — Real wall-clock time in ~35 test sites (already owned as DA-37; still open, re-verified).** `scanner_test.dart` gates on real 50–150 ms sleeps at 8 sites (`:51,:132,:156,:161,:208,:234,:256,:281`); `bluey_server_test.dart` ~20× 10 ms; `bluey_connection_disconnect_test.dart:43` real 100 ms settle + 3 s wall-clock bound; zero `fakeAsync` usage in `integration/` (verified: 0 files). Violates the project's own simulate-time rule. Referenced, not re-owned.

**NT-10 — Flow-control backpressure is modeled natively but not in the Dart fake.** iOS queues have excellent contract tests (gate-shut/reopen, cap-full, `failAll` — `PendingWriteQueueTests.swift:52-121`, `PendingNotificationQueueTests.swift:80-227`), but the Dart fake's write-without-response never blocks, so domain-level behavior under a saturated link (what does `writeCharacteristic(withResponse: false)` feel like when the native queue is full?) is untestable. Android server notify has no backpressure/serialization test (production gap = audit DA-15). Fix direction: a fake write-queue depth with held drains, reusing the `holdNext*` machinery.

### MINOR

**NT-11 — Bonding failure outcomes unsimulatable.** `bond()` is capability-gated or unconditional no-op success (`fake_platform.dart:1477-1481`); no bond-rejected/auth-failed/bond-removed path. Graded Minor because Android bonding is itself an unimplemented stub (open I030/I035) — the hazard isn't live until that lands.

**NT-12 — Advertising failure is a single generic `StateError`.** `advertisingShouldFail` (`fake_platform.dart:1659-1669`) covers the rollback path but no typed `AdvertisingFailureReason`s; only `dataTooBig` is wired in translation. Twin of open I319.

**NT-13 — Persistent-boolean seams are leak-prone.** Every `simulateWrite*` call site must pair set/reset manually; a forgotten reset bleeds into later tests sharing the fake. Subsumed by NT-5's fix.

**NT-14 — Heavy fixture duplication despite good helpers.** The same ~20-line heart-rate `PlatformService` literal is copy-pasted dozens of times across `integration/` while `TestServiceBuilder`/`TestUuids`/`TestProperties` (`test_helpers.dart:169-253`) sit under-used. Maintenance drag only.

### OBSERVATIONS

**NT-15 — Several failure paths are plumbed-but-inert in production, so tests *cannot* cover them yet:** `ConnectionException`/`GattException` never constructed, user-op accounting never engaged in production, 4 of the `BlueyEvent` types never emitted (all owned by DA-20/21/22). Any new networking-scenario tests should assert on `logEvents` / `ConnectionState`, not `bluey.events`, until DA-22 is resolved.

**NT-16 — `Future.delayed(Duration.zero)` is the pervasive event-pump idiom in `integration/`.** Works today; brittle if the domain layer ever adds an await hop. `pumpEventQueue()` or expectation-based waits would be sturdier. Not worth a sweep on its own; adopt in new tests.

---

## What is genuinely healthy (verified — protect these)

- **The held-operation seams** (`holdNextRead/Write/AddService` + two-slot resolve/fail design, `fake_platform.dart:399-479, 1577-1596`) — a correct, elegant in-flight-op model that already proves the disconnect-races-write case (I074). NT-1/NT-2's fixes should extend this pattern, not replace it.
- **`fakeAsync` discipline for all timer-driven logic** — 12 files, ~200 `elapse` sites across lifecycle client/server, silence monitor, peer tests; `fireLifecycleSilence` (`fake_platform.dart:697-718`) is purpose-built to pair with virtual time.
- **Platform-fidelity of the fake where it counts**: tree-position handle minting, `_clearHandles` on disconnect/Service-Changed (`:1059-1147`) making handle-invalidation tests meaningful; `simulateSilentLinkLoss` (`:730`) and `reportsCentralDisconnects` (`:45-69`) encoding the *empirical* iOS quirk rather than idealized behavior; capability gating via `UnimplementedError` (`:1456-1567`).
- **The Kotlin captured-callback harness** — capturing the real `BluetoothGattCallback` from mockk'd `connectGatt` and firing synthetic event sequences, with `postDelayed` runnables captured and fired manually as a virtual clock. Deterministic disconnect-drain, 5 s-fallback, late/stray-callback, and mid-fanout concurrency tests all ride on it. This is the model NT-1/NT-4's native work should extend, and the template NT-3 should port to Swift.
- **Swift `OpSlotTests` `pendingDrops`** — the sharpest late/duplicate-native-callback treatment in the repo — plus `FakeTimerFactory` (fully virtual time, zero `XCTestExpectation` sleeps) and the backpressure queue contract tests.
- **Error-translation matrices on every layer** (Dart per-op loops, Kotlin `ErrorsTest`, Swift `CBErrorPigeonTests` with forward-compat unknown-code preservation; the "don't spuriously re-translate `gatt-status-failed`" guard in `ios_server_respond_test.dart:114-145`).
- **Call-recording lists** carrying both wire handle and resolved UUID (`fake_platform.dart:343-368`) — strong order/argument assertions without handle bookkeeping in tests.

## Adjusted / discarded claims

- Agent claims were broadly accurate; all spot-checked citations existed and matched. Adjustments made:
  - "Mid-operation disconnect coverage" was initially presented as a capability class; adjudicated down to "one narrow genuine race test (I074) plus lifecycle-internal uses" — reflected in NT-2.
  - The finder suggested High severity for adapter-off and MTU gaps; re-graded Moderate on the ladder (structural gaps, not live defects — the domain-layer *reaction* to state events is tested).
  - Fixture duplication and the `Duration.zero` pump were suggested medium; re-graded Minor/Observation (maintenance drag, no correctness impact today).
  - Claims overlapping the 2026-07-07 audit (SUT-bypass = DA-39, real sleeps = DA-37, inert exceptions/events = DA-20/21/22, hand-rolled mocks = DA-38) were excluded or referenced rather than re-owned.
- No fabricated citations found.

## Recommendations

| ID | What | Findings | Effort |
|---|---|---|---|
| R1 | Connect-phase fault seams in the fake (fail/timeout/held-connect) + fire Kotlin connect-timeout & connect-status events; pairs with wiring `ConnectionFailureReason` (DA-21) | NT-1 | M |
| R2 | Fault-rule queue in the fake: per-device/per-char targeting, fail-N-then-succeed, subsumes boolean flags | NT-5, NT-13 | M |
| R3 | Latency knob (Timer-based, `fakeAsync`-driven) + rewrite concurrent-operations tests through the public API | NT-2 | M |
| R4 | Loop server notify/indicate back to client-side streams in the fake (true dual-role E2E) | NT-6 | S–M |
| R5 | Swift delegate-seam wrappers for `CBCentralManager`/`CBPeripheralManager` + first delegate-sequence tests; XCTest in the routine gate | NT-3 | L |
| R6 | Adapter-off cascade in the fake + native adapter-transition tests | NT-4 | S–M |
| R7 | MTU negotiate-down/failure seam; scan-failure seam (land with I013) | NT-7, NT-8 | S |
| R8 | Migrate real-sleep tests to `fakeAsync` (executes DA-37) | NT-9 | M |
| R9 | Fake write-queue depth for backpressure scenarios | NT-10 | M |

**Suggested order: R1 → R2 → R3 → R4, then R5, then the rest.** R1 unlocks the biggest blind spot (pre-link failures) cheaply; R2/R3 turn the existing seams into a general scenario-scripting harness; R4 makes the peer/lifecycle protocol testable end-to-end both ways; R5 is the largest but addresses the platform where bugs have historically escaped to hardware.

---

## Addendum (2026-07-10): additional scenario classes

Added after the initial report, sourced from the project's own quirk record (`bluey/docs/cross-platform-quirks.md`, `bluey_android/ANDROID_BLE_NOTES.md`, `bluey_ios/IOS_BLE_NOTES.md`) cross-referenced against the harness capabilities above. Owner has approved addressing **all** of these; the three modeling items are tracked as backlog I346–I348 and sequenced after R1–R9 + the A-scenarios below.

### A. Expressible with today's fake — missing only tests (fold into R10)

1. **Peer address rotation.** iOS mints a random address per connection (IOS notes, limitation 9) — the reason `ServerId` exists. Peer at address X drops, same `ServerId` re-advertises at address Y: `discoverPeers`/dedup must resolve it as the same peer; server side must tolerate the stale entry for X. Expressible now via `simulateBlueyServer` at a new address + `removePeripheral`.
2. **ServerId changes under a stable address** (peer app restarted, fresh identity mid-session). `PeerIdentityMismatchException` is defined but never constructed (NT-15 family) — decide the intended behavior, then pin it.
3. **Late-heartbeat boundary race** — heartbeat arriving just after vs. just before the silence timer fires at exactly `lifecycleInterval`. Pure `fakeAsync`; seams exist (`fireLifecycleSilence` + `elapse`).
4. **Hostile/buggy peer inputs:** interval characteristic of 0/negative (DA-10 busy-loop hazard), malformed lifecycle payloads, unsupported protocol version, non-Bluey central writing garbage to control characteristics or subscribe/unsubscribe-flapping the presence characteristic. Log-and-drop is the claimed behavior; largely unpinned.
5. **Duplicate-UUID notification cross-delivery** (DA-02 hazard): notifications demux by UUID string, not handle — two same-UUID characteristics is a live wrong-stream scenario expressible via `simulateNotification`.

### B. Unlocked by R1/R2 seams (fold into R11)

6. **Remote peer force-kill sequence** (Android notes): no callbacks, ops time out for 20–30 s, *then* link loss — a canned scripted sequence (write-timeouts → disconnect) for the R2 fault-rule queue.
7. **Connection-limit reached / connect flapping under failure** — needs R1's connect-phase seams (`ConnectionFailureReason.connectionLimitReached`).
8. **512-byte cap / silent truncation regression in the fake** (I343/I344): "platform over-reports max, peripheral truncates silently" as a fast unit regression complementing the on-device stress harness.

### C. New fake-platform modeling (backlog I346–I348)

9. **iOS shared-LL-link trap** (`cross-platform-quirks.md` §1): disconnecting an outgoing handle to a peer that is already our client tears down the one shared physical link, including the documented 6-step reconnect loop and the recommended address-dedup pattern. Requires linking the fake's two roles (extends R4). → **I346**.
10. **Android role-reversal ATT blackhole** (§2, I208): server-side requests silently never arrive while the connection looks healthy; tests should prove heartbeat failures accumulate into dead-peer teardown. → **I347**.
11. **Inherited/ghost centrals pre-advertising** (Android notes, iOS connection caching): real platforms deliver centrals before advertising starts, but the fake *forbids* it — `simulateCentralConnection` throws `StateError` when not advertising (`fake_platform.dart:663-665`), a fidelity bug encoding a false invariant. → **I348**.

### Recommendations (addendum)

| ID | What | Scenarios | Effort |
|---|---|---|---|
| R10 | Scenario tests expressible today: address rotation, ServerId change (decide behavior first), heartbeat boundary race, hostile peer inputs, duplicate-UUID cross-delivery | A.1–A.5 | M |
| R11 | Canned scripted sequences on top of R1/R2: force-kill profile, connection-limit/flapping, 512-cap truncation | B.6–B.8 | S–M |
| R12 | Fake-platform modeling work | C.9–C.11 → backlog [I346](../backlog/I346-fake-platform-shared-link-trap-model.md), [I347](../backlog/I347-fake-platform-role-reversal-att-blackhole.md), [I348](../backlog/I348-fake-platform-inherited-central-before-advertising.md) | L |

**Revised order:** R1 → R2 → R3 → R4 → R10 → R11 → R5 → R6–R9 → R12 (I346–I348 last, per owner's sequencing; I346 depends on R4's loopback).

### Progress

- **R1 — done** (2026-07-10, merge `b06f304`): `PlatformConnectFailedException` + reason enum in the platform interface; ACL maps it to `ConnectionException` (first `ConnectionFailureReason` construction — half of DA-21); both adapters translate connect-phase codes positionally; fake gains `simulateConnectFailure` (per-device, one-shot), `holdNextConnect`/`resolveHeldConnect`/`failHeldConnect`, and held-connect timeout enforcement under `fakeAsync`; Kotlin pins the fired connect-timeout runnable (typed `ConnectionTimeout`, late `STATE_CONNECTED` no-op) and mid-connect status 133.

## Coverage

- `bluey/test/fakes/fake_platform.dart` — read in full by the orchestrator (2,017 lines) *and* by agent 1.
- `bluey/test/` (98 files) — agent 1 (fakes and integration read closely; unit-test fault-seam call sites enumerated via search); orchestrator re-verified 5 load-bearing claims in source.
- `bluey_platform_interface/test/`, `bluey_android/test/`, `bluey_ios/test/`, Kotlin suite (12 files), Swift suite (10 files) — agent 2, read in full; orchestrator re-verified 4 load-bearing claims.
- Production failure surface (`bluey/lib/src/`, `bluey_platform_interface/lib/src/` in full; native skimmed) + `docs/roadmap.md`, `docs/backlog/`, `docs/reviews/` — agent 3; orchestrator re-verified 4 claims.
- Gates: `cd bluey && flutter test` run by the orchestrator during this audit (result recorded below). **Not run:** Android Gradle JVM tests and iOS XCTest (heavyweight toolchain runs; their *content* was read in full, their pass/fail state is asserted by CI history only). `flutter analyze` not run (out of rubric).
- Not covered: `bluey/example/` app code (incl. `StressTestRunner`) beyond backlog references — it is a manual on-device harness, not part of the automated suites.

**Gate result:** `flutter test` in `bluey/`: **1017 tests, all passed** (22 s, run 2026-07-10).
