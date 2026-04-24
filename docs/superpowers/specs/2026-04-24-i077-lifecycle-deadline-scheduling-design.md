# Client-Side Lifecycle: Deadline-Driven Probe Scheduling (I077)

**Status:** proposed
**Date:** 2026-04-24
**Scope:** `bluey` package — `LivenessMonitor` + `LifecycleClient` only. No platform-interface change, no native change, no server-side change, no protocol change.
**Backlog entry:** [I077](../../backlog/I077-lifecycle-client-disconnect-storm.md).

## Problem

During manual verification of the I020+I021 fix (Android server + iOS client), the server-side log showed the client cycling `Client connected` / `Client disconnected` approximately every 10 seconds during heartbeat activity. The BLE link stayed up, and application reads/writes continued working. Only the Dart lifecycle layer was reporting the flapping.

Investigation with targeted instrumentation produced definitive evidence:

1. iOS client `_sendProbe` logs showed heartbeat writes at 10-second intervals — not the intended 5-second interval (server interval ÷ 2 default).
2. Android server `heartbeat-timer FIRED` logs appeared between heartbeats, firing `onClientGone` just before each next heartbeat arrived.
3. Every `_handleClientDisconnected` event was `source=lifecycle` (timer expiry), never `source=native` (real BLE disconnect).
4. Every write from iOS to `b1e70002` carried `value=0x01` — pure heartbeats, no disconnect commands.

## Root cause

`LifecycleClient._beginHeartbeat` sets both the `Timer.periodic` tick interval and the `LivenessMonitor` activity window to the same `interval` value:

```dart
void _beginHeartbeat(Duration interval) {
  _monitor.updateActivityWindow(interval);       // activityWindow = 5s
  _probeTimer = Timer.periodic(interval, (_) => _tick());  // ticks every 5s
}
```

`LivenessMonitor.shouldSendProbe()` uses a `>=` boundary check:

```dart
return _now().difference(last) >= _activityWindow;
```

When `Timer.periodic` drifts slightly early — common in Dart, where scheduled timers routinely fire with sub-millisecond jitter — the check `now - lastActivity >= 5000ms` returns `false` (because `now - lastActivity` is ~4998ms). The tick is skipped. The probe fires at the *next* tick 5 seconds later. Observed effect: heartbeats go out every 10 seconds instead of every 5.

Server's timer deadline is `interval = 10 seconds`. When the client heartbeats at 10-second intervals (racing the server deadline), the server's timer fires first → `onClientGone` → disconnect event. The in-transit heartbeat arrives ~100ms later → `onHeartbeatReceived` → `_trackClientIfNeeded` → reconnect event. Loop.

The design comment on `shouldSendProbe()` says `>=` was chosen deliberately to "beat the server's matching per-client timeout." That reasoning assumes tick interval < activity window — but the code sets them equal, eliminating the margin the `>=` was supposed to give.

## Non-goals

- **Not touching the protocol.** The server's reported interval still means "my timer deadline," and the client still halves it for heartbeats. Any change to that semantic is a protocol change; out of scope.
- **Not changing the server timer margin.** After the client fix, client heartbeats fire every `activityWindow = interval ÷ 2` exactly. Server timer stays at `interval`. The inherent 2× margin is sufficient; adding a multiplier on the server side would duplicate the ratio on both sides with no independent benefit.
- **Not changing `maxFailedHeartbeats`.** The default of 1 is aggressive, but applications already control it via `bluey.connect()` / `bluey.peer()`. Leave policy to callers.
- **Not adding exponential backoff, circuit breakers, or separate transient-vs-dead-peer retry cadences.** Current behavior doesn't have these; adding them is out of scope.

## Decisions locked during brainstorming

1. **Fix shape:** deadline-driven one-shot scheduling (option C in the brainstorming). Replace polling `Timer.periodic` + `shouldSendProbe()` query with an event-driven `Timer` rescheduled at every state transition that shifts the probe deadline.
2. **Server side:** unchanged.
3. **Transient error retry interval:** full `activityWindow`. Matches the success case, keeps code simple. The specific transient errors this catches (e.g. `op-in-flight` from the Android GATT queue) resolve on their own regardless of retry cadence.

