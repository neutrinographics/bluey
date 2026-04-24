# I077 Client-Side Deadline-Driven Probe Scheduling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `LifecycleClient`'s polling `Timer.periodic` + `_tick` with a deadline-driven one-shot `Timer` rescheduled at every state transition. Fixes I077: timer jitter was causing `shouldSendProbe()` to return false on slightly-early ticks, doubling the heartbeat cadence from 5s to 10s and racing the server timer.

**Architecture:** `LivenessMonitor` stays a pure state tracker but swaps its `shouldSendProbe()` query for two narrower primitives (`timeUntilNextProbe()`, `probeInFlight` getter). `LifecycleClient` moves timer ownership from periodic polling to event-driven scheduling — every state transition (probe success/failure, external activity, interval change) cancels the current timer and arms a new one-shot.

**Tech Stack:** Dart, `Timer` (dart:async), `LivenessMonitor` (pure), `FakeAsync` for deterministic tests.

**Spec:** [`docs/superpowers/specs/2026-04-24-i077-lifecycle-deadline-scheduling-design.md`](../specs/2026-04-24-i077-lifecycle-deadline-scheduling-design.md).

**Working directory for all commands:** `/Users/joel/git/neutrinographics/bluey`.

**Branch:** this plan executes on `investigate/i077-lifecycle-disconnect-storm` (the branch already carrying the diagnostic commits `7586d2c` + `2c2fb4a` for the spec). First task reverts the diagnostics before implementing the fix.

---

## File Structure

| File | Role |
|---|---|
| `bluey/lib/src/connection/liveness_monitor.dart` | Pure state tracker — adds `timeUntilNextProbe()` + `probeInFlight` getter, removes `shouldSendProbe()` |
| `bluey/lib/src/connection/lifecycle_client.dart` | Timer owner — rewritten from `Timer.periodic` polling to event-driven one-shot scheduling |
| `bluey/test/connection/liveness_monitor_test.dart` | Monitor tests — removes `shouldSendProbe` tests, adds tests for the new methods |
| `bluey/test/connection/lifecycle_client_test.dart` | Client tests — adds I077 regression test, updates any polling-specific assertions |
| `bluey/lib/src/gatt_server/lifecycle_server.dart` | Revert `[I077]` instrumentation (this plan's Task 1) |
| `bluey/lib/src/gatt_server/bluey_server.dart` | Revert `[I077]` instrumentation |
| `bluey/lib/src/connection/bluey_connection.dart` | Revert `[I077]` instrumentation |
| `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` | Revert `[I077]` instrumentation (value-bytes log) |
| `docs/backlog/I077-lifecycle-client-disconnect-storm.md` | Mark fixed after verification |

---

## Task 1: Revert the I077 diagnostic instrumentation

**Rationale:** Commit `7586d2c` added `[I077]` `debugPrint` calls across five files for the investigation. Now that the root cause is understood, those logs should not ship. Revert cleanly before building the fix on top.

**Files touched (by the revert):**
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt`
- `bluey/lib/src/connection/bluey_connection.dart`
- `bluey/lib/src/connection/lifecycle_client.dart`
- `bluey/lib/src/gatt_server/bluey_server.dart`
- `bluey/lib/src/gatt_server/lifecycle_server.dart`

- [ ] **Step 1: Check current branch state**

```bash
git status
git log --oneline -3
```

Expected last two commits on `investigate/i077-lifecycle-disconnect-storm`:
```
2c2fb4a doc:spec for I077 client-side deadline-driven probe scheduling
7586d2c investigate(i077): add diagnostic logging to lifecycle write/disconnect paths
```

- [ ] **Step 2: Revert the instrumentation commit**

```bash
git revert --no-edit 7586d2c
```

Expected: a new commit with the instrumentation removed. `git log --oneline -3` should show:
```
<new sha> Revert "investigate(i077): add diagnostic logging to lifecycle write/disconnect paths"
2c2fb4a doc:spec for I077 client-side deadline-driven probe scheduling
7586d2c investigate(i077): add diagnostic logging to lifecycle write/disconnect paths
```

- [ ] **Step 3: Verify all `[I077]` debugPrints are gone from source**

```bash
grep -rn "\[I077\]" bluey/lib/ bluey_android/android/src/ 2>&1
```

Expected: no matches. (Backlog file still legitimately mentions I077; filter to source dirs only.)

- [ ] **Step 4: Run the bluey test suite to confirm the revert didn't break anything**

```bash
cd bluey && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!` (baseline before the fix — the bug still exists in code, but tests don't exercise it deterministically because `FakeAsync` has no jitter).

- [ ] **Step 5: Nothing to commit**

The revert commit from Step 2 is the only change. Move on to Task 2.

---

## Task 2: Add `probeInFlight` getter to `LivenessMonitor`

**Files:**
- Modify: `bluey/lib/src/connection/liveness_monitor.dart`
- Modify: `bluey/test/connection/liveness_monitor_test.dart`

**Rationale:** The new `LifecycleClient._sendProbeOrDefer` needs to query "is a probe in flight?" directly. Currently `_probeInFlight` is a private field read only inside `shouldSendProbe()`. Expose it as a public getter.

- [ ] **Step 1: Write the failing test**

Append to the `group('LivenessMonitor', () { ... })` block in `bluey/test/connection/liveness_monitor_test.dart`, immediately after the `cancelProbe does NOT refresh the activity timestamp` test (around line 135):

```dart
    test('probeInFlight getter reflects markProbeInFlight + release', () {
      final m = buildMonitor();
      expect(m.probeInFlight, isFalse);
      m.markProbeInFlight();
      expect(m.probeInFlight, isTrue);
      m.recordProbeSuccess();
      expect(m.probeInFlight, isFalse);
    });

    test('probeInFlight released by cancelProbe', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      m.cancelProbe();
      expect(m.probeInFlight, isFalse);
    });

    test('probeInFlight released by recordProbeFailure', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      m.recordProbeFailure();
      expect(m.probeInFlight, isFalse);
    });
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart -p --name 'probeInFlight' 2>&1 | tail -10
```

Expected: FAIL — `The getter 'probeInFlight' isn't defined for the type 'LivenessMonitor'`.

