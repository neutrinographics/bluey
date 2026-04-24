# Lifecycle Client Guards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `LifecycleClient` transactional and self-consistent — late promise callbacks after `stop()` must be no-ops, `start()` must be idempotent and unwind fully on failure, and activity signals during the `start()` → interval-read window must not be dropped. Fixes I070 + I073 + I078.

**Architecture:** Introduce a single authoritative `_isRunning` flag. Set it at the commit point inside `start()` (after pre-commit null checks pass), clear it at the top of `stop()`, check it in every promise callback, and wrap the post-commit section of `start()` in a try/catch that calls `stop()` and rethrows on synchronous failure. Keep `_heartbeatCharUuid` as a separate narrow-purpose field (the char UUID we write heartbeats to).

**Tech Stack:** Dart 3, Flutter test framework, `FakeAsync` from the `fake_async` package for deterministic time, `FakeBlueyPlatform` from `bluey/test/fakes/fake_platform.dart` for platform simulation.

**Spec reference:** `docs/superpowers/specs/2026-04-24-lifecycle-client-guards-design.md`.

---

## File structure

Only two files change. One new test helper method is added to `FakeBlueyPlatform`.

| Path | Responsibility | Change |
|---|---|---|
| `bluey/lib/src/connection/lifecycle_client.dart` | Domain — client-side lifecycle / heartbeat scheduler | Modify: add `_isRunning`, guards, transactional `start()`, `stop()` monitor cleanup |
| `bluey/test/connection/lifecycle_client_test.dart` | Tests for the above | Modify: add tests for each of the seven behaviours below |
| `bluey/test/fakes/fake_platform.dart` | In-memory platform fake | Modify: add `holdNextReadCharacteristic`/`resolveHeldRead`, `holdNextWriteCharacteristic`/`resolveHeldWrite`/`failHeldWrite`, and `simulateSyncWriteThrow` |

No Pigeon files, no native sources, no platform-interface changes.

---

## Starting context

Read these before starting:

- `docs/superpowers/specs/2026-04-24-lifecycle-client-guards-design.md` — the approved design.
- `docs/backlog/I070-lifecycle-client-late-promise-callbacks.md`, `I073-lifecycle-client-start-not-idempotent.md`, `I078-lifecycle-client-activity-drop-during-start.md` — the three bugs being fixed.
- `bluey/lib/src/connection/lifecycle_client.dart` — the file being modified. ~265 lines, one class.
- `bluey/lib/src/connection/liveness_monitor.dart` — unchanged, but the client delegates policy to it. You need to know its API: `recordActivity()`, `timeUntilNextProbe()`, `markProbeInFlight()`, `recordProbeSuccess()`, `recordProbeFailure()`, `cancelProbe()`, `probeInFlight`, `activityWindow`, `updateActivityWindow()`.
- `bluey/test/connection/lifecycle_client_test.dart` — existing test file. The helper `_setUpConnectedClient(...)` at the top is the fixture you'll reuse. Tests use `FakeAsync` blocks with `fake.flushMicrotasks()` / `async.elapse(...)`.
- `CLAUDE.md` — project mandates DDD + Clean Architecture + TDD (Red-Green-Refactor). Coverage targets: 90% domain.

Run tests from `bluey/`:
```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

---

## Task 1: Add `_isRunning` field and make `start()` idempotent (I073)

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Test: `bluey/test/connection/lifecycle_client_test.dart`

**Why this task:** The three bugs in this PR all share the same root cause — no authoritative "running" sentinel. This task lays the foundation: a `_isRunning` bool, an idempotency guard at the top of `start()`, and a corresponding clear in `stop()`. Subsequent tasks build on this field.

This task picks the simplest placement of `_isRunning = true` (at the top of `start()`'s body, before null checks). Task 6 later moves it past the null checks to make `start()` retryable after a pre-commit early return.

- [ ] **Step 1: Add the failing test for I073 — double `start()` is a no-op**

Append a new `test(...)` inside the existing `group('LifecycleClient', ...)` block in `bluey/test/connection/lifecycle_client_test.dart`. The test uses `FakeAsync` to hold the interval-read Pigeon round-trip, calls `start()` twice, then resolves the interval-read — it must see exactly one heartbeat dispatch, not two.

First, add a hold/release helper to `FakeBlueyPlatform` (in `bluey/test/fakes/fake_platform.dart`). Insert these fields and methods near the other simulate/hold helpers around line 90 (after the `simulateSetNotificationDisconnected` field):

```dart
  /// When non-null, the next call to [readCharacteristic] parks the
  /// future on this completer instead of resolving immediately.
  /// Clear with [resolveHeldRead] or [failHeldRead].
  Completer<Uint8List>? _heldRead;

  /// Arranges for the next [readCharacteristic] call to be held
  /// indefinitely. Call [resolveHeldRead] or [failHeldRead] to release it.
  void holdNextReadCharacteristic() {
    _heldRead = Completer<Uint8List>();
  }

  /// Resolves the currently-held read future with [value].
  void resolveHeldRead(Uint8List value) {
    final held = _heldRead;
    if (held == null) {
      throw StateError('No held readCharacteristic to resolve');
    }
    _heldRead = null;
    held.complete(value);
  }

  /// Fails the currently-held read future with [error].
  void failHeldRead(Object error) {
    final held = _heldRead;
    if (held == null) {
      throw StateError('No held readCharacteristic to fail');
    }
    _heldRead = null;
    held.completeError(error);
  }
