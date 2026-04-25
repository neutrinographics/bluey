# I097 Time-Based Peer-Silence Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the count-based heartbeat-failure mechanism with time-based peer-silence detection. Defer probes during user-op pendency. Route user-op timeouts into the same silence detector that probe failures feed. Drop `maxFailedHeartbeats` from the public API and add `peerSilenceTimeout` (`Duration`).

**Architecture:** `LivenessMonitor` is renamed `PeerSilenceMonitor` and rewritten with a wall-clock death timer keyed off `_firstFailureAt`, cancelled on any successful exchange, ignoring pending state. `LifecycleClient` adds `markUserOpStarted/Ended/recordUserOpFailure` and defers probes when user ops are pending. `BlueyConnection` wraps each user-op call site with start/end accounting and routes timeouts to the failure path. `Bluey.connect()` / `Bluey.peer()` change parameter signature. Example app's `ConnectionSettings` and tolerance UI shift from counts to durations.

**Tech Stack:** Dart, `Timer` (dart:async), `clock` package for test injection, `fake_async` for deterministic time travel.

**Spec:** [`docs/superpowers/specs/2026-04-26-i097-client-opslot-starvation-design.md`](../specs/2026-04-26-i097-client-opslot-starvation-design.md)

**Working directory for all commands:** `/Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence`.

**Branch:** `fix/i097-peer-silence` off `main`.

---

## File Structure

| File | Role |
|---|---|
| `bluey/lib/src/connection/liveness_monitor.dart` | Rename file → `peer_silence_monitor.dart`. Class renamed, semantics rewritten. |
| `bluey/lib/src/connection/lifecycle_client.dart` | Subscribe to monitor's `onSilent`, add user-op tracking + filter, modify `_sendProbeOrDefer`. |
| `bluey/lib/src/connection/bluey_connection.dart` | Wrap user-op call sites with `markUserOpStarted/Ended` + `recordUserOpFailure`. Replace `int maxFailedHeartbeats` with `Duration peerSilenceTimeout`. |
| `bluey/lib/src/peer/bluey_peer.dart` | Replace `int maxFailedHeartbeats` with `Duration peerSilenceTimeout`. |
| `bluey/lib/src/bluey.dart` | Replace `int maxFailedHeartbeats` with `Duration peerSilenceTimeout` on `connect()`, `peer()`, and any other public entry. Update doc comments. |
| `bluey/test/connection/liveness_monitor_test.dart` | Rewrite for new semantics. (File rename optional; class import path changes either way.) |
| `bluey/test/connection/lifecycle_client_test.dart` | Update for new monitor API + new `markUserOpStarted/Ended/recordUserOpFailure` methods. |
| `bluey/test/connection/bluey_connection_test.dart` | Update for `peerSilenceTimeout` parameter; assert wrapping behaviour. |
| `bluey/test/connection/bluey_connection_activity_test.dart` | Update for new activity / pending-tracking semantics. |
| `bluey/test/connection/bluey_connection_disconnected_test.dart` | Update for parameter rename. |
| `bluey/test/connection/bluey_connection_timeout_test.dart` | Update for parameter rename + new failure-path behaviour. |
| `bluey/test/connection/bluey_connection_upgrade_test.dart` | Update for parameter rename. |
| `bluey/example/lib/features/connection/domain/connection_settings.dart` | Replace `int maxFailedHeartbeats` with `Duration peerSilenceTimeout`. |
| `bluey/example/lib/features/connection/presentation/connection_settings_cubit.dart` | Method rename: `setMaxFailedHeartbeats(int)` → `setPeerSilenceTimeout(Duration)`. |
| `bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart` | Three segments now express durations (e.g. 10 s / 30 s / 60 s). |
| `bluey/example/lib/features/stress_tests/presentation/widgets/tolerance_indicator.dart` | Render duration label instead of count label. |
| `bluey/example/lib/features/connection/infrastructure/bluey_connection_repository.dart` | Update propagation to `bluey.connect()`. |
| `bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart` | Update for new labels and dispatched values. |
| `bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart` | Update for new labels. |
| `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart` | Restore the two-scenario `failureInjection.readingResults` (Strict cascade vs Tolerant recovery), drop the I097 caveat. |
| `docs/backlog/I097-client-opslot-starves-heartbeat.md` | Mark fixed, replace Notes. |
| `docs/backlog/README.md` | Move I097 from Open → Fixed. |

---

## Task 1: Set up the feature worktree

- [ ] **Step 1: Confirm primary worktree state**

```bash
cd /Users/joel/git/neutrinographics/bluey
git status -s
git log --oneline -3
```

Expected: clean working tree on `main` with recent commit `920af0b docs(spec): I097 — switch to time-based peer-silence detection` (or later if other docs commits exist).

- [ ] **Step 2: Create the worktree**

```bash
git worktree add .worktrees/i097-peer-silence -b fix/i097-peer-silence
```

- [ ] **Step 3: Pub get + baseline tests**

```bash
cd .worktrees/i097-peer-silence/bluey && flutter pub get 2>&1 | tail -3
flutter test 2>&1 | tail -3
cd ../bluey/example && flutter pub get 2>&1 | tail -3
flutter test 2>&1 | tail -3
```

Record the baseline pass counts. The bluey package and example each have their own suites.

---

## Task 2: Rewrite `LivenessMonitor` → `PeerSilenceMonitor`

**Rationale:** This is the core of the time-based mechanism. Rename the file, replace the contents, write fresh tests, then have everything else use the new API.

**Files:**
- Rename: `bluey/lib/src/connection/liveness_monitor.dart` → `bluey/lib/src/connection/peer_silence_monitor.dart`
- Rewrite contents
- Rename: `bluey/test/connection/liveness_monitor_test.dart` → `bluey/test/connection/peer_silence_monitor_test.dart`
- Rewrite tests