- [ ] **Step 3: Add the getter**

In `bluey/lib/src/connection/liveness_monitor.dart`, add the getter immediately before the `recordActivity()` method (around line 41, right after the `activityWindow` getter):

```dart
  /// Whether a probe is currently in flight. Needed by callers that
  /// schedule the next probe from timer callbacks — a fired timer must
  /// not send a new probe while a previous one is still pending.
  bool get probeInFlight => _probeInFlight;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart -p --name 'probeInFlight' 2>&1 | tail -10
```

Expected: all three new tests PASS.

- [ ] **Step 5: Run the full monitor suite to confirm no regressions**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/liveness_monitor.dart bluey/test/connection/liveness_monitor_test.dart
git commit -m "$(cat <<'EOF'
feat(liveness-monitor): expose probeInFlight as a public getter

Needed by the upcoming deadline-driven scheduler — the timer
callback must check probeInFlight before sending a new probe,
so the previous in-flight probe's completion can reschedule.

Part of I077.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `timeUntilNextProbe()` to `LivenessMonitor`

**Files:**
- Modify: `bluey/lib/src/connection/liveness_monitor.dart`
- Modify: `bluey/test/connection/liveness_monitor_test.dart`

**Rationale:** The new scheduler needs a way to ask "how long from now until the probe deadline?" so it can arm a one-shot timer for exactly that duration. `shouldSendProbe` only returns a boolean, which isn't enough for scheduling.

- [ ] **Step 1: Write the failing tests**

Append to `bluey/test/connection/liveness_monitor_test.dart`, inside the same `group('LivenessMonitor', ...)` block after the new `probeInFlight` tests from Task 2:

```dart
    test('timeUntilNextProbe returns activityWindow when no activity recorded yet', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      // lastActivity is null — deadline falls back to a full activityWindow
      // from now, so the first schedule after construction is activityWindow.
      expect(m.timeUntilNextProbe(), const Duration(seconds: 5));
    });

    test('timeUntilNextProbe returns activityWindow immediately after recordActivity', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      expect(m.timeUntilNextProbe(), const Duration(seconds: 5));
    });

    test('timeUntilNextProbe decreases as clock advances', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 2));
      expect(m.timeUntilNextProbe(), const Duration(seconds: 3));
    });

    test('timeUntilNextProbe returns Duration.zero once deadline has passed', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 10));
      expect(m.timeUntilNextProbe(), Duration.zero,
          reason: 'Never returns a negative value; caller should probe immediately');
    });

    test('timeUntilNextProbe reflects updateActivityWindow', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 2));
      m.updateActivityWindow(const Duration(seconds: 10));
      // With the new 10s window, 8s remain.
      expect(m.timeUntilNextProbe(), const Duration(seconds: 8));
    });

    test('timeUntilNextProbe is not affected by markProbeInFlight', () {
      // The in-flight flag is a separate dimension — the deadline
      // still advances in real time regardless of whether a probe is pending.
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 2));
      m.markProbeInFlight();
      expect(m.timeUntilNextProbe(), const Duration(seconds: 3));
    });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart -p --name 'timeUntilNextProbe' 2>&1 | tail -10
```