```

Modify `readCharacteristic` at line ~516 to consult the held completer first. Insert at the top of the method body, before any of the existing `simulate*` checks:

```dart
    final held = _heldRead;
    if (held != null) {
      _heldRead = null;
      return held.future;
    }
```

Now add the test. Append inside `group('LifecycleClient', ...)` in `lifecycle_client_test.dart`:

```dart
    test('start() is idempotent — second call before interval-read resolves is a no-op', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        fakePlatform.holdNextReadCharacteristic();

        client.start(allServices: services!);
        async.flushMicrotasks();
        // First start dispatched the initial heartbeat write.
        final writesAfterFirst = fakePlatform.writeCharacteristicCalls.length;

        // Second start() before the interval-read resolves — must be a no-op.
        client.start(allServices: services!);
        async.flushMicrotasks();

        expect(fakePlatform.writeCharacteristicCalls.length, writesAfterFirst,
            reason: 'second start() must not dispatch another heartbeat write');
        expect(client.isRunning, isTrue);

        // Clean up the held future so fakeAsync doesn't complain.
        fakePlatform.resolveHeldRead(lifecycle.encodeInterval(const Duration(seconds: 10)));
        async.flushMicrotasks();
        client.stop();
      });
    });
```

- [ ] **Step 2: Run the test — expect failure**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "start() is idempotent"
```

Expected: FAIL. The second `start()` currently proceeds because there's no guard — the test should see either two writes (the two initial heartbeats) or a test-framework error from the fake's `writeCharacteristicCalls` not matching.

- [ ] **Step 3: Implement the `_isRunning` field and guard**

In `bluey/lib/src/connection/lifecycle_client.dart`:

Add the field under the existing `_heartbeatCharUuid` declaration around line 27:

```dart
  Timer? _probeTimer;
  String? _heartbeatCharUuid;
  /// Authoritative "running" sentinel. True from the moment `start()`
  /// commits to run (after its pre-commit null checks pass) until
  /// `stop()` clears it. Distinct from `_heartbeatCharUuid`, which
  /// indicates only "we know which char to write heartbeats to".
  bool _isRunning = false;
```

Replace the `isRunning` getter (currently at line 48):

```dart
  /// Whether the heartbeat client has committed to running and has
  /// not yet been stopped.
  bool get isRunning => _isRunning;
```

At the top of `start()` (currently line 68, the method body starts at line 69), replace the existing `if (_heartbeatCharUuid != null) return;` with:

```dart
  void start({required List<RemoteService> allServices}) {
    if (_isRunning) return;
    _isRunning = true;

    final controlService = allServices
```

At the top of `stop()` (currently line 138), add the clear as the first line:

```dart
  void stop() {
    _isRunning = false;
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
  }
```

- [ ] **Step 4: Run the test — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "start() is idempotent"
```

Expected: PASS. Also run the full lifecycle test file to catch regressions:

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
cd bluey/.. && git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart bluey/test/fakes/fake_platform.dart
git commit -m "feat(lifecycle): add _isRunning sentinel and start() idempotency (I073)"
```

---

## Task 2: `stop()` releases the monitor's in-flight probe flag

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Test: `bluey/test/connection/lifecycle_client_test.dart`
- Test helper: `bluey/test/fakes/fake_platform.dart`

**Why this task:** Task 5 of this plan will guard the `_sendProbe` completion callbacks with `if (!_isRunning) return;`. Those callbacks are responsible for clearing the monitor's `_probeInFlight` flag (via `recordProbeSuccess` / `recordProbeFailure` / `cancelProbe`). If the guard blocks them, the flag strands. `stop()` must release the flag synchronously so the monitor stays consistent.

- [ ] **Step 1: Add hold/release helpers for writes to `FakeBlueyPlatform`**

In `bluey/test/fakes/fake_platform.dart`, near the read helpers from Task 1 (~line 90):