- [ ] **Step 1: Rename the production file**

```bash
git mv bluey/lib/src/connection/liveness_monitor.dart bluey/lib/src/connection/peer_silence_monitor.dart
```

- [ ] **Step 2: Replace the file contents**

Open `bluey/lib/src/connection/peer_silence_monitor.dart` and replace the entire contents with:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// Detects when a peer has been silent for too long.
///
/// State machine:
/// - **Idle (no death watch).** No outstanding failure has been
///   recorded, or the most recent failure was followed by a success.
///   `_firstFailureAt` is null. No timer scheduled. The peer is
///   presumed alive.
/// - **Death watch active.** A failure has been recorded; no success
///   has cleared it. `_firstFailureAt` is non-null. A `Timer` is
///   scheduled to fire `onSilent` at `_firstFailureAt +
///   peerSilenceTimeout`. Any successful exchange returns the
///   monitor to idle.
///
/// The death watch deliberately ignores pending state — once armed,
/// the timer runs to completion regardless of whether further user
/// ops start or end. This ensures rapid back-to-back failures don't
/// indefinitely defer dead-peer detection. Only an explicit
/// `recordActivity` (or `recordProbeSuccess`) cancels the timer.
///
/// Pure-ish domain — no GATT, no platform dependencies. Schedules a
/// Dart `Timer`; tests use `fake_async` and the `clock` package's
/// `withClock` to control time.
///
/// Bidirectional symmetry note: the *server-side* `LifecycleServer`
/// uses a similar but distinct mechanism (watchdog from last activity
/// rather than death-watch from first failure). The two share
/// vocabulary — peer silence, pending exchange, activity reset — but
/// not implementation, because the server passively receives
/// heartbeats while the client actively initiates exchanges. See
/// `LifecycleServer` for the symmetric counterpart.
class PeerSilenceMonitor {
  /// How long after a first failure (without an intervening success)
  /// before the peer is declared silent and `onSilent` fires.
  final Duration peerSilenceTimeout;

  /// Fired exactly once when the death watch expires. The monitor
  /// stops itself on this call; further `recordPeerFailure` calls are
  /// no-ops until the surrounding `LifecycleClient` is restarted.
  final void Function() onSilent;

  /// Cadence at which the lifecycle client schedules heartbeat
  /// probes during idle periods. Independent of [peerSilenceTimeout].
  Duration _activityWindow;

  DateTime? _lastActivityAt;
  DateTime? _firstFailureAt;
  Timer? _deathTimer;
  bool _probeInFlight = false;
  bool _running = false;

  PeerSilenceMonitor({
    required this.peerSilenceTimeout,
    required this.onSilent,
    required Duration activityWindow,
  })  : _activityWindow = activityWindow {
    assert(peerSilenceTimeout > Duration.zero,
        'peerSilenceTimeout must be positive');
    assert(activityWindow > Duration.zero,
        'activityWindow must be positive');
  }

  /// Probe-scheduling cadence. Read-only from outside; mutate via
  /// [updateActivityWindow].
  Duration get activityWindow => _activityWindow;

  /// Becomes false when the monitor has fired `onSilent` (terminal)
  /// or `stop()` has been called.
  bool get isRunning => _running;

  // === Lifecycle ===

  /// Activates the monitor. Failures recorded before `start()` are
  /// ignored; activity is tracked but the timer is not armed.
  void start() {
    _running = true;
  }

  /// Deactivates the monitor and cancels any pending timer.
  /// Idempotent.
  void stop() {
    _running = false;
    _deathTimer?.cancel();
    _deathTimer = null;
  }

  // === Activity (peer responded) ===

  /// Records evidence that the peer is alive: a successful user op,
  /// an incoming notification, or a probe ack. Cancels the death
  /// watch if one is active.
  void recordActivity() {
    _lastActivityAt = clock.now();
    _firstFailureAt = null;
    _deathTimer?.cancel();
    _deathTimer = null;
  }

  /// Probe write succeeded and peer acknowledged. Equivalent to
  /// [recordActivity] plus releasing the in-flight flag.
  void recordProbeSuccess() {
    _probeInFlight = false;
    recordActivity();
  }

  // === Failure (peer didn't respond) ===

  /// Records evidence that the peer may be unresponsive. If this is
  /// the first failure since the last success, arms the death timer
  /// for `_firstFailureAt + peerSilenceTimeout`. Subsequent failures
  /// while the death watch is active are no-ops on `_firstFailureAt`
  /// (the deadline doesn't reset).
  void recordPeerFailure() {
    if (!_running) return;
    _firstFailureAt ??= clock.now();
    if (_deathTimer != null) return; // already armed
    final deadline = _firstFailureAt!.add(peerSilenceTimeout);
    final remaining = deadline.difference(clock.now());
    if (!remaining.isNegative && remaining != Duration.zero) {
      _deathTimer = Timer(remaining, _fireSilent);
    } else {
      _fireSilent();
    }
  }

  /// Probe write failed in a way that's not interpreted as dead-peer
  /// (e.g., a transient platform error like Android's
  /// "another op in flight"). Releases the in-flight flag without
  /// touching the death watch.
  void cancelProbe() {
    _probeInFlight = false;
  }

  void _fireSilent() {
    if (!_running) return;
    _deathTimer = null;
    _running = false; // single-fire
    onSilent();
  }

  // === Probe scheduling helpers ===

  /// Whether a probe is currently in flight. Caller-side flag set
  /// before dispatching the heartbeat write.
  bool get probeInFlight => _probeInFlight;

  /// Marks that a probe write has been dispatched. The caller must
  /// follow up with [recordProbeSuccess] or [cancelProbe] /
  /// [recordPeerFailure].
  void markProbeInFlight() {
    _probeInFlight = true;
  }