Expected: FAIL — `The method 'timeUntilNextProbe' isn't defined`.

- [ ] **Step 3: Add the method**

In `bluey/lib/src/connection/liveness_monitor.dart`, add the method immediately before the existing `shouldSendProbe()` method (around line 59):

```dart
  /// How long from now until the next probe is due.
  ///
  /// Returns [Duration.zero] if the deadline is already past — caller
  /// should probe immediately. Returns [activityWindow] if no activity
  /// has been recorded yet, giving the caller a sensible first deadline.
  ///
  /// The in-flight flag is a separate dimension: this method reports
  /// the deadline regardless, so the caller can make a unified
  /// "time to probe" decision (via a one-shot timer) without needing
  /// to special-case the in-flight branch.
  Duration timeUntilNextProbe() {
    final last = _lastActivityAt;
    if (last == null) return _activityWindow;
    final elapsed = _now().difference(last);
    final remaining = _activityWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart -p --name 'timeUntilNextProbe' 2>&1 | tail -10
```

Expected: all 6 new tests PASS.

- [ ] **Step 5: Run the full monitor suite**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/liveness_monitor.dart bluey/test/connection/liveness_monitor_test.dart
git commit -m "$(cat <<'EOF'
feat(liveness-monitor): add timeUntilNextProbe()

Returns the remaining duration until the activity-window deadline,
clamped to Duration.zero when elapsed. The upcoming deadline-driven
scheduler uses this to arm a one-shot Timer at exactly the deadline,
replacing the jitter-sensitive Timer.periodic + shouldSendProbe()
polling that caused I077.

Part of I077.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Write the I077 regression test in `LifecycleClient`

**Files:**
- Modify: `bluey/test/connection/lifecycle_client_test.dart`

**Rationale:** Lock in the deadline-scheduling behavior so the fix can't silently regress. The test exercises the behavioral difference between polling and scheduling: after `recordActivity` at T=3, the next probe fires at T=8 (deadline = 3+5), not at T=10 (next periodic tick). Old polling code would NOT send a probe at T=8. New scheduling code will.

This test is written RED — it will fail against the current polling code. Task 5 makes it pass.

- [ ] **Step 1: Inspect the existing test file to find a good insertion point**

```bash
cd /Users/joel/git/neutrinographics/bluey
grep -n "^  group\|^    test" bluey/test/connection/lifecycle_client_test.dart | tail -20
```

Use the output to pick an insertion point inside the `group('LifecycleClient', () { ... })` block, near the existing heartbeat-cadence tests. The test file already imports `package:fake_async/fake_async.dart`, so `FakeAsync().run(...)` is available.

- [ ] **Step 2: Write the failing test**

Append this test inside the `group('LifecycleClient', () { ... })` block, before its closing brace:

```dart
    test(
      'I077 regression: recordActivity reschedules probe to exactly '
      'activityWindow from now (not next periodic tick)',
      () async {
        // Set up the full connected lifecycle client (10s server interval →
        // 5s client heartbeat window).
        final setup = await _setUpConnectedClient(
          onServerUnreachable: () {},
        );
        final client = setup.client;
        final services = setup.services;
        final fakePlatform = setup.fakePlatform;

        FakeAsync().run((async) {
          client.start(allServices: services);

          // Let the start() sequence settle: initial probe + interval read +
          // schedule the first periodic/one-shot timer. After this elapse,
          // the initial probe has written, completed, and recorded activity.
          async.elapse(const Duration(milliseconds: 100));
          final initialProbeCount = fakePlatform.writeCharacteristicCalls.length;
          expect(initialProbeCount, greaterThanOrEqualTo(1),
              reason: 'start() should have issued the initial probe');

          // At T=3s, simulate a user op completing. recordActivity must
          // reset the deadline so the next probe is due at T=3+5 = 8s.
          async.elapse(const Duration(seconds: 3));
          client.recordActivity();

          // Advance to T=5s total. Under the old polling model, a probe
          // would NOT fire here (shouldSendProbe returns false because
          // activity is recent). Under the new scheduling model, a probe
          // also does not fire here (deadline is T=8). Both agree.
          async.elapse(const Duration(seconds: 2));
          expect(
            fakePlatform.writeCharacteristicCalls.length,
            initialProbeCount,
            reason: 'At T=5s, recent activity means no probe yet',
          );

          // Advance to T=8s total. Under the old polling model, the next
          // tick is at T=10s, so no probe yet. Under the new scheduling
          // model, the deadline is T=8, so a probe fires here.
          async.elapse(const Duration(seconds: 3));
          expect(
            fakePlatform.writeCharacteristicCalls.length,
            initialProbeCount + 1,
            reason: 'Deadline-driven scheduler must probe at '
                'recordActivity + activityWindow, not at the next periodic tick',
          );
        });
      },
    );
```