```dart
  /// When non-null, the next call to [writeCharacteristic] parks the
  /// future on this completer instead of resolving immediately.
  Completer<void>? _heldWrite;

  /// Arranges for the next [writeCharacteristic] call to be held
  /// indefinitely. Call [resolveHeldWrite] or [failHeldWrite] to release it.
  void holdNextWriteCharacteristic() {
    _heldWrite = Completer<void>();
  }

  /// Resolves the currently-held write future successfully.
  void resolveHeldWrite() {
    final held = _heldWrite;
    if (held == null) {
      throw StateError('No held writeCharacteristic to resolve');
    }
    _heldWrite = null;
    held.complete();
  }

  /// Fails the currently-held write future with [error].
  void failHeldWrite(Object error) {
    final held = _heldWrite;
    if (held == null) {
      throw StateError('No held writeCharacteristic to fail');
    }
    _heldWrite = null;
    held.completeError(error);
  }
```

Modify `writeCharacteristic` at line ~558 to consult the held completer first. Insert at the top of the method body, before any of the existing `simulate*` checks:

```dart
    final held = _heldWrite;
    if (held != null) {
      _heldWrite = null;
      return held.future;
    }
```

- [ ] **Step 2: Add the failing test**

Append to `group('LifecycleClient', ...)` in `lifecycle_client_test.dart`:

```dart
    test('stop() releases in-flight probe so monitor does not strand probeInFlight', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        // Resolve the initial heartbeat and interval-read normally, so
        // we're in the steady state with a probe timer armed.
        client.start(allServices: services!);
        async.flushMicrotasks();

        // Now hold the next heartbeat write. Advance time to let the
        // probe timer fire and dispatch.
        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        // The probe is in flight. Call stop().
        client.stop();

        // Assert: probeInFlight is false even though the write future
        // has not resolved.
        expect(client.probeInFlightForTest, isFalse,
            reason: 'stop() must release the monitor in-flight flag');

        // Clean up the held future.
        fakePlatform.resolveHeldWrite();
        async.flushMicrotasks();
      });
    });
```

This test calls `client.probeInFlightForTest` which does not exist yet. Expose it as a test-only getter in `lifecycle_client.dart`:

```dart
  /// Exposed for tests: whether the internal monitor is currently
  /// tracking an in-flight probe. Not intended for production use.
  @visibleForTesting
  bool get probeInFlightForTest => _monitor.probeInFlight;
```

Add this import to `lifecycle_client.dart`:

```dart
import 'package:meta/meta.dart';
```

- [ ] **Step 3: Run the test — expect failure**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "stop() releases in-flight probe"
```

Expected: FAIL. After `stop()`, `_monitor.probeInFlight` is still `true` because the held write future hasn't resolved and nothing has called `cancelProbe()`.

- [ ] **Step 4: Implement the fix**

Update `stop()` in `lifecycle_client.dart`:

```dart
  void stop() {
    _isRunning = false;
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
    _monitor.cancelProbe();
  }
```

- [ ] **Step 5: Run the test — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "stop() releases in-flight probe"
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: the new test passes, all others still pass.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart bluey/test/fakes/fake_platform.dart
git commit -m "feat(lifecycle): stop() releases monitor in-flight probe flag"
```

---

## Task 3: I070 — guard `start()`'s interval-read callbacks after `stop()`

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Test: `bluey/test/connection/lifecycle_client_test.dart`

**Why this task:** `start()` dispatches `_platform.readCharacteristic(intervalChar)` and attaches `.then` / `.catchError` callbacks. If `stop()` runs while that Pigeon round-trip is pending, the late callback would call `_beginHeartbeat()` — arming a probe timer on a supposedly-dead client.

- [ ] **Step 1: Add the failing tests**

Append two tests to `lifecycle_client_test.dart`. Both use the hold/resolve mechanism from Task 1. The first covers the `.then` path (interval-read succeeds after stop). The second covers the `.catchError` path (interval-read fails after stop).

```dart
    test('I070: interval-read success after stop() is a no-op', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        fakePlatform.holdNextReadCharacteristic();
        client.start(allServices: services!);
        async.flushMicrotasks();

        // Capture the heartbeat write count before we stop.
        final writesBefore = fakePlatform.writeCharacteristicCalls.length;

        client.stop();
        async.flushMicrotasks();

        // Late interval-read arrives.
        fakePlatform.resolveHeldRead(lifecycle.encodeInterval(const Duration(seconds: 10)));
        async.flushMicrotasks();

        // Advance far enough that any armed timer would fire.
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(client.isRunning, isFalse);
        expect(fakePlatform.writeCharacteristicCalls.length, writesBefore,
            reason: 'no probe may dispatch after stop()');
      });
    });

    test('I070: interval-read failure after stop() is a no-op', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        fakePlatform.holdNextReadCharacteristic();
        client.start(allServices: services!);
        async.flushMicrotasks();

        final writesBefore = fakePlatform.writeCharacteristicCalls.length;

        client.stop();
        async.flushMicrotasks();

        fakePlatform.failHeldRead(Exception('simulated interval-read failure'));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(client.isRunning, isFalse);
        expect(fakePlatform.writeCharacteristicCalls.length, writesBefore);
      });
    });
```