## Architecture

All changes inside `bluey/lib/src/connection/liveness_monitor.dart` and `bluey/lib/src/connection/lifecycle_client.dart`.

### `LivenessMonitor` — state tracker (unchanged role)

Still a pure domain class. No BLE, async, or platform dependencies. No timer management.

**API changes:**

- **Removed:** `bool shouldSendProbe()`. Its two sub-responsibilities split:
  - "Is a probe in flight?" → new `bool get probeInFlight`.
  - "How close to the deadline?" → new `Duration timeUntilNextProbe()`.

- **Added: `Duration timeUntilNextProbe()`**

  ```dart
  /// How long from now until the next probe is due. Returns [Duration.zero]
  /// if the deadline is already past (caller should probe immediately).
  /// Returns [activityWindow] if no activity has been recorded yet.
  Duration timeUntilNextProbe() {
    final last = _lastActivityAt;
    if (last == null) return _activityWindow;
    final elapsed = _now().difference(last);
    final remaining = _activityWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
  ```

- **Added: `bool get probeInFlight`** — trivial getter exposing existing state.

- **Unchanged:** `recordActivity()`, `markProbeInFlight()`, `recordProbeSuccess()`, `recordProbeFailure() → bool`, `cancelProbe()`, `updateActivityWindow()`, `maxFailedProbes`, `activityWindow` getter.

- **Docstring update:** `recordActivity()` now has a caller contract side-effect — the client must reschedule its timer after calling this.

### `LifecycleClient` — timer ownership + scheduling decisions

`_probeTimer` stays `Timer?` but becomes a one-shot, rescheduled at every state transition instead of firing repeatedly.

**Removed:**

- `_tick()` method.
- `Timer.periodic(...)` in `_beginHeartbeat`.

**Added helpers:**