- [ ] **Step 3: Run the test and verify it FAILS**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart -p --name 'I077 regression' 2>&1 | tail -15
```

Expected: FAIL with an assertion about the probe count at T=8s — the old polling code does not probe until T=10s.

If instead the test passes, STOP. Either the test doesn't actually distinguish the two models (re-examine assumptions) or the old code already happens to do the right thing in this scenario. Do not proceed to Task 5 with a green test that's supposed to be red.

- [ ] **Step 4: Commit the failing test**

```bash
git add bluey/test/connection/lifecycle_client_test.dart
git commit -m "$(cat <<'EOF'
test(lifecycle-client): add I077 regression — recordActivity reschedules probe

Exercises the behavioral difference between polling and deadline
scheduling: after recordActivity at T=3, the next probe must fire
at T=8 (deadline = lastActivity + activityWindow), not at T=10
(next periodic tick).

Currently FAILS against the existing Timer.periodic + shouldSendProbe
polling code. Task 5 (replacing polling with deadline scheduling)
makes it pass.

Part of I077.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Replace polling with deadline scheduling in `LifecycleClient`

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`

**Rationale:** The primary fix. Remove `Timer.periodic` + `_tick`. Add `_scheduleProbe({Duration? after})` + `_sendProbeOrDefer`. Update `_beginHeartbeat`, `_sendProbe` completion paths, and `recordActivity` to drive scheduling through those helpers.

Each completion path in `_sendProbe` ends with exactly one of: `_scheduleProbe()` (monitor deadline), `_scheduleProbe(after: activityWindow)` (explicit retry delay), or `stop()` (threshold trip).

- [ ] **Step 1: Update `recordActivity` to reschedule after recording**

In `bluey/lib/src/connection/lifecycle_client.dart`, replace the existing `recordActivity` method (currently around lines 54-57):

```dart
  /// Forwarded from [BlueyConnection] on any successful GATT op or
  /// incoming notification. Treats the peer as demonstrably alive.
  /// No-op if the lifecycle isn't running — prevents lingering
  /// notification subscriptions from dirtying monitor state after
  /// [stop] has been called.
  void recordActivity() {
    if (!isRunning) return;
    _monitor.recordActivity();
  }
```

with:

```dart
  /// Forwarded from [BlueyConnection] on any successful GATT op or
  /// incoming notification. Treats the peer as demonstrably alive and
  /// shifts the probe deadline forward by [_monitor.activityWindow].
  /// No-op if the lifecycle isn't running — prevents lingering
  /// notification subscriptions from dirtying monitor state after
  /// [stop] has been called.
  void recordActivity() {
    if (!isRunning) return;
    _monitor.recordActivity();
    // Deadline shifted — supersede the pending timer.
    _scheduleProbe();
  }
```

- [ ] **Step 2: Replace `_beginHeartbeat` and remove `_tick`**

In the same file, replace this block (currently around lines 143-159):

```dart
  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    dev.log('heartbeat interval set: ${interval.inMilliseconds}ms', name: 'bluey.lifecycle');
    // Update the monitor in place so a probe in flight from the initial
    // synchronous send keeps its markProbeInFlight flag intact.
    _monitor.updateActivityWindow(interval);
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(interval, (_) => _tick());
  }

  void _tick() {
    if (!_monitor.shouldSendProbe()) return;
    _sendProbe();
  }