- [ ] **Step 2: Run the tests — expect failure**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "I070: interval-read"
```

Expected: both fail. After `stop()`, the late interval-read callback calls `_beginHeartbeat` → schedules a probe → the 60-second elapse fires it → an extra write is dispatched.

- [ ] **Step 3: Add the guards**

In `start()` in `lifecycle_client.dart`, the interval-read block currently at lines 100-114 looks like:

```dart
    if (intervalChar != null) {
      _platform
          .readCharacteristic(_connectionId, intervalChar.uuid.toString())
          .then((bytes) {
        final serverInterval = lifecycle.decodeInterval(bytes);
        final heartbeatInterval = Duration(
          milliseconds: serverInterval.inMilliseconds ~/ 2,
        );
        _beginHeartbeat(heartbeatInterval);
      }).catchError((_) {
        _beginHeartbeat(_defaultHeartbeatInterval);
      });
    } else {
      _beginHeartbeat(_defaultHeartbeatInterval);
    }
```

Add `if (!_isRunning) return;` as the first line of each callback:

```dart
    if (intervalChar != null) {
      _platform
          .readCharacteristic(_connectionId, intervalChar.uuid.toString())
          .then((bytes) {
        if (!_isRunning) return;
        final serverInterval = lifecycle.decodeInterval(bytes);
        final heartbeatInterval = Duration(
          milliseconds: serverInterval.inMilliseconds ~/ 2,
        );
        _beginHeartbeat(heartbeatInterval);
      }).catchError((_) {
        if (!_isRunning) return;
        _beginHeartbeat(_defaultHeartbeatInterval);
      });
    } else {
      _beginHeartbeat(_defaultHeartbeatInterval);
    }
```

- [ ] **Step 4: Run the tests — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "I070: interval-read"
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: both new tests pass, everything else still passes.

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart
git commit -m "fix(lifecycle): guard interval-read callbacks against post-stop() mutation (I070)"
```

---

## Task 4: I070 — guard `_sendProbe`'s completion callbacks after `stop()`

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Test: `bluey/test/connection/lifecycle_client_test.dart`

**Why this task:** `_sendProbe` dispatches a heartbeat write and attaches `.then` (success) / `.catchError` (failure) callbacks. Both mutate the monitor and schedule follow-on work. Both must no-op when the client has been stopped — otherwise a late failure after `stop()` could invoke `onServerUnreachable()` on a connection the caller already tore down.

- [ ] **Step 1: Add the failing tests**

Append to `lifecycle_client_test.dart`. Three tests: probe-success after stop is no-op; probe-transient-failure after stop is no-op; probe-dead-peer-failure after stop does not invoke `onServerUnreachable`.

```dart
    test('I070: probe-write success after stop() does not reschedule', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services!);
        async.flushMicrotasks();

        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        final writesBefore = fakePlatform.writeCharacteristicCalls.length;

        client.stop();
        async.flushMicrotasks();

        fakePlatform.resolveHeldWrite();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(client.isRunning, isFalse);
        expect(fakePlatform.writeCharacteristicCalls.length, writesBefore,
            reason: 'no probe may be rescheduled after stop()');
      });
    });

    test('I070: probe-write transient failure after stop() does not reschedule', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services!);
        async.flushMicrotasks();

        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        final writesBefore = fakePlatform.writeCharacteristicCalls.length;

        client.stop();
        async.flushMicrotasks();

        // Transient (non-dead-peer) error — e.g. a platform-layer Exception.
        fakePlatform.failHeldWrite(Exception('transient platform error'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(client.isRunning, isFalse);
        expect(fakePlatform.writeCharacteristicCalls.length, writesBefore);
      });
    });

    test('I070: probe-write dead-peer failure after stop() does not fire onServerUnreachable', () {
      fakeAsync((async) {
        var unreachableCalls = 0;
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(
          onServerUnreachable: () => unreachableCalls++,
        ).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services!);
        async.flushMicrotasks();

        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        client.stop();
        async.flushMicrotasks();

        // Dead-peer signal: timeout exception. With the current buggy code,
        // this would call recordProbeFailure and then invoke onServerUnreachable
        // because maxFailedHeartbeats defaults to 1. The guard must prevent
        // that callback entirely.
        fakePlatform.failHeldWrite(
          const platform.GattOperationTimeoutException('writeCharacteristic'),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(unreachableCalls, 0,
            reason: 'onServerUnreachable must not fire after stop()');
      });
    });
```