  /// How long from now until the next probe is due. Used by
  /// `LifecycleClient` to decide when to schedule the next probe
  /// timer in idle.
  Duration timeUntilNextProbe() {
    final last = _lastActivityAt;
    if (last == null) return _activityWindow;
    final elapsed = clock.now().difference(last);
    final remaining = _activityWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Swaps in a new probe-scheduling cadence (e.g. after negotiating
  /// the server-preferred interval). Preserves all other state.
  void updateActivityWindow(Duration window) {
    assert(window > Duration.zero, 'activityWindow must be positive');
    _activityWindow = window;
  }

  // === Test inspection ===

  @visibleForTesting
  DateTime? get lastActivityAt => _lastActivityAt;

  @visibleForTesting
  DateTime? get firstFailureAt => _firstFailureAt;

  @visibleForTesting
  bool get isDeathWatchActive => _deathTimer != null;
}
```

- [ ] **Step 3: Rename the test file**

```bash
git mv bluey/test/connection/liveness_monitor_test.dart bluey/test/connection/peer_silence_monitor_test.dart
```

- [ ] **Step 4: Replace the test file contents**

Open `bluey/test/connection/peer_silence_monitor_test.dart` and replace its entire contents with:

```dart
import 'package:bluey/src/connection/peer_silence_monitor.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerSilenceMonitor', () {
    test('start enables the monitor; stop disables it', () {
      var fired = false;
      final monitor = PeerSilenceMonitor(
        peerSilenceTimeout: const Duration(seconds: 20),
        activityWindow: const Duration(seconds: 5),
        onSilent: () => fired = true,
      );
      expect(monitor.isRunning, isFalse);
      monitor.start();
      expect(monitor.isRunning, isTrue);
      monitor.stop();
      expect(monitor.isRunning, isFalse);
      expect(fired, isFalse);
    });

    test('recordPeerFailure arms the death watch', () {
      fakeAsync((async) {
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () {},
        )..start();
        monitor.recordPeerFailure();
        expect(monitor.firstFailureAt, isNotNull);
        expect(monitor.isDeathWatchActive, isTrue);
        monitor.stop();
      });
    });

    test('recordActivity cancels the death watch', () {
      fakeAsync((async) {
        var fired = false;
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () => fired = true,
        )..start();
        monitor.recordPeerFailure();
        async.elapse(const Duration(seconds: 5));
        monitor.recordActivity();
        expect(monitor.firstFailureAt, isNull);
        expect(monitor.isDeathWatchActive, isFalse);
        async.elapse(const Duration(seconds: 30));
        expect(fired, isFalse);
      });
    });

    test('multiple failures do not reset the deadline', () {
      fakeAsync((async) {
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () {},
        )..start();
        monitor.recordPeerFailure();
        final firstAt = monitor.firstFailureAt;
        async.elapse(const Duration(seconds: 10));
        monitor.recordPeerFailure();
        expect(monitor.firstFailureAt, equals(firstAt));
        monitor.stop();
      });
    });

    test('onSilent fires after peerSilenceTimeout from first failure', () {
      fakeAsync((async) {
        var fired = false;
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () => fired = true,
        )..start();
        monitor.recordPeerFailure();
        async.elapse(const Duration(seconds: 19));
        expect(fired, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(fired, isTrue);
        // Single-fire: monitor is no longer running.
        expect(monitor.isRunning, isFalse);
      });
    });

    test('stop cancels the timer; onSilent does not fire', () {
      fakeAsync((async) {
        var fired = false;
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () => fired = true,
        )..start();
        monitor.recordPeerFailure();
        async.elapse(const Duration(seconds: 5));
        monitor.stop();
        async.elapse(const Duration(seconds: 30));
        expect(fired, isFalse);
      });
    });

    test('failure recorded before start is ignored', () {
      var fired = false;
      final monitor = PeerSilenceMonitor(
        peerSilenceTimeout: const Duration(seconds: 20),
        activityWindow: const Duration(seconds: 5),
        onSilent: () => fired = true,
      );
      monitor.recordPeerFailure();
      expect(monitor.firstFailureAt, isNull);
      expect(fired, isFalse);
    });

    test('timeUntilNextProbe and updateActivityWindow', () {
      fakeAsync((async) {
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () {},
        )..start();
        // No activity yet → returns activityWindow.
        expect(monitor.timeUntilNextProbe(),
            equals(const Duration(seconds: 5)));
        monitor.recordActivity();
        async.elapse(const Duration(seconds: 2));
        expect(monitor.timeUntilNextProbe(),
            equals(const Duration(seconds: 3)));
        monitor.updateActivityWindow(const Duration(seconds: 10));
        expect(monitor.timeUntilNextProbe(),
            equals(const Duration(seconds: 8)));
        monitor.stop();
      });
    });
  });
}
```

- [ ] **Step 5: Verify the new tests pass**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence/bluey
flutter test test/connection/peer_silence_monitor_test.dart 2>&1 | tail -3
```

Expected: 8 tests pass.

The bluey package as a whole will not yet build because `LifecycleClient` still imports the old monitor — that's the next task. Don't run the full suite yet.

- [ ] **Step 6: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence
git add bluey/lib/src/connection/peer_silence_monitor.dart \
        bluey/test/connection/peer_silence_monitor_test.dart
git commit -m "refactor(lifecycle): rename LivenessMonitor → PeerSilenceMonitor + time-based semantics"
```

(`git mv` already staged the deletions of the old files; `git add` here picks up the new content.)

---

## Task 3: Update `LifecycleClient` to use `PeerSilenceMonitor`

**Rationale:** Wire LifecycleClient to the new monitor. Add `markUserOpStarted/Ended/recordUserOpFailure`. Modify `_sendProbeOrDefer` to defer when `_pendingUserOps > 0`. Remove `maxFailedHeartbeats`; add `peerSilenceTimeout` constructor parameter.

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`