```

with:

```dart
  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    dev.log('heartbeat interval set: ${interval.inMilliseconds}ms', name: 'bluey.lifecycle');
    // Update the monitor in place so a probe in flight from the initial
    // synchronous send keeps its markProbeInFlight flag intact.
    _monitor.updateActivityWindow(interval);
    _scheduleProbe();
  }

  /// Cancel any pending scheduled probe and schedule a new one.
  ///
  /// If [after] is null (default), the delay is computed from the
  /// monitor's current deadline — appropriate after a probe success or
  /// after external [recordActivity] shifts the deadline forward.
  ///
  /// If [after] is non-null, the delay is that explicit duration —
  /// appropriate after a probe failure, where the monitor's deadline
  /// would already have elapsed (producing an immediate-retry cadence
  /// that diverges from the original polling behaviour). Failure paths
  /// pass [_monitor.activityWindow] to preserve the roughly-one-probe-
  /// per-window rate-limit that polling produced implicitly.
  ///
  /// No-op if the client has been stopped.
  void _scheduleProbe({Duration? after}) {
    if (_heartbeatCharUuid == null) return;
    _probeTimer?.cancel();
    final delay = after ?? _monitor.timeUntilNextProbe();
    _probeTimer = Timer(delay, _sendProbeOrDefer);
  }

  /// Timer callback. Sends a probe unless one is already in flight
  /// (in which case the in-flight probe's completion handler will
  /// reschedule). Re-verifies the deadline in case [recordActivity]
  /// raced the timer firing — if activity just shifted the deadline
  /// forward, reschedule instead of probing now.
  void _sendProbeOrDefer() {
    if (_heartbeatCharUuid == null) return;
    if (_monitor.probeInFlight) return;
    if (_monitor.timeUntilNextProbe() > Duration.zero) {
      _scheduleProbe();
      return;
    }
    _sendProbe();
  }
```

- [ ] **Step 3: Update `_sendProbe` completion paths to reschedule**

In the same file, replace the existing `_sendProbe` method (currently around lines 161-202, after the revert from Task 1) with:

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
      _monitor.recordProbeSuccess();
      // Success refreshed lastActivity → monitor deadline is now
      // exactly activityWindow from now. No explicit override.
      _scheduleProbe();
    }).catchError((Object error) {
      if (!_isDeadPeerSignal(error)) {
        // Transient platform error — release in-flight, retry after a
        // full activityWindow (the monitor deadline has already elapsed
        // by the time we got here, so without the explicit delay we'd
        // hammer the peer with immediate retries).
        _monitor.cancelProbe();
        _scheduleProbe(after: _monitor.activityWindow);
        return;
      }
      final tripped = _monitor.recordProbeFailure();
      dev.log(
        'heartbeat failed (counted): ${error.runtimeType}',
        name: 'bluey.lifecycle',
        level: 900, // WARNING
      );
      if (tripped) {
        dev.log(
          'heartbeat threshold reached — invoking onServerUnreachable',
          name: 'bluey.lifecycle',
          level: 1000, // SEVERE
        );
        stop();
        onServerUnreachable();
        // No reschedule — connection is tearing down.
        return;
      }
      // Under-threshold dead-peer signal: retry one activityWindow later
      // (same rate-limit as the transient path).
      _scheduleProbe(after: _monitor.activityWindow);
    });
  }
```

- [ ] **Step 4: Run the I077 regression test — verify it now PASSES**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart -p --name 'I077 regression' 2>&1 | tail -10
```

Expected: PASS. If it still fails, re-read the changes above and verify `_scheduleProbe()` is being called where expected.

- [ ] **Step 5: Run the full LifecycleClient test suite to catch regressions**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart 2>&1 | tail -15
```

Expected: **all tests pass**. Existing tests should continue to work because:

- Steady-state cadence (probe every 5s with no external activity) is identical between polling and scheduling.
- `FakeAsync` is deterministic, so there's no jitter that would distinguish the two models in unaffected tests.

If a test DOES fail, the most likely causes are:

1. A test asserting a specific retry interval after a transient failure that previously relied on the next polling tick (old: ~tick interval after failure; new: `activityWindow` after failure). If the test is still valid behaviorally, the expected time may need updating.
2. A test asserting on a shared-state mutation from `recordActivity` that now also schedules a timer. The schedule itself is invisible; only an observable (probe firing) should have changed.

If you hit a failure and are uncertain whether the old test was correct, stop and escalate — do not mutate test expectations without understanding the semantic difference.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart
git commit -m "$(cat <<'EOF'
fix(lifecycle-client): replace polling Timer.periodic with deadline scheduling

Root cause of I077: Timer.periodic tick interval and LivenessMonitor
activityWindow were set to the same value. Dart timer jitter caused
slightly-early ticks to fail the >= activityWindow check in
shouldSendProbe, doubling the effective heartbeat cadence from 5s to
10s and racing the server's 10s timer.