- [ ] **Step 2: Run the tests — expect failure**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "I070: probe-write"
```

Expected: all three fail. The first two fail because a late probe-write callback reschedules the probe timer → elapse fires it → extra writes dispatch. The third fails because the late `.catchError` still invokes `recordProbeFailure` + `onServerUnreachable`.

- [ ] **Step 3: Add the guards to `_sendProbe`**

In `lifecycle_client.dart`, `_sendProbe` is at lines ~192-240. Update both callbacks:

```dart
  void _sendProbe() {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    _monitor.markProbeInFlight();
    _platform
        .writeCharacteristic(
          _connectionId,
          charUuid,
          lifecycle.heartbeatValue,
          true,
        )
        .then((_) {
      if (!_isRunning) return;
      _monitor.recordProbeSuccess();
      _scheduleProbe();
    }).catchError((Object error) {
      if (!_isRunning) return;
      if (!_isDeadPeerSignal(error)) {
        _monitor.cancelProbe();
        _scheduleProbe(after: _monitor.activityWindow);
        return;
      }
      final tripped = _monitor.recordProbeFailure();
      dev.log(
        'heartbeat failed (counted): ${error.runtimeType}',
        name: 'bluey.lifecycle',
        level: 900,
      );
      if (tripped) {
        dev.log(
          'heartbeat threshold reached — invoking onServerUnreachable',
          name: 'bluey.lifecycle',
          level: 1000,
        );
        stop();
        onServerUnreachable();
        return;
      }
      _scheduleProbe(after: _monitor.activityWindow);
    });
  }
```

- [ ] **Step 4: Run the tests — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "I070: probe-write"
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: all three new tests pass, everything else still passes.

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart
git commit -m "fix(lifecycle): guard probe-write callbacks against post-stop() mutation (I070)"
```

---

## Task 5: I078 — activity during `start()` → interval-read window is not dropped

**Files:**
- Test: `bluey/test/connection/lifecycle_client_test.dart` (test-only task; no production change needed)

**Why this task:** The spec requires `recordActivity()` not to drop signals during the window between `start()` entry and interval-read resolution. With `_isRunning = true` set at the top of `start()` (from Task 1), this behaviour is already correct — but we need a test that locks it in, so a future refactor cannot re-introduce I078. Task 6 later moves the assignment past the null checks; this test must continue to pass after that move.

- [ ] **Step 1: Add the test**

Append to `lifecycle_client_test.dart`. The test calls `recordActivity()` while the interval-read is held, then resolves the interval-read and verifies that the next probe deadline reflects the activity timestamp (not just the interval-read resolution time).

We don't have a direct accessor for `_monitor._lastActivityAt`, so we assert the *effect*: if activity was recorded at T=3s, the monitor's deadline is `activityWindow` from T=3s = T=8s. A probe must not fire earlier than that. Without I078's fix, the monitor would miss the T=3s activity, so its deadline would be whatever the initial-heartbeat write sets — typically T=0 + activityWindow = T=5s. The test advances to T=7s and asserts no probe has been dispatched yet beyond the initial ones.

```dart
    test('I078: recordActivity during interval-read window shifts the probe deadline', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        List<RemoteService>? services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        fakePlatform.holdNextReadCharacteristic();

        client.start(allServices: services!);
        async.flushMicrotasks();
        // T=0: initial heartbeat dispatched as part of start().
        final writesAfterStart = fakePlatform.writeCharacteristicCalls.length;

        // T=3s: simulate a user GATT op completing inside the window.
        async.elapse(const Duration(seconds: 3));
        client.recordActivity();
        async.flushMicrotasks();

        // Now resolve interval-read at T=3s. This sets monitor window
        // to 5s (half of the 10s server interval).
        fakePlatform.resolveHeldRead(
            lifecycle.encodeInterval(const Duration(seconds: 10)));
        async.flushMicrotasks();

        // Deadline is now T=3s + 5s = T=8s. Advance to T=7s — no probe
        // should have fired yet.
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(fakePlatform.writeCharacteristicCalls.length, writesAfterStart,
            reason: 'recordActivity at T=3s must push deadline to T=8s');

        // Advance past T=8s — the probe should now fire.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(fakePlatform.writeCharacteristicCalls.length, writesAfterStart + 1,
            reason: 'probe fires at T=8s (activity at T=3s + window 5s)');

        client.stop();
      });
    });
```

- [ ] **Step 2: Run the test — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "I078"
```

Expected: PASS. With `_isRunning = true` set at the top of `start()` (Task 1), `recordActivity()` passes the guard during the window.

Note: if this test fails, it means Task 1 set `_isRunning` somewhere else than the top of `start()`. Go back and fix Task 1, then rerun.

- [ ] **Step 3: Run the full file**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add bluey/test/connection/lifecycle_client_test.dart
git commit -m "test(lifecycle): lock in I078 — activity during start window not dropped"
```

