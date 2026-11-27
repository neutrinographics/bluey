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
- **Scan results**: `simulateScanResult`, `simulateScanRefusal`,
  `holdNextStopScan`. The scan stream is synchronous, so a result heard just
  before a replacing scan is delivered; a real platform may lose it, which the
  fake cannot exercise.
- **Dual-role end-to-end**: `FakeBleLink` cross-wires two fakes so two
  real `Bluey` endpoints exchange real traffic; `shareOnePhysicalLink`
  adds the iOS one-link-per-peer-pair topology. Known limits are listed
  in backlog I352.
- **Assertion seams**: recorded-call lists (`writeCharacteristicCalls`,
  `serverNotifyCalls`, ...) carry both wire handle and resolved UUID —
  prefer asserting on them over `expect(true, isTrue)`-style "didn't
  throw" tests.

## Where a test lives

A test file mirrors its source file's path, so the test of a file is
found without searching: `lib/src/features/connection/domain/link_state.dart`
is tested by `test/features/connection/domain/link_state_test.dart`. An
existing test moves with its source, in the slice that moves it. In-memory
doubles of a port live in `test/fixtures/` under the same tree.

## How a test is laid out

A `group` names the scenario, and each test inside it is laid out with
`// arrange`, `// act` and `// assert`. Leave a phase comment out only
when that phase has no statement.

```dart
group('a scan that is restarted', () {
  test('delivers the second scan\'s results', () async {
    // arrange
    ...
    // act
    ...
    // assert
    ...
  });
});
```

## Known defects

A known defect is a test that reproduces an audit finding and fails until
the slice that owns it fixes the bug. The files live in
`test/known_defects/` (in `bluey` and `bluey_android`) and open with
`@Tags(['known-defect'])`. Each package's `dart_test.yaml` gives the tag a
skip reason, so a normal `flutter test` shows each file as one skipped suite.
Run them on purpose with:

```bash
cd bluey && flutter test test/known_defects --run-skipped --tags known-defect
```

They are expected to fail. CI's Known defects job fails when one passes or
stops running. A fix slice starts by moving its test out of the known-defect
file into the mirrored tree, where it fails: that is its red step. The move
and the fix land in one commit. `docs/ARCHITECTURE.md` (section 9) has the
whole rule.

## Which gate to run

CI runs all of these: every pull request runs `.github/workflows/ci.yml`,
and XCTest runs from `ios.yml`. `docs/ARCHITECTURE.md` (section 10) lists
each gate with its CI job. Locally:

- **Dart:** `flutter test` per package; `dart test` in `bluey_guards`.
- **Architecture:** `flutter test test/architecture` in a package. A failure
  names what is new and what is stale on its list; `docs/ARCHITECTURE.md`
  (section 5) says what to do with each.
- **Public API:** `cd bluey && dart run bluey_guards:public_api lib/bluey.dart
  api/bluey.api`. Add `--write` after a change that was meant, and review the
  dump's diff as an API change.
- **Coverage floor:** `cd bluey && flutter test --coverage && dart run
  bluey_guards:coverage_gate coverage/lcov.info 90`.
- **Known defects:** the command above, or the job's JSON form and verdict in
  `docs/ARCHITECTURE.md` (section 10).
- **Android native:** Gradle (see CLAUDE.md; create the wrapper once per
  checkout).
- **iOS native:** XCTest via xcodebuild (see CLAUDE.md; the scheme's eligible
  simulator list is constrained — check `xcodebuild -showdestinations` when
  the destination errors). CI runs it only for pull requests that touch
  `bluey_ios/`, and nightly, so run it yourself when touching Swift.