Fix: one-shot Timer rearmed at every state transition that shifts
the deadline (probe success, activity recorded, probe failure retry).
The timer fires at exactly the deadline — no polling, no jitter
window, no skipped ticks.

Completion paths each end with exactly one of:
- _scheduleProbe()             (success / activity: monitor deadline)
- _scheduleProbe(after: window) (retry: explicit delay — monitor
                                 deadline already elapsed)
- stop()                       (trip: no reschedule)

Fixes I077.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Remove `shouldSendProbe()` from `LivenessMonitor`

**Files:**
- Modify: `bluey/lib/src/connection/liveness_monitor.dart`
- Modify: `bluey/test/connection/liveness_monitor_test.dart`

**Rationale:** After Task 5, `shouldSendProbe()` has no callers. Dead code. Remove it and its tests.

- [ ] **Step 1: Verify there are no remaining callers**

```bash
cd /Users/joel/git/neutrinographics/bluey
grep -rn "shouldSendProbe" bluey/lib/ bluey_platform_interface/lib/ bluey_android/lib/ bluey_ios/lib/ 2>&1
```

Expected: only matches inside `liveness_monitor.dart` itself. If anything in `bluey/lib/` still references it, STOP — Task 5 missed a call site.

- [ ] **Step 2: Remove the method from `liveness_monitor.dart`**

Delete the `shouldSendProbe()` method. In the current source after Tasks 2 and 3, it's the block that looks like:

```dart
  /// Tick-time decision: should we send a probe this tick? False if
  /// a probe is already pending, or activity is recent within the
  /// window. Uses `>=` at the boundary so the first tick after the
  /// window expires sends a heartbeat in time to beat the server's
  /// matching per-client timeout — with `>` the boundary slides the
  /// heartbeat out to the NEXT tick, racing the server timer.
  bool shouldSendProbe() {
    if (_probeInFlight) return false;
    final last = _lastActivityAt;
    if (last == null) return true;
    return _now().difference(last) >= _activityWindow;
  }
```

Delete the whole doc-comment + method. Leave a blank line between the preceding `timeUntilNextProbe()` method and the following `updateActivityWindow()` method.

- [ ] **Step 3: Remove the `shouldSendProbe` tests**

In `bluey/test/connection/liveness_monitor_test.dart`, delete these existing tests (they exercise a method that no longer exists):

- `test('shouldSendProbe is true initially (no activity yet)', ...)` — around line 21
- `test('recordActivity then shouldSendProbe within window returns false', ...)` — around line 26
- `test('recordActivity then shouldSendProbe at window boundary returns true', ...)` — around line 33
- `test('markProbeInFlight prevents shouldSendProbe from firing again', ...)` — around line 42

Also update any remaining tests in the file that use `shouldSendProbe()` inside their assertions. Specifically, in `test('recordProbeSuccess clears in-flight flag and refreshes activity', ...)`, replace:

```dart
      // In-flight cleared AND activity refreshed.
      expect(m.shouldSendProbe(), isFalse);
      advance(const Duration(seconds: 3));
      expect(m.shouldSendProbe(), isTrue);
```

with:

```dart
      // In-flight cleared AND activity refreshed.
      expect(m.probeInFlight, isFalse);
      expect(m.timeUntilNextProbe(), const Duration(seconds: 2));
      advance(const Duration(seconds: 3));
      expect(m.timeUntilNextProbe(), Duration.zero);
```

In `test('recordProbeFailure increments counter and releases in-flight', ...)`, replace:

```dart
      // In-flight cleared → next tick can probe.
      expect(m.shouldSendProbe(), isTrue);
```

with:

```dart
      // In-flight cleared.
      expect(m.probeInFlight, isFalse);
```

In `test('recordActivity during in-flight probe does not release flag', ...)`, replace:

```dart
      // Activity recorded, counter reset — but in-flight flag still true.
      expect(m.shouldSendProbe(), isFalse);
      m.recordProbeSuccess();
      // Now the flag releases.
      expect(m.shouldSendProbe(), isFalse); // activity is recent
```

with:

```dart
      // Activity recorded, counter reset — but in-flight flag still true.
      expect(m.probeInFlight, isTrue);
      m.recordProbeSuccess();
      // Now the flag releases.
      expect(m.probeInFlight, isFalse);
```

In `test('recordProbeSuccess on non-in-flight monitor is idempotent', ...)`, no change needed — that test does not call `shouldSendProbe`.