---

## Task 6: Partial-start retry — move `_isRunning = true` past the pre-commit null checks

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Test: `bluey/test/connection/lifecycle_client_test.dart`

**Why this task:** Task 1 put `_isRunning = true` at the top of `start()` for simplicity. That works for I073/I078 but has a latent bug: if `start()` early-returns because the peer doesn't host the control service, `_isRunning` stays `true` forever, making a retry (e.g. after a later service-discovery cycle that does find the control service) impossible. The fix is to move the assignment past the null checks so `start()` only commits to run once it has something to do.

- [ ] **Step 1: Add the failing test**

Append to `lifecycle_client_test.dart`:

```dart
    test('start() with no control service leaves _isRunning false and is retryable', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      // First: simulate a regular (non-Bluey) device with no control service.
      fakePlatform.simulatePeripheral(
        id: _deviceAddress,
        name: 'Regular Device',
        services: const [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ],
      );

      await fakePlatform.connect(
        _deviceAddress,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      final platformServicesNoControl =
          await fakePlatform.discoverServices(_deviceAddress);
      final domainServicesNoControl = platformServicesNoControl
          .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
          .toList();

      final client = LifecycleClient(
        platformApi: fakePlatform,
        connectionId: _deviceAddress,
        onServerUnreachable: () {},
      );

      client.start(allServices: List<RemoteService>.from(domainServicesNoControl));

      // No control service found — start() must NOT mark itself running.
      expect(client.isRunning, isFalse,
          reason: 'start() without a control service must not commit');

      // Now simulate a second service-discovery pass that returns the
      // control service. A retry should succeed.
      fakePlatform.simulateBlueyServer(
        address: _deviceAddress,
        serverId: ServerId.generate(),
      );
      // Force the connection to refresh services via the fake's store.
      await fakePlatform.disconnect(_deviceAddress);
      await fakePlatform.connect(
        _deviceAddress,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );
      final platformServicesWithControl =
          await fakePlatform.discoverServices(_deviceAddress);
      final domainServicesWithControl = platformServicesWithControl
          .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
          .toList();

      client.start(
          allServices: List<RemoteService>.from(domainServicesWithControl));

      expect(client.isRunning, isTrue,
          reason: 'retry with control service must succeed');

      client.stop();
    });
```

- [ ] **Step 2: Run the test — expect failure**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "retryable"
```

Expected: FAIL at the first `expect(client.isRunning, isFalse)`. Task 1 set `_isRunning = true` at the top of `start()`, before the null checks, so even the no-control-service path leaves the flag set.

- [ ] **Step 3: Move the assignment past the null checks**

In `lifecycle_client.dart`, `start()` currently looks like:

```dart
  void start({required List<RemoteService> allServices}) {
    if (_isRunning) return;
    _isRunning = true;

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) return;

    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    // ... rest unchanged
  }
```

Move the `_isRunning = true;` line down:

```dart
  void start({required List<RemoteService> allServices}) {
    if (_isRunning) return;

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) return;

    // Commit point — from here on, any failure must unwind (see Task 7).
    _isRunning = true;
    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    // ... rest unchanged
  }
```

- [ ] **Step 4: Run the test — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "retryable"
```

Expected: PASS.

- [ ] **Step 5: Run the full file — expect no regressions**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: every test still passes. Pay special attention to the I078 test from Task 5 — it must continue to pass because `_isRunning = true` is still set before the async interval-read dispatch.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart
git commit -m "fix(lifecycle): gate _isRunning commit on control-service presence for retryable start()"
```

---

## Task 7: Transactional `start()` — unwind on synchronous platform throws

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Modify: `bluey/test/fakes/fake_platform.dart`
- Test: `bluey/test/connection/lifecycle_client_test.dart`

**Why this task:** After the commit point, `start()` calls `_sendProbe` (which calls `_platform.writeCharacteristic`) and potentially `_platform.readCharacteristic`. If either throws synchronously — an idiomatic `async` impl won't, but the platform-interface signature is just `Future<T>` and doesn't forbid it — `_isRunning` and `_heartbeatCharUuid` would be left set on a client that has no timer armed. Clean-architecture-wise, the class must own its invariants: any failure after commit must unwind fully and re-raise so the caller sees the real error.

- [ ] **Step 1: Add sync-throw support to `FakeBlueyPlatform`**

In `bluey/test/fakes/fake_platform.dart`, add a flag:

```dart
  /// When true, the next [writeCharacteristic] call throws synchronously
  /// (before returning a Future). Models a misbehaving platform impl —
  /// the platform-interface signature `Future<void>` doesn't forbid
  /// a non-`async` implementation from throwing sync, and
  /// LifecycleClient.start() must unwind cleanly if it does.
  bool simulateSyncWriteThrow = false;