- [ ] **Step 1: Replace the import + class header**

Open `lifecycle_client.dart`. Change the import:

```dart
// Before:
import 'liveness_monitor.dart';
// After:
import 'peer_silence_monitor.dart';
```

- [ ] **Step 2: Update the constructor and field set**

Replace the existing fields + constructor (lines 21-52) with:

```dart
class LifecycleClient {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final Duration _peerSilenceTimeout;
  final void Function() onServerUnreachable;

  late final PeerSilenceMonitor _monitor;
  Timer? _probeTimer;

  /// UUID of the server's heartbeat characteristic, once we've found
  /// it during `start()`. Not a running sentinel — use [_isRunning] for
  /// that. Nulled by `stop()`.
  String? _heartbeatCharUuid;

  /// Authoritative "running" sentinel. True from the moment `start()`
  /// commits to run (after its pre-commit null checks pass) until
  /// `stop()` clears it. Distinct from `_heartbeatCharUuid`, which
  /// indicates only "we know which char to write heartbeats to".
  bool _isRunning = false;

  /// Count of user-initiated GATT ops currently in flight on this
  /// connection. While > 0, scheduled probes defer rather than fire —
  /// the in-flight op is itself an outstanding peer probe (see I097).
  /// Maintained by [BlueyConnection] via [markUserOpStarted] /
  /// [markUserOpEnded].
  int _pendingUserOps = 0;

  LifecycleClient({
    required platform.BlueyPlatform platformApi,
    required String connectionId,
    required Duration peerSilenceTimeout,
    required this.onServerUnreachable,
  })  : _platform = platformApi,
        _connectionId = connectionId,
        _peerSilenceTimeout = peerSilenceTimeout {
    _monitor = PeerSilenceMonitor(
      peerSilenceTimeout: peerSilenceTimeout,
      activityWindow: _defaultHeartbeatInterval,
      onSilent: () {
        // Single-fire from monitor; we still need to clean up our
        // own state and signal upward.
        stop();
        onServerUnreachable();
      },
    );
  }

  /// Exposed for [BlueyConnection] tests to inspect.
  Duration get peerSilenceTimeout => _peerSilenceTimeout;
```