```dart
/// Cancel any pending scheduled probe and schedule a new one.
///
/// If [after] is null (default), the delay is computed from the monitor's
/// current deadline — appropriate after a probe success or after external
/// activity shifts the deadline forward.
///
/// If [after] is non-null, the delay is that explicit duration —
/// appropriate after a probe failure, where the monitor's deadline would
/// have already elapsed (producing an immediate-retry cadence that
/// diverges from the current polling behavior). Failure paths pass
/// [activityWindow] to preserve the roughly-one-probe-per-window
/// rate-limit that polling produced implicitly.
///
/// No-op if the client has been stopped.
void _scheduleProbe({Duration? after}) {
  if (_heartbeatCharUuid == null) return;
  _probeTimer?.cancel();
  final delay = after ?? _monitor.timeUntilNextProbe();
  _probeTimer = Timer(delay, _sendProbeOrDefer);
}

/// Timer callback. Sends a probe unless one is already in flight (in
/// which case the in-flight probe's completion handler will reschedule).
/// Re-verifies the deadline in case recordActivity fired concurrently.
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

**Changed methods:**

- `_beginHeartbeat(Duration interval)` — now just: log, `updateActivityWindow(interval)`, `_scheduleProbe()`.
- `_sendProbe()` — `.then` and `.catchError` branches each end with exactly one of: `_scheduleProbe()` (success — uses monitor's deadline), `_scheduleProbe(after: activityWindow)` (any non-trip failure — explicit delay to avoid immediate-retry), or `stop()` (threshold trip — no reschedule).
- `recordActivity()` — after `_monitor.recordActivity()`, calls `_scheduleProbe()` so the deadline shifts forward immediately (rather than at the next tick).

**Unchanged:**

- `start()`, `sendDisconnectCommand()`, `stop()`, `_isDeadPeerSignal`.
- `_monitor.markProbeInFlight()` timing (before `writeCharacteristic`).

## Data flow

Seven events touch the probe timer. Each resolves to exactly one action: `_scheduleProbe()` (arms a new one-shot, superseding any prior timer) or `stop()` (cancels permanently).

| Event | Action |
|---|---|
| `start()` → first `_sendProbe()` then `_beginHeartbeat()` | `_scheduleProbe()` after `updateActivityWindow` |
| Timer fires, not in flight, deadline past | `_sendProbe()` → completion reschedules |
| Timer fires, in flight | no-op; in-flight completion reschedules |
| Timer fires, deadline in future (activity happened) | `_scheduleProbe()` |
| Probe success (`.then`) | `recordProbeSuccess` + `_scheduleProbe()` (monitor deadline = `activityWindow` from now) |
| Probe transient failure (`.catchError`, not dead-peer) | `cancelProbe` + `_scheduleProbe(after: activityWindow)` |
| Probe dead-peer under threshold | `recordProbeFailure` + `_scheduleProbe(after: activityWindow)` |
| Probe dead-peer trips threshold | `recordProbeFailure` + `stop()` + `onServerUnreachable()` — no reschedule |
| `recordActivity()` (external, from user op) | `recordActivity` + `_scheduleProbe()` (monitor deadline = `activityWindow` from now) |
| `stop()` (external) | cancel timer, null out `_heartbeatCharUuid` |

**Invariant:** at every instant in the client's lifetime, there is at most one `_probeTimer` armed. Every scheduling point cancels before arming. `stop()` cancels without rearming. After `stop()`, any subsequent `_scheduleProbe()` or `_sendProbeOrDefer` call is a no-op (guarded on `_heartbeatCharUuid == null`).

## Error handling

Three failure categories, all resolved in `_sendProbe`'s `.catchError`:

**Transient platform errors (not dead-peer):** e.g. `op-in-flight` from the Android GATT queue, Pigeon-level errors.
- `_monitor.cancelProbe()` — releases in-flight flag, no failure count.
- `_scheduleProbe()` — retry at `activityWindow`.

**Dead-peer signals under threshold:** `GattOperationTimeoutException`, `GattOperationDisconnectedException`, `GattOperationStatusFailedException`.
- `_monitor.recordProbeFailure()` returns `false` — counter incremented.
- `dev.log` WARNING.
- `_scheduleProbe()` — retry at `activityWindow`.

**Dead-peer signals that trip threshold:** same exception types, but `recordProbeFailure` returns `true`.
- `dev.log` SEVERE.
- `stop()` — cancels timer, clears `_heartbeatCharUuid`. Terminal state.
- `onServerUnreachable()` — caller disconnects.
- No reschedule. Any lingering Pigeon callbacks find `_heartbeatCharUuid == null` and no-op.

**Verifiable invariant under error paths:** every probe completion path chooses exactly one of `_scheduleProbe()` or `stop()`. Never both, never neither.

## Testing strategy

TDD order. All timer-sensitive tests use fake time (`FakeAsync` or injected `clock.now`).

### Layer 1: `LivenessMonitor` unit tests

File: `bluey/test/connection/liveness_monitor_test.dart`.

Removed: existing `shouldSendProbe()` tests.

Added:
1. `timeUntilNextProbe` returns `activityWindow` when no activity recorded yet.
2. `timeUntilNextProbe` returns `activityWindow` immediately after `recordActivity()`.
3. `timeUntilNextProbe` returns remaining time after partial window has elapsed.
4. `timeUntilNextProbe` returns `Duration.zero` once deadline has passed (not negative).
5. `updateActivityWindow(newWindow)` shifts the deadline; subsequent `timeUntilNextProbe` reflects new window.
6. `probeInFlight` getter returns true after `markProbeInFlight`; false after `recordProbeSuccess` / `cancelProbe` / `recordProbeFailure`.

Kept unchanged (semantics identical): all `recordActivity`, `markProbeInFlight`, `recordProbeSuccess`, `recordProbeFailure`, `cancelProbe` state-transition tests.

### Layer 2: `LifecycleClient` unit tests

File: `bluey/test/connection/lifecycle_client_test.dart`.

Removed: any tests asserting `Timer.periodic` tick counts over elapsed time.

Added:
1. `_beginHeartbeat` arms exactly one timer at `activityWindow` from now.
2. Timer firing at the deadline sends a probe via fake platform.
3. Probe success reschedules for exactly `activityWindow` further.
4. `recordActivity()` during a cycle cancels the pending timer and reschedules for full `activityWindow`.
5. Continuous `recordActivity()` calls slide the deadline — probe never fires if activity is continuous.
6. Probe-in-flight when deadline fires: `_sendProbeOrDefer` no-ops; probe completion reschedules.
7. Transient error (`cancelProbe` path) reschedules at `activityWindow`.
8. Dead-peer under threshold reschedules at `activityWindow`.
9. Dead-peer trip: no reschedule, `stop()` called, `onServerUnreachable` fires.
10. `stop()` cancels pending timer; subsequent `_scheduleProbe()` is no-op.
11. **Regression test for I077:** exactly one probe per `activityWindow` across ≥10 cycles. No skipped ticks, no doubled cadence. Locks in the fix so it can't silently revert.

### Layer 3: Integration & manual verification

- Run `bluey` test suite, `bluey_platform_interface` test suite, `bluey_android` test suite — no regressions.
- Revert the `[I077]` instrumentation from the investigate branch.
- Re-run the original reproduction: Android server (Pixel 6a) + iOS client, 30+ seconds idle. Expected:
  - No `[Bluey] [Server] Client connected/disconnected` cycling during steady state.
  - iOS `_sendProbe` fires at `activityWindow` (5s default) intervals, not 10s.
  - Server `heartbeat-timer FIRED` never appears.

### Coverage targets

- `LivenessMonitor`: maintain existing coverage.
- `LifecycleClient`: 100% of the new scheduling code paths; test #11 explicitly guards the fix.

## Files touched

| File | Change |
|---|---|
| `bluey/lib/src/connection/liveness_monitor.dart` | Remove `shouldSendProbe`; add `timeUntilNextProbe` and `probeInFlight` getter; docstring update on `recordActivity` |
| `bluey/lib/src/connection/lifecycle_client.dart` | Replace `Timer.periodic`/`_tick` with `_scheduleProbe`/`_sendProbeOrDefer`; reschedule on every completion and on `recordActivity` |
| `bluey/test/connection/liveness_monitor_test.dart` | Remove `shouldSendProbe` tests; add `timeUntilNextProbe`/`probeInFlight` tests |
| `bluey/test/connection/lifecycle_client_test.dart` | Add scheduling-behavior tests including the I077 regression lock-in |
| `docs/backlog/I077-lifecycle-client-disconnect-storm.md` | Mark `status: fixed`, set `fixed_in`, update `last_verified` |
| (investigate branch) Revert temporary `[I077]` instrumentation before merge | Removes `debugPrint` calls from `GattServer.kt`, `LifecycleServer`, `BlueyServer`, `LifecycleClient`, `BlueyConnection` |

## Breaking-change acceptability

None. The `LivenessMonitor` API change (`shouldSendProbe` → `timeUntilNextProbe` + `probeInFlight`) is package-internal — the class is consumed only by `LifecycleClient` in the same package. No public API, no Pigeon schema, no platform interface touched.

## DDD / CA alignment

- **Dependencies inward unchanged:** `LivenessMonitor` remains framework-free. `LifecycleClient` owns the `Timer` (application-layer concern) and orchestrates via the monitor. No domain concept gained or lost.
- **Single responsibility strengthened:** the monitor used to mix state tracking with "should we probe now?" decision logic. After the fix, it purely tracks state; the scheduling decision is entirely in the client.
- **Value-object discipline preserved:** `LivenessMonitor` fields stay private with the same invariants (monotonic failure counter until activity, at-most-one probe in flight).