```

Convert `writeCharacteristic` from a single `async` method into a sync-first entry that delegates to an `async` helper. Replace the existing signature:

```dart
  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) {
    if (simulateSyncWriteThrow) {
      simulateSyncWriteThrow = false;
      throw StateError('simulated synchronous writeCharacteristic throw');
    }
    return _writeCharacteristicAsync(
        deviceId, characteristicUuid, value, withResponse);
  }

  Future<void> _writeCharacteristicAsync(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    // ... existing body that was inside writeCharacteristic
  }
```

Move the entire existing body of `writeCharacteristic` (the one starting around line 563) into `_writeCharacteristicAsync`.

- [ ] **Step 2: Add the failing test**

Append to `lifecycle_client_test.dart`:

```dart
    test('start() unwinds fully when writeCharacteristic throws synchronously', () async {
      final fixture = await _setUpConnectedClient(onServerUnreachable: () {});
      final client = fixture.client;
      final fakePlatform = fixture.fakePlatform;
      final services = fixture.services;

      fakePlatform.simulateSyncWriteThrow = true;

      Object? caught;
      try {
        client.start(allServices: services);
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>(),
          reason: 'synchronous throw must propagate out of start()');
      expect(client.isRunning, isFalse,
          reason: '_isRunning must be cleared on sync-throw unwind');
      expect(client.probeInFlightForTest, isFalse,
          reason: 'monitor probeInFlight must be released');

      // A second start() with a healthy platform must be able to run.
      fakePlatform.simulateSyncWriteThrow = false;
      client.start(allServices: services);
      expect(client.isRunning, isTrue);

      client.stop();
    });
```

- [ ] **Step 3: Run the test — expect failure**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "synchronously"
```

Expected: FAIL. Without the try/catch, the exception propagates but `_isRunning` and `_heartbeatCharUuid` stay set; the monitor has `probeInFlight = true` from `markProbeInFlight()` inside `_sendProbe`. The second `start()` also fails because `_isRunning == true` trips the idempotency guard.

- [ ] **Step 4: Wrap the post-commit section in try/catch**

In `lifecycle_client.dart`, update `start()` to wrap the lines from `_sendProbe()` through the end of the interval-read dispatch:

```dart
  void start({required List<RemoteService> allServices}) {
    if (_isRunning) return;

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) return;

    // Commit point — from here on, any synchronous failure must
    // fully unwind so the class never exposes a partial-start state.
    _isRunning = true;
    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    dev.log('heartbeat started: char=$_heartbeatCharUuid', name: 'bluey.lifecycle');

    try {
      _sendProbe();

      final intervalChar = controlService.characteristics
          .where(
            (c) =>
                c.uuid.toString().toLowerCase() == lifecycle.intervalCharUuid,
          )
          .firstOrNull;

      if (intervalChar != null) {
        _platform
            .readCharacteristic(_connectionId, intervalChar.uuid.toString())
            .then((bytes) {
          if (!_isRunning) return;
          final serverInterval = lifecycle.decodeInterval(bytes);
          final heartbeatInterval = Duration(
            milliseconds: serverInterval.inMilliseconds ~/ 2,
          );
          _beginHeartbeat(heartbeatInterval);
        }).catchError((_) {
          if (!_isRunning) return;
          _beginHeartbeat(_defaultHeartbeatInterval);
        });
      } else {
        _beginHeartbeat(_defaultHeartbeatInterval);
      }
    } catch (_) {
      stop();
      rethrow;
    }
  }
```

- [ ] **Step 5: Run the test — expect pass**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart --name "synchronously"
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
cd bluey && flutter test
```

Expected: all tests pass. This catches any integration-level regression — `BlueyConnection`, `BlueyPeer`, and other callers of `LifecycleClient` should be unaffected because the public API hasn't changed.

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/fakes/fake_platform.dart bluey/test/connection/lifecycle_client_test.dart
git commit -m "feat(lifecycle): transactional start() unwinds on synchronous platform throws"
```

---

## Task 8: Mark backlog entries fixed

**Files:**
- Modify: `docs/backlog/I070-lifecycle-client-late-promise-callbacks.md`
- Modify: `docs/backlog/I073-lifecycle-client-start-not-idempotent.md`
- Modify: `docs/backlog/I078-lifecycle-client-activity-drop-during-start.md`
- Modify: `docs/backlog/README.md`