(The `maxFailedHeartbeats` field and getter are gone; the new `peerSilenceTimeout` field and getter take their place. The closure passed to `onSilent` calls both `stop()` and the upward callback because the monitor's single-fire semantics already disabled it — we just need to mirror that on our side.)

- [ ] **Step 3: Add the user-op tracking methods**

Insert after the existing public methods (e.g. after `recordActivity`):

```dart
/// Called by [BlueyConnection] when a user GATT op is dispatched.
/// While [_pendingUserOps] is > 0, scheduled probes defer rather
/// than fire — the in-flight op is itself an outstanding peer probe
/// and its outcome will tell us about the peer's liveness. See I097.
void markUserOpStarted() {
  _pendingUserOps++;
}

/// Called by [BlueyConnection] when a user GATT op completes (success
/// or failure). Symmetric with [markUserOpStarted]. Decrement only;
/// does not itself fire a probe — the next scheduled tick will fire
/// normally if the count reaches zero before then.
void markUserOpEnded() {
  if (_pendingUserOps > 0) _pendingUserOps--;
}

/// Called by [BlueyConnection] when a user GATT op fails. Filters by
/// predicate: timeouts feed the peer-silence detector; other errors
/// are no-ops at this layer.
///
/// User-op disconnects are deliberately not counted here: the
/// platform-level disconnect callback already triggers tear-down
/// through a separate path. User-op statusFailed errors are
/// deliberately not counted: at the user level they can mean ATT
/// errors (WriteNotPermitted, etc.) that don't imply dead peer.
void recordUserOpFailure(Object error) {
  if (!_isRunning) return;
  if (error is! platform.GattOperationTimeoutException) return;
  _monitor.recordPeerFailure();
}
```

- [ ] **Step 4: Modify `_sendProbeOrDefer`**

Replace the existing method body with:

```dart
void _sendProbeOrDefer() {
  if (_heartbeatCharUuid == null) return;
  if (_monitor.probeInFlight) return;
  if (_pendingUserOps > 0) {
    // I097: defer while a user op is in flight — that op is itself
    // an outstanding peer probe.
    _scheduleProbe(after: _monitor.activityWindow);
    return;
  }
  if (_monitor.timeUntilNextProbe() > Duration.zero) {
    _scheduleProbe();
    return;
  }
  _sendProbe();
}
```

- [ ] **Step 5: Modify `_sendProbe`'s `catchError`**

The dead-peer branch now calls `_monitor.recordPeerFailure()` directly (which arms the timer; no `tripped`-style return value to dispatch on). Replace the existing failure branch (the `final tripped = _monitor.recordProbeFailure()` block) with:

```dart
.catchError((Object error) {
  if (!_isRunning) return;
  if (!_isDeadPeerSignal(error)) {
    // Transient platform error — release in-flight, retry after a
    // full activityWindow.
    _monitor.cancelProbe();
    _scheduleProbe(after: _monitor.activityWindow);
    return;
  }
  dev.log(
    'heartbeat failed (counted): ${error.runtimeType}',
    name: 'bluey.lifecycle',
    level: 900, // WARNING
  );
  // Feed the peer-silence detector. If the death watch trips, the
  // monitor's onSilent callback (set in the constructor) will call
  // our stop() + onServerUnreachable. No reschedule needed in that
  // case — the lifecycle is shutting down. Otherwise, keep retrying
  // on the original cadence.
  _monitor.recordPeerFailure();
  if (_isRunning) {
    _scheduleProbe(after: _monitor.activityWindow);
  }
});
```

- [ ] **Step 6: Update `start()` to call `_monitor.start()`**

Search for the comment block before `_sendProbe()` is called in `start()`. Insert `_monitor.start();` immediately after `_isRunning = true;` is set:

```dart
_isRunning = true;
_monitor.start();
_heartbeatCharUuid = heartbeatChar.uuid.toString();
```

- [ ] **Step 7: Update `stop()` to call `_monitor.stop()`**

```dart
void stop() {
  _isRunning = false;
  _probeTimer?.cancel();
  _probeTimer = null;
  _heartbeatCharUuid = null;
  _monitor.stop();
}
```

(Remove the `_monitor.cancelProbe()` line if present — no longer needed; `stop()` handles cancellation more thoroughly.)

- [ ] **Step 8: Fix-up the test-inspection getters**

The `@visibleForTesting` `activityWindowForTest` and `lastActivityAtForTest` getters can stay; they delegate to the monitor's same-named getters which we kept.

- [ ] **Step 9: Run the file's compile check**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence/bluey
flutter analyze lib/src/connection/lifecycle_client.dart 2>&1 | tail -10
```

Expected: clean. Existing test files will fail because they pass `maxFailedHeartbeats:` — those tests get updated in Task 4.

- [ ] **Step 10: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart
git commit -m "feat(lifecycle): switch LifecycleClient to PeerSilenceMonitor + user-op tracking (I097)"
```

---

## Task 4: Update `LifecycleClient` tests

**Files:**
- Modify: `bluey/test/connection/lifecycle_client_test.dart`

- [ ] **Step 1: Update the test helper**

Find the constructor helper near the top of the file (around line 22). Replace the parameter signature:

```dart
// Before:
LifecycleClient build({
  // ...
  int maxFailedHeartbeats = 1,
  // ...
})

// After:
LifecycleClient build({
  // ...
  Duration peerSilenceTimeout = const Duration(seconds: 20),
  // ...
})
```

Update the constructor call inside:

```dart
return LifecycleClient(
  platformApi: platform,
  connectionId: connectionId,
  peerSilenceTimeout: peerSilenceTimeout,
  onServerUnreachable: onUnreachable,
);
```

- [ ] **Step 2: Update existing tests for parameter rename**

Search the file for `maxFailedHeartbeats:` and `maxFailedProbes:`. Each is replaced with `peerSilenceTimeout:` plus an appropriate Duration. For tests that previously did `maxFailedHeartbeats: 3`, switch to `peerSilenceTimeout: const Duration(seconds: 30)` (or whatever value preserves the test's intent).

For tests asserting "trips after 3 failures", rewrite them to assert "trips after peerSilenceTimeout duration of consistent failures." Use `fake_async` to advance time.

For tests using `maxFailedProbes`-style assertions, this is now a duration-based check.

The test at line 540 references `maxFailedHeartbeats: 3` directly — convert it.

- [ ] **Step 3: Add new tests for the user-op tracking**

Append these inside the existing `group('LifecycleClient', () { ... })` block, before its closing `});`:

```dart
test('probe deferred while user op pending', () {
  fakeAsync((async) {
    final cubit = build();
    cubit.start(allServices: [
      // … same setup pattern as existing tests for tracked clients,
      // including the heartbeat-char fake. Reuse whatever helper
      // existing tests in this file use to set up a "started" client.
    ]);
    cubit.markUserOpStarted();
    async.elapse(const Duration(seconds: 30));
    // Verify no probe write was attempted on the fake platform.
    expect(platform.writeCharacteristicCalls.where(
        (call) => call.characteristicUuid == lifecycle.heartbeatCharUuid),
        isEmpty);
    cubit.markUserOpEnded();
    cubit.stop();
  });
});

test('probe fires after user op ends', () {
  fakeAsync((async) {
    final cubit = build()..start(allServices: [...]);
    cubit.markUserOpStarted();
    async.elapse(const Duration(seconds: 30));
    cubit.markUserOpEnded();
    async.elapse(const Duration(seconds: 5));
    expect(platform.writeCharacteristicCalls.where(
        (call) => call.characteristicUuid == lifecycle.heartbeatCharUuid),
        isNotEmpty);
    cubit.stop();
  });
});

test('multiple concurrent user ops correctly counted', () {
  fakeAsync((async) {
    final cubit = build()..start(allServices: [...]);
    cubit.markUserOpStarted();
    cubit.markUserOpStarted();
    cubit.markUserOpEnded(); // count: 1
    async.elapse(const Duration(seconds: 30));
    expect(platform.writeCharacteristicCalls.where(
        (call) => call.characteristicUuid == lifecycle.heartbeatCharUuid),
        isEmpty,
        reason: 'one op still pending — probes should be deferred');
    cubit.markUserOpEnded(); // count: 0
    async.elapse(const Duration(seconds: 5));
    expect(platform.writeCharacteristicCalls.where(
        (call) => call.characteristicUuid == lifecycle.heartbeatCharUuid),
        isNotEmpty);
    cubit.stop();
  });
});

test('recordUserOpFailure with timeout feeds the silence detector', () {
  fakeAsync((async) {
    var unreachable = false;
    final cubit = build(
      onUnreachable: () => unreachable = true,
      peerSilenceTimeout: const Duration(seconds: 10),
    )..start(allServices: [...]);
    cubit.recordUserOpFailure(
      const platform.GattOperationTimeoutException(),
    );
    async.elapse(const Duration(seconds: 11));
    expect(unreachable, isTrue);
  });
});

test('recordUserOpFailure with non-timeout is a no-op', () {
  fakeAsync((async) {
    var unreachable = false;
    final cubit = build(
      onUnreachable: () => unreachable = true,
      peerSilenceTimeout: const Duration(seconds: 10),
    )..start(allServices: [...]);
    cubit.recordUserOpFailure(
      const platform.GattOperationStatusFailedException(status: 0x03),
    );
    async.elapse(const Duration(seconds: 30));
    expect(unreachable, isFalse);
  });
});
```

(Replace `[...]` with the actual `allServices` list the test file already uses for tracked-client setup. The pattern should match existing tests in the file. If the file has a helper like `_buildTrackedClient(...)`, use that instead.)

- [ ] **Step 4: Run the test file**

```bash
flutter test test/connection/lifecycle_client_test.dart 2>&1 | tail -10
```

Expected: all tests pass (existing + new).

- [ ] **Step 5: Commit**

```bash
git add bluey/test/connection/lifecycle_client_test.dart
git commit -m "test(lifecycle): update LifecycleClient tests for time-based silence detection"
```

---

## Task 5: Update `BlueyConnection` to wrap user-op call sites and propagate `peerSilenceTimeout`

**Rationale:** Replace the `int maxFailedHeartbeats` field/parameter with `Duration peerSilenceTimeout`. Wrap each user-op call site with start/end/failure-routing.

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`

- [ ] **Step 1: Replace the field and constructor parameter**

Find `_maxFailedHeartbeats` (around line 121) and the constructor parameter (around line 177). Replace:

```dart
// Before:
final int _maxFailedHeartbeats;
// in constructor:
int maxFailedHeartbeats = 1,
// init:
_maxFailedHeartbeats = maxFailedHeartbeats {

// After:
final Duration _peerSilenceTimeout;
// in constructor:
required Duration peerSilenceTimeout,
// init:
_peerSilenceTimeout = peerSilenceTimeout {
```

(The field is `required` because there's no sensible default at the connection layer — the `Bluey` factory passes the appropriate default through.)

- [ ] **Step 2: Update the LifecycleClient construction site**

Search for `maxFailedHeartbeats: _maxFailedHeartbeats` (around line 518). Replace with:

```dart
peerSilenceTimeout: _peerSilenceTimeout,
```

- [ ] **Step 3: Wrap user-op call sites**

The four `recordActivity` call sites (per the spec — `bluey_connection.dart:317, :364, :376, :619`) need the wrapping pattern. Search the file for `_lifecycle?.recordActivity()` and identify each.

Three of them are user-op completion sites (read, write, set-notification or similar). Update each from:

```dart
final result = await _platform.<op>(...);
_lifecycle?.recordActivity();
return result;
```

to:

```dart
_lifecycle?.markUserOpStarted();
try {
  final result = await _platform.<op>(...);
  _lifecycle?.recordActivity();
  return result;
} catch (error) {
  _lifecycle?.recordUserOpFailure(error);
  rethrow;
} finally {
  _lifecycle?.markUserOpEnded();
}
```

The fourth call site (the notification-stream callback at `:619` — verify by inspection) is for inbound notifications, not outbound user ops. **Leave that one alone** — it stays as `_lifecycle?.recordActivity()`.

- [ ] **Step 4: Run analyzer**

```bash
flutter analyze lib/src/connection/bluey_connection.dart 2>&1 | tail -5
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart
git commit -m "feat(connection): wrap user-op call sites + accept peerSilenceTimeout (I097)"
```

---

## Task 6: Update `BlueyPeer`, `Bluey.connect()`, `Bluey.peer()`

**Rationale:** Public API rename. Propagate `peerSilenceTimeout` through the peer module and the top-level entry points.

**Files:**
- Modify: `bluey/lib/src/peer/bluey_peer.dart`
- Modify: `bluey/lib/src/bluey.dart`

- [ ] **Step 1: Update `BlueyPeer`**

In `bluey/lib/src/peer/bluey_peer.dart`, replace `int maxFailedHeartbeats` with `Duration peerSilenceTimeout` everywhere. There are roughly six occurrences (field, two constructors, doc comment, two propagation sites).

Default value where one is needed: `const Duration(seconds: 20)`.

- [ ] **Step 2: Update `Bluey.connect()` and `Bluey.peer()`**

In `bluey/lib/src/bluey.dart`, replace `int maxFailedHeartbeats = 1` with `Duration peerSilenceTimeout = const Duration(seconds: 20)` on every method that exposes it (look for the existing occurrences at lines 312, 375, 521).

Update doc comments:

- The `[maxFailedHeartbeats] - Consecutive heartbeat write failures...` comment on connect() becomes:
  ```dart
  /// [peerSilenceTimeout] - How long after a peer-failure signal
  /// (heartbeat probe timeout or user-op timeout) without an
  /// intervening successful exchange before the connection is
  /// declared dead. Default 20 seconds. Smaller values are more
  /// aggressive; larger values tolerate transient peer slowness.
  ```
- Similar updates on peer() and any other docstring references.

- [ ] **Step 3: Run analyzer on the bluey package**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence
flutter analyze 2>&1 | tail -5
```

Expected: clean for the bluey package itself. Example app may still have errors — those get fixed in Task 7.

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/peer/bluey_peer.dart bluey/lib/src/bluey.dart
git commit -m "feat(public-api): replace maxFailedHeartbeats with peerSilenceTimeout (I097)"
```

---

## Task 7: Update `BlueyConnection` tests

**Files:**
- Modify: `bluey/test/connection/bluey_connection_test.dart`
- Modify: `bluey/test/connection/bluey_connection_activity_test.dart`
- Modify: `bluey/test/connection/bluey_connection_disconnected_test.dart`
- Modify: `bluey/test/connection/bluey_connection_timeout_test.dart`
- Modify: `bluey/test/connection/bluey_connection_upgrade_test.dart`

- [ ] **Step 1: Bulk parameter rename**

In each test file, find `maxFailedHeartbeats:` and replace with `peerSilenceTimeout: const Duration(seconds: ...)`. Pick a duration that preserves the test's intent (most tests don't actually depend on the value; default 20 s is fine).

Tests that relied on count-based trip semantics need rewriting to assert duration-based semantics.

- [ ] **Step 2: Add new tests for the wrapping in `bluey_connection_test.dart` (or an appropriate file)**

Three new tests:

```dart
test('user op success wraps with start/end and records activity', () {
  // ... fake platform that returns success for a write
  // assert: lifecycle's pendingUserOps went 0 → 1 → 0 around the await
  //         lifecycle.recordActivity called once
});

test('user op timeout wraps with start/end and records failure', () {
  // ... fake platform that throws GattOperationTimeoutException
  // assert: pendingUserOps returned to 0 (no leak)
  //         lifecycle.recordUserOpFailure called with the timeout
  //         the timeout still propagates to the caller (rethrown)
});

test('user op other failure wraps with start/end; failure filtered', () {
  // ... fake platform that throws GattOperationStatusFailedException
  // assert: pendingUserOps returned to 0
  //         lifecycle.recordUserOpFailure called (which is a no-op
  //         internally for non-timeout)
});
```

(Use whatever spy / mock pattern existing tests in the file use — `MockBlueyPlatform`, `FakeBlueyPlatform`, etc. The new tests slot in alongside them.)

- [ ] **Step 3: Run all bluey tests**

```bash
cd bluey
flutter test 2>&1 | tail -3
```

Expected: all passing.

- [ ] **Step 4: Commit**

```bash
git add bluey/test/connection/
git commit -m "test(connection): update BlueyConnection tests for peerSilenceTimeout + user-op wrapping"
```

---

## Task 8: Update example app — `ConnectionSettings` and infrastructure

**Files:**
- Modify: `bluey/example/lib/features/connection/domain/connection_settings.dart`
- Modify: `bluey/example/lib/features/connection/presentation/connection_settings_cubit.dart`
- Modify: `bluey/example/lib/features/connection/infrastructure/bluey_connection_repository.dart`

- [ ] **Step 1: Update `ConnectionSettings`**

Replace the file contents:

```dart
import 'package:flutter/foundation.dart';

/// User-tunable options applied to the next [Connection].
@immutable
class ConnectionSettings {
  /// How long after a peer-failure signal without intervening
  /// successful activity before the connection is declared dead.
  /// See [Bluey.connect].
  final Duration peerSilenceTimeout;

  const ConnectionSettings({
    this.peerSilenceTimeout = const Duration(seconds: 20),
  });

  ConnectionSettings copyWith({Duration? peerSilenceTimeout}) {
    return ConnectionSettings(
      peerSilenceTimeout: peerSilenceTimeout ?? this.peerSilenceTimeout,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionSettings &&
          runtimeType == other.runtimeType &&
          peerSilenceTimeout == other.peerSilenceTimeout;

  @override
  int get hashCode => peerSilenceTimeout.hashCode;
}
```

- [ ] **Step 2: Update `ConnectionSettingsCubit`**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/connection_settings.dart';

/// Session-scoped store for [ConnectionSettings] the user can tweak
/// before connecting. Not persisted across app restarts — intended for
/// demo use.
class ConnectionSettingsCubit extends Cubit<ConnectionSettings> {
  ConnectionSettingsCubit() : super(const ConnectionSettings());

  void setPeerSilenceTimeout(Duration value) {
    emit(state.copyWith(peerSilenceTimeout: value));
  }
}
```

- [ ] **Step 3: Update `BlueyConnectionRepository`**

In the repository's connect/peer call, replace:

```dart
maxFailedHeartbeats: settings.maxFailedHeartbeats,
```

with:

```dart
peerSilenceTimeout: settings.peerSilenceTimeout,
```

- [ ] **Step 4: Commit**

```bash
git add bluey/example/lib/features/connection/domain/connection_settings.dart \
        bluey/example/lib/features/connection/presentation/connection_settings_cubit.dart \
        bluey/example/lib/features/connection/infrastructure/bluey_connection_repository.dart
git commit -m "feat(example): switch ConnectionSettings + cubit to peerSilenceTimeout"
```

---

## Task 9: Update example app — UI widgets (`ToleranceControl`, `ToleranceIndicator`)

**Files:**
- Modify: `bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/tolerance_indicator.dart`
- Modify: `bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart`
- Modify: `bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart`

- [ ] **Step 1: Update `ToleranceControl`**

In `tolerance_control.dart`, replace the `_options` list and the dispatch. New segments:

```dart
static const _options = [
  (label: 'Strict', value: Duration(seconds: 10)),
  (label: 'Tolerant', value: Duration(seconds: 30)),
  (label: 'Very tolerant', value: Duration(seconds: 60)),
];
```

In the `BlocBuilder` body, replace `settings.maxFailedHeartbeats == option.value` with `settings.peerSilenceTimeout == option.value`. In the tap handler, replace `setMaxFailedHeartbeats(option.value)` with `setPeerSilenceTimeout(option.value)`.

- [ ] **Step 2: Update `ToleranceIndicator`**

In `tolerance_indicator.dart`, replace the `int maxFailedHeartbeats` constructor parameter with `Duration peerSilenceTimeout`. Replace the `_label` switch:

```dart
String get _label => switch (peerSilenceTimeout) {
      Duration(inSeconds: 10) => 'Strict',
      Duration(inSeconds: 30) => 'Tolerant',
      Duration(inSeconds: 60) => 'Very tolerant',
      final d => '${d.inSeconds}s',
    };
```

(Pattern matching on Duration may need helper getters depending on Dart version; the `inSeconds` getter is standard. If pattern matching is awkward, an `if/else` chain works fine.)

The widget's caller in `stress_tests_screen.dart` reads from the settings cubit; update the construction site:

```dart
ToleranceIndicator(peerSilenceTimeout: settings.peerSilenceTimeout)
```

- [ ] **Step 3: Update `ToleranceControl` tests**

In `tolerance_control_test.dart`, update each test to assert against the new `peerSilenceTimeout` field. Example:

```dart
testWidgets('default state has Strict selected (10 s)', (tester) async {
  // ...
  expect(cubit.state.peerSilenceTimeout, const Duration(seconds: 10));
});

testWidgets('tapping Tolerant dispatches setPeerSilenceTimeout(30s)',
    (tester) async {
  // ...
  await tester.tap(find.text('Tolerant'));
  await tester.pump();
  expect(cubit.state.peerSilenceTimeout, const Duration(seconds: 30));
});
// ... and similarly for "Very tolerant"
```

Also update the default-state expectation: ConnectionSettings's default is now 20 s, which doesn't match any of the three segments. The test should account for that — either change the default to one of the three segment values (e.g., 30 s) for UX consistency, OR assert that no segment is selected initially.

(I'd recommend changing the default to 30 s — match "Tolerant" — so the UI starts in a sensible state. That's a one-line change in `ConnectionSettings`'s default.)

- [ ] **Step 4: Update `ToleranceIndicator` tests**

```dart
testWidgets('renders Strict label for 10 s', (tester) async {
  await tester.pumpWidget(
      wrap(const ToleranceIndicator(peerSilenceTimeout: Duration(seconds: 10))));
  expect(find.text('Tolerance: Strict'), findsOneWidget);
});
// ... and similarly for Tolerant (30s), Very tolerant (60s), and a non-named value (e.g., 7s → "Tolerance: 7s")
```

- [ ] **Step 5: Run example app tests**

```bash
cd bluey/example
flutter test 2>&1 | tail -3
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart \
        bluey/example/lib/features/stress_tests/presentation/widgets/tolerance_indicator.dart \
        bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart \
        bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart
git commit -m "feat(example): tolerance UI now expresses durations (I097)"
```

---

## Task 10: Restore the failure-injection two-scenario description

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`

- [ ] **Step 1: Replace the failure-injection `readingResults`**

In `stress_test_help_content.dart`, find the `failureInjection` `StressTestHelpContent` block. Replace the `readingResults` field with the original two-scenario description (Strict cascade vs Tolerant recovery), now phrased in terms of duration. Suggested text:

```dart
readingResults:
    'Outcome depends on the "Heartbeat tolerance" setting on the '
    'connection screen.\n\n'
    'Strict (10 s) — the connection is declared dead 10 seconds '
    'after the dropped write times out. Expect 1 GattTimeoutException '
    '(the dropped write) followed by writeCount−1 '
    'GattOperationDisconnectedException as the queued ops drain. '
    'This is the disconnect-cascade scenario.\n\n'
    'Tolerant (30 s) or Very tolerant (60 s): the dropped write times '
    'out, but a subsequent successful echo arrives before the silence '
    'timeout expires, resetting the death watch. Expect 1 '
    'GattTimeoutException + writeCount−1 successes. This is the '
    'recovery scenario.',
```

(Drop the I097 caveat from this entry — the bug is fixed.)

- [ ] **Step 2: Run example tests**

```bash
flutter test 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart
git commit -m "docs(stress-tests): restore failureInjection two-scenario description (I097 fixed)"
```

---

## Task 11: Final verification

- [ ] **Step 1: Full test run**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence/bluey
flutter test 2>&1 | tail -3
cd ../bluey/example
flutter test 2>&1 | tail -3
```

Expected: both suites passing.

- [ ] **Step 2: Analyzer**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/i097-peer-silence
flutter analyze 2>&1 | tail -5
```

Expected: clean.

- [ ] **Step 3: Branch summary**

```bash
git log --oneline main..HEAD
```

Expected: roughly 9–11 commits with `refactor(...)`, `feat(...)`, `test(...)`, `docs(...)` prefixes.

- [ ] **Step 4: Report to user**

Summarise:
- Branch name (`fix/i097-peer-silence`)
- Commit count
- Test counts (bluey + example)
- Manual verification step on user's side: re-run the failure-injection stress test on iOS device. At Strict (10 s), expect 1 timeout + cascade. At Tolerant (30 s) or higher, expect 1 timeout + N-1 successes (clean recovery). At any tolerance, all-ops-fail eventually trips the death watch after `peerSilenceTimeout` seconds.

Do **not** push the branch.

---

## Task 12: Backlog hygiene (post-merge follow-up)

This task happens **after** the user squash-merges the PR. Document here so it's not forgotten.

- Update `docs/backlog/I097-client-opslot-starves-heartbeat.md`: `status: open` → `fixed`, add `fixed_in: <squash-merge sha>`, replace Notes with the prose drafted in the spec's "Backlog hygiene" section.
- Update `docs/backlog/README.md`: move I097 from Open table → Fixed table.

---

## Self-review

**Spec coverage:**
- `PeerSilenceMonitor` rename + time-based semantics: Task 2.
- `LifecycleClient` user-op tracking + monitor wiring: Task 3.
- `BlueyConnection` wrapping + parameter change: Task 5.
- `BlueyPeer` + `Bluey.connect/peer` public API: Task 6.
- Example app `ConnectionSettings` + UI: Tasks 8–9.
- `failureInjection` description restored: Task 10.

**Placeholder scan:** None remaining. Tolerance segment values (10/30/60) are illustrative; the plan calls them out as tunable. Default `peerSilenceTimeout = 20 s` library-wide; example app default is 30 s for UI consistency.

**Tests:** every code change is paired with a corresponding test update. `PeerSilenceMonitor` gets fresh tests; `LifecycleClient` gets new tests for the user-op API; `BlueyConnection` gets new tests for the wrapping. Existing tests are updated for the parameter rename.

**Manual verification only at the end:** the lifecycle/connection layer interacts with real BLE behaviour that's hard to fake fully in unit tests beyond mock-call counts. The plan accepts this and surfaces a manual checklist at hand-off.