In `test('cancelProbe releases the in-flight flag', ...)`, replace:

```dart
      m.cancelProbe();
      expect(m.shouldSendProbe(), isTrue);
```

with:

```dart
      m.cancelProbe();
      expect(m.probeInFlight, isFalse);
```

In `test('cancelProbe does NOT refresh the activity timestamp', ...)`, replace:

```dart
      m.markProbeInFlight();
      m.cancelProbe();
      // 10s since last real activity — cancel must not have updated it.
      expect(m.shouldSendProbe(), isTrue);
```

with:

```dart
      m.markProbeInFlight();
      m.cancelProbe();
      // 10s since last real activity — cancel must not have updated it.
      expect(m.timeUntilNextProbe(), Duration.zero);
```

In `test('updateActivityWindow preserves in-flight and counter state', ...)`, replace:

```dart
      m.updateActivityWindow(const Duration(seconds: 20));
      // In-flight flag preserved.
      expect(m.shouldSendProbe(), isFalse);
```

with:

```dart
      m.updateActivityWindow(const Duration(seconds: 20));
      // In-flight flag preserved.
      expect(m.probeInFlight, isTrue);
```

- [ ] **Step 4: Run the monitor test suite**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the full bluey suite to confirm nothing else broke**

```bash
cd bluey && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/liveness_monitor.dart bluey/test/connection/liveness_monitor_test.dart
git commit -m "$(cat <<'EOF'
refactor(liveness-monitor): remove dead shouldSendProbe()

After the I077 scheduler fix, LifecycleClient uses timeUntilNextProbe()
+ probeInFlight instead. No callers remain. Remove the method and
update the tests that exercised it to check the underlying state
directly.

Part of I077.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Full regression sweep + static analysis

**Files:** none (verification only).

- [ ] **Step 1: Run the full Dart test suites across all packages**

```bash
cd /Users/joel/git/neutrinographics/bluey
cd bluey && flutter test 2>&1 | tail -5
cd /Users/joel/git/neutrinographics/bluey/bluey_platform_interface && flutter test 2>&1 | tail -5
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!` from each package.

- [ ] **Step 2: Run the static analyzer**

```bash
cd /Users/joel/git/neutrinographics/bluey && flutter analyze 2>&1 | tail -10
```

Expected: `No issues found!`.

- [ ] **Step 3: Run the Android Kotlin tests**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_android/android && ./gradlew test 2>&1 | tail -5
```

Expected: `BUILD SUCCESSFUL` — no regression from the I077 debugPrint revert in Task 1.

- [ ] **Step 4: No commit — verification only**

---

## Task 8: Manual verification on physical hardware (user-run)

**Files:** none (manual verification).

**Cannot be automated.** Requires the user to run the Android server + iOS client on physical devices and observe that the disconnect/reconnect storm is gone.

- [ ] **Step 1: Launch Android server**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey/example && flutter run -d <android-device-id>
```

Let it start the server (`[Server] Started`, `Added service ...`, `Advertising started`).

- [ ] **Step 2: Connect iOS client**

From the iOS example app, scan and connect to the Pixel 6a ("Bluey Demo"). Leave both apps idle for 60+ seconds.

- [ ] **Step 3: Verify no disconnect storm**

Capture both log streams for the same 60-second window.

**Android log must NOT contain:**
- `[Bluey] [Server] Client disconnected: 6D:FE:B9...` (or similar) occurring repeatedly during the idle period.

**iOS log must show:**
- `_sendProbe` cadence in the lifecycle client: writes roughly every 5 seconds (server interval ÷ 2 with the default 10s server interval).

If both conditions hold, I077 is fixed.

- [ ] **Step 4: Report**

If verification passes, proceed to Task 9. If it fails, stop and escalate — do not mark the backlog entry fixed.

---

## Task 9: Mark I077 as fixed in the backlog

**Files:**
- Modify: `docs/backlog/I077-lifecycle-client-disconnect-storm.md`
- Modify: `docs/backlog/README.md`

- [ ] **Step 1: Capture the final fix commit SHA**

```bash
cd /Users/joel/git/neutrinographics/bluey
git log --oneline -10
```

The `fixed_in` value should be the last substantive fix commit — likely the Task 5 commit (`fix(lifecycle-client): ...`) or the Task 6 commit (`refactor(liveness-monitor): ...`) depending on which one closes the loop. Use whichever SHA corresponds to the final landing commit on main after merge.

- [ ] **Step 2: Update the I077 frontmatter**

Open `docs/backlog/I077-lifecycle-client-disconnect-storm.md`. Change the frontmatter:

```yaml
---
id: I077
title: Client appears to toggle connected/disconnected during heartbeat activity
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-04-24
related: [I020, I021]
---
```

to:

```yaml
---
id: I077
title: Client appears to toggle connected/disconnected during heartbeat activity
category: bug
severity: medium
platform: both
status: fixed
last_verified: 2026-04-24
fixed_in: <fix-sha>
related: [I020, I021]
---
```

Replace `<fix-sha>` with the actual SHA.

- [ ] **Step 3: Move I077 from the open list to the Fixed table in the README**

In `docs/backlog/README.md`, remove this row from the domain-layer Open table:

```markdown
| [I077](I077-lifecycle-client-disconnect-storm.md) | Client appears to toggle connected/disconnected during heartbeat activity | medium |
```

Add this row to the "Fixed — verified in HEAD" table, preserving ID order (I077 goes after I021 fixed entries):

```markdown
| [I077](I077-lifecycle-client-disconnect-storm.md) | Client appears to toggle connected/disconnected during heartbeat activity | `<fix-sha>` |
```

- [ ] **Step 4: Commit the backlog update**

```bash
git add docs/backlog/I077-lifecycle-client-disconnect-storm.md docs/backlog/README.md
git commit -m "$(cat <<'EOF'
doc(backlog): mark I077 fixed

