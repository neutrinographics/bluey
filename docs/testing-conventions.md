# Testing conventions

Hard-won rules for writing tests in this repo. The fixtures themselves
are documented in their own doc comments (`bluey/test/fakes/`); this
page records the rules and gotchas that aren't visible from any one
file.

## Simulate time — never wait it out

Any test that involves a timeout, interval, or delay runs under
`fakeAsync` and advances virtual time with `async.elapse(...)`. Tests
must never sleep the wall clock: no `Future.delayed` with a non-zero
duration anywhere in `bluey/test` (enforced by review; the last 100+
were removed in audit R8 / DA-37).

- **Timer-driven logic** (lifecycle heartbeats, silence timeouts, scan
  windows, `operationLatency`, connect timeouts): `fakeAsync` +
  `elapse`. Boot pattern: create the fake and call `Bluey.create()`
  inside the `fakeAsync` body via `.then(...)` + `flushMicrotasks()`.
- **Event propagation** (waiting for a stream event to land, a
  broadcast emission to deliver): `await pumpEventQueue();` — never a
  timed sleep "long enough for it to arrive".
- Failure *bounds* that only fire on regression (e.g. a 3 s `.timeout`
  guarding against a deadlock) are acceptable: they cost nothing when
  the code is correct.

## The fakeAsync escape trap: never `await` a broadcast cancel

`StreamSubscription.cancel()` on a broadcast subscription with no
`onCancel` handler returns Dart's root-zone null-future singleton.
`await`ing it registers the continuation on the **real** event loop —
outside the fakeAsync zone — so the awaiting code parks until the test
ends, no matter how much virtual time you elapse. The symptom is an
inexplicable hang exactly at an `await sub.cancel();` line.

Rule: in code that must work under `fakeAsync` (production or test),
don't await broadcast-subscription cancels — `unawaited(sub.cancel())`
and rely on an explicit stop call (e.g. `stopScan`) for authoritative
teardown. Found the hard way in I349; see
`bluey/lib/src/peer/peer_discovery.dart` for the in-tree example.

## Fixtures: FakeBlueyPlatform, not mocks

`FakeBlueyPlatform` (`bluey/test/fakes/fake_platform.dart`) is the
mandated test double (CLAUDE.md); hand-rolled `MockBlueyPlatform`
classes drift (audit DA-38). The scenario surface, briefly:

- **Fault injection**: `enqueueFault(op, error, {deviceId,
  characteristicUuid, times})` — FIFO rules, per-device/characteristic
  targeting, fail-N-then-succeed, `times: null` persistent,
  `clearFaults()`. The `simulateWrite*` booleans and
  `simulateConnectFailure` are sugar for common one-liners.
- **Latency / interleaving**: `operationLatency` (requires `fakeAsync`).
- **In-flight control**: `holdNextRead/Write/Connect/AddService` +
  `resolve*`/`fail*`.
- **Transport events**: `simulateDisconnection`, `simulateServiceChange`,
  `setBluetoothState` (+ `cascadeAdapterTeardown`),
  `simulateScanFailure`, `simulateMtuNegotiationCap`,
  `setWriteWithoutResponseBudget`/`drainPendingWrites`,
  `simulateServerRequestBlackhole`.
- **Dual-role end-to-end**: `FakeBleLink` cross-wires two fakes so two
  real `Bluey` endpoints exchange real traffic; `shareOnePhysicalLink`
  adds the iOS one-link-per-peer-pair topology. Known limits are listed
  in backlog I352.
- **Assertion seams**: recorded-call lists (`writeCharacteristicCalls`,
  `serverNotifyCalls`, ...) carry both wire handle and resolved UUID —
  prefer asserting on them over `expect(true, isTrue)`-style "didn't
  throw" tests.

## Which gate to run

Dart: `flutter test` per package. Android native: Gradle (see
CLAUDE.md). iOS native: XCTest via xcodebuild (see CLAUDE.md; the
scheme's eligible simulator list is constrained — check
`xcodebuild -showdestinations` when the destination errors). There is
no CI yet (backlog I351) — run the native gates manually when touching
Kotlin/Swift.