**Why this task:** Backlog hygiene — each fixed entry gets `status: fixed`, `fixed_in: <sha>`, and `last_verified: 2026-04-24`, per the workflow in `docs/backlog/README.md`. The index table is updated to move the three entries from "Open — domain layer" to "Fixed — verified in HEAD". The suggested order of attack loses its item #1, renumbering the rest.

- [ ] **Step 1: Capture the head commit SHA for `fixed_in`**

```bash
git rev-parse --short HEAD
```

Note the short SHA — this is the transactional-start commit from Task 7. Use it for all three entries.

- [ ] **Step 2: Update I070 frontmatter**

In `docs/backlog/I070-lifecycle-client-late-promise-callbacks.md`, change the frontmatter block. Replace:

```yaml
---
id: I070
title: LifecycleClient late promise callbacks can fire after `stop()`
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-23
---
```

with:

```yaml
---
id: I070
title: LifecycleClient late promise callbacks can fire after `stop()`
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-24
fixed_in: <sha from step 1>
---
```

- [ ] **Step 3: Update I073 frontmatter**

In `docs/backlog/I073-lifecycle-client-start-not-idempotent.md`, change `status: open` to `status: fixed`, `last_verified: 2026-04-23` to `last_verified: 2026-04-24`, and add `fixed_in: <sha>`.

- [ ] **Step 4: Update I078 frontmatter**

In `docs/backlog/I078-lifecycle-client-activity-drop-during-start.md`, change `status: open` to `status: fixed` and add `fixed_in: <sha>`. `last_verified: 2026-04-24` is already set.

- [ ] **Step 5: Update the README index**

In `docs/backlog/README.md`, remove these three rows from the "Open — domain layer" table:

```markdown
| [I070](I070-lifecycle-client-late-promise-callbacks.md) | LifecycleClient late promise callbacks fire after `stop()` | high |
| [I073](I073-lifecycle-client-start-not-idempotent.md) | `LifecycleClient.start()` is not idempotent | low |
| [I078](I078-lifecycle-client-activity-drop-during-start.md) | `LifecycleClient.recordActivity()` silently drops signals during `start()` → interval-read window | low |
```

Add them (in ID order) to the "Fixed — verified in HEAD" table:

```markdown
| [I070](I070-lifecycle-client-late-promise-callbacks.md) | LifecycleClient late promise callbacks fire after `stop()` | `<sha>` |
| [I073](I073-lifecycle-client-start-not-idempotent.md) | `LifecycleClient.start()` is not idempotent | `<sha>` |
| [I078](I078-lifecycle-client-activity-drop-during-start.md) | `LifecycleClient.recordActivity()` silently drops signals during `start()` → interval-read window | `<sha>` |
```

Remove cluster #1 from the "Suggested order of attack" section. Replace:

```markdown
1. **I070 + I073 + I078** — Lifecycle client guards. *Est. ≤1 day, one PR.* All three fixes live in `LifecycleClient`: `_isRunning` sentinel checked in every promise callback (I070), `start()` idempotency guard (I073), and activity-signal handling during the `start()` → interval-read window (I078). The `_isRunning` refactor is the shared backbone — all three ride on it. Promoted to #1 because I070 is `high` severity and the `LifecycleClient` code is warm after the I077 fix. Paired with #2 as sequential PRs; this one first because it's strictly smaller and doesn't depend on #2.

2. **I079** — Lifecycle server tolerates pending requests.
```

with (renumbering each subsequent item by one):

```markdown
1. **I079** — Lifecycle server tolerates pending requests.
```

and decrement the number of every subsequent numbered item (2→?, 3→?, 4→?, 5→? ... follow the existing entries). Also update the "(follow-up after #2)" reference in the former #6 item to "(follow-up after #1)".

- [ ] **Step 6: Commit**

```bash
git add docs/backlog/I070-lifecycle-client-late-promise-callbacks.md \
        docs/backlog/I073-lifecycle-client-start-not-idempotent.md \
        docs/backlog/I078-lifecycle-client-activity-drop-during-start.md \
        docs/backlog/README.md
git commit -m "chore(backlog): mark I070 + I073 + I078 fixed"
```

---

## Definition of done

- [ ] All seven test-driven tasks complete; each commit is reviewable in isolation.
- [ ] `cd bluey && flutter test` passes with no new failures.
- [ ] `cd bluey && flutter analyze` clean (no new warnings).
- [ ] `cd bluey && flutter test --coverage` — the domain-layer coverage target (90%) is not lowered; `lifecycle_client.dart` gains tests for the new edge cases.
- [ ] `docs/backlog/README.md` no longer lists I070/I073/I078 as open, and the suggested order of attack reflects the removal.
- [ ] The spec file `docs/superpowers/specs/2026-04-24-lifecycle-client-guards-design.md` remains unmodified — the plan implemented the spec faithfully.