LifecycleClient now uses deadline-driven one-shot timer scheduling
instead of Timer.periodic polling. The jitter-induced tick-skip that
doubled the heartbeat cadence is gone; the server-side spurious
disconnect storm is resolved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Results

**Spec coverage audit:**

| Spec requirement | Plan task(s) |
|---|---|
| Revert the `[I077]` instrumentation before implementing the fix | Task 1 |
| Add `bool get probeInFlight` to LivenessMonitor | Task 2 |
| Add `Duration timeUntilNextProbe()` to LivenessMonitor | Task 3 |
| Remove `shouldSendProbe()` from LivenessMonitor | Task 6 |
| Docstring update on `recordActivity()` noting deadline side-effect | Task 5, Step 1 |
| Add `_scheduleProbe({Duration? after})` helper | Task 5, Step 2 |
| Add `_sendProbeOrDefer()` timer callback | Task 5, Step 2 |
| Remove `_tick()` method | Task 5, Step 2 (replaced inline) |
| Remove `Timer.periodic(...)` in `_beginHeartbeat` | Task 5, Step 2 |
| `_beginHeartbeat` rewritten: log, `updateActivityWindow`, `_scheduleProbe()` | Task 5, Step 2 |
| `_sendProbe` completion paths each end with exactly one of `_scheduleProbe()` / `_scheduleProbe(after: activityWindow)` / `stop()` | Task 5, Step 3 |
| `recordActivity` gains `_scheduleProbe()` side-effect | Task 5, Step 1 |
| Transient failure retry at `activityWindow` (not immediate) | Task 5, Step 3 — explicit `after: _monitor.activityWindow` |
| Dead-peer under-threshold retry at `activityWindow` | Task 5, Step 3 — explicit `after: _monitor.activityWindow` |
| Dead-peer trip: `stop()`, no reschedule | Task 5, Step 3 |
| `stop()` cancels timer and clears `_heartbeatCharUuid` (unchanged) | Task 5, Step 2 — `_scheduleProbe` and `_sendProbeOrDefer` both no-op on null |
| `LivenessMonitor` unit tests — `timeUntilNextProbe` and `probeInFlight` | Tasks 2, 3, 6 |
| `LifecycleClient` unit tests — I077 regression (deadline behaviour) | Task 4 |
| Full regression test sweep | Task 7 |
| Manual reproduction verification | Task 8 |
| Mark I077 fixed in backlog | Task 9 |

Every spec requirement maps to at least one task.

**Placeholder scan:** No TBD/TODO/vague references. The `<fix-sha>` in Task 9 is an explicit instruction to substitute at implementation time, not a plan placeholder.

**Type consistency:** `probeInFlight` (getter) and `timeUntilNextProbe()` (method) are used consistently across Tasks 2, 3, 5, 6. `_scheduleProbe({Duration? after})` keyword argument name `after` is used consistently. `_sendProbeOrDefer` spelled identically in all four references.

**Scope check:** Plan stays within `bluey/lib/src/connection/` + its tests + backlog updates. No platform-interface changes, no native changes, no server-side changes. Consistent with spec non-goals.
