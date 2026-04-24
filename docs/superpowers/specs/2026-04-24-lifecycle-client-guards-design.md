# Lifecycle client guards — design

**Covers:** I070 + I073 + I078
**Status:** approved, ready for plan
**Related:** I077 (predecessor lifecycle fix, same file)

## Goal

Three known bugs in `LifecycleClient` all share the same root cause: the class has no authoritative "running" sentinel. Today it reads `_probeTimer != null` via the `isRunning` getter in some places and `_heartbeatCharUuid != null` in others, and neither correctly represents "`start()` has been called and `stop()` has not."

The fix is to add a single `_isRunning` flag that is flipped on at the very top of `start()` and cleared at the very top of `stop()`, and to consult it in every place where the class currently guards on a stale proxy.

## Why each bug exists

### I070 — late promise callbacks fire after `stop()`

`LifecycleClient.stop()` cancels the probe timer and clears `_heartbeatCharUuid`, but in-flight Pigeon futures (the interval-read dispatched in `start()`, and heartbeat-write dispatched in `_sendProbe`) are not cancellable. When those futures resolve after `stop()` ran:

- The interval-read `.then` at `lifecycle_client.dart:101-111` calls `_beginHeartbeat`, which calls `_scheduleProbe` — arming a new timer on a supposedly-dead client.
- Probe-write completion paths (`.then` at :204, `.catchError` at :209) mutate `_monitor` and call `_scheduleProbe`.

In production this compounds across disconnect cycles: each tear-down can leak a ghost probe timer.

### I073 — `start()` is not idempotent

Calling `start()` twice before the first's interval-read has resolved overwrites `_heartbeatCharUuid` and schedules a second chained flow. If both `.then` callbacks fire, two independent probe schedulers end up running. Today this is only prevented because `BlueyConnection._tryUpgrade` is the sole caller and only calls it once — a fragile invariant to rely on.

### I078 — `recordActivity()` silently drops signals during `start()`

`recordActivity()` early-returns when `!isRunning`. `isRunning` returns `_probeTimer != null`, which stays `false` throughout the window between `start()` setting `_heartbeatCharUuid` (:84) and `_beginHeartbeat()` actually arming a timer (reached only after the interval-read Pigeon round-trip resolves). Any successful GATT op that completes inside that window has its `recordActivity()` call silently dropped, shifting the first probe's deadline earlier than the monitor would otherwise schedule.

## Design

### The `_isRunning` sentinel

```dart
class LifecycleClient {
  bool _isRunning = false;

  void start({required List<RemoteService> allServices}) {
    if (_isRunning) return;                    // I073 guard
    _isRunning = true;                          // flag up BEFORE any async work
    // ... existing body (find control service, set _heartbeatCharUuid,
    //     dispatch first heartbeat, read interval)
  }

  void stop() {
    _isRunning = false;                         // flag down at top of stop()
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
    _monitor.cancelProbe();                     // release any in-flight probe
  }

  bool get isRunning => _isRunning;             // getter now reflects the flag
}
```

`_heartbeatCharUuid` is kept as a separate field, but its meaning is narrowed: it's now strictly "we discovered a heartbeat characteristic on this server and know its UUID for writes." It is **not** a running-sentinel. The in-code comment on the field should say so explicitly, so future readers don't re-conflate the two.

### Callback guards

Every promise callback that would mutate state or schedule work consults `_isRunning` first:

- `start()`'s interval-read `.then` and `.catchError` at lines 101-111.
- `_sendProbe`'s `.then` at line 204.
- `_sendProbe`'s `.catchError` at line 209.

Each gets `if (!_isRunning) return;` as its first statement. Inside the probe-failure `.catchError`, the check precedes all monitor mutation, so `_monitor.cancelProbe()` / `_monitor.recordProbeFailure()` do not run after `stop()`.

Re-entrancy concern: `onServerUnreachable()` (called from the failure `.catchError` when the threshold trips) typically triggers a connection tear-down, which in turn calls `_lifecycle.stop()`. The handler calls `stop()` immediately before `onServerUnreachable()`, so a re-entrant `stop()` is idempotent (already handled by the `_isRunning` check).

Monitor cleanup: before the callback guards land, the `.then` / `.catchError` paths were responsible for releasing `_monitor._probeInFlight` via `recordProbeSuccess` / `recordProbeFailure` / `cancelProbe`. Adding `if (!_isRunning) return;` at the top of those callbacks blocks that release. To compensate, `stop()` explicitly calls `_monitor.cancelProbe()` so the in-flight flag is released synchronously when the client is torn down. This matters because `LivenessMonitor` instances are long-lived relative to any single probe, and a stranded `_probeInFlight = true` would prevent future probes from being dispatched if the client were ever restarted.

### `recordActivity()` window

```dart
void recordActivity() {
  if (!_isRunning) return;
  _monitor.recordActivity();
  _scheduleProbe();
}
```

With `_isRunning` set at the top of `start()`, any successful GATT op whose completion callback reaches `recordActivity()` during the `start()` → interval-read window now passes the guard. `_monitor.recordActivity()` refreshes `_lastActivityAt`; `_scheduleProbe()` is still guarded by `_heartbeatCharUuid != null` (which becomes non-null early in `start()`, before the interval read), so if the char is known, the probe is rescheduled.

If `recordActivity()` runs **before** `_heartbeatCharUuid` is set (e.g., activity arrives in the same microtask as `start()` entry, before the control-service lookup finishes), `_scheduleProbe` no-ops. That's fine — the monitor's timestamp is still updated, and the first `_scheduleProbe` later in `start()` will pick it up via `timeUntilNextProbe()`.

### What is removed

The previous code relied on `_heartbeatCharUuid == null` as a stand-in for "stopped" in `_scheduleProbe` (:171), `_sendProbeOrDefer` (:183), and `_sendProbe` (:194). Those checks can stay as defense-in-depth (they're cheap and document intent), but the authoritative "am I running" question is now answered by `_isRunning`. Where the current code reads `_heartbeatCharUuid == null` purely as a running-sentinel, the callback-level `_isRunning` guard is what actually blocks the work; the char-uuid check is retained only where the caller genuinely needs the UUID.

## Test plan

All tests in `bluey/test/connection/lifecycle_client_test.dart`. Uses `FakeAsync` for deterministic time travel and `FakeBlueyPlatform` with per-test hooks to hold/resolve Pigeon futures.

### I070 — late callbacks no-op after `stop()`

1. `start()` → let the interval-read future be held (unresolved).
2. `stop()`.
3. Resolve the interval-read future.
4. Assert: no probe timer armed, `_monitor` untouched, no second heartbeat dispatched.

Plus the symmetric case:

1. `start()` with interval-read resolved immediately.
2. Advance time so a probe fires; hold the probe-write future.
3. `stop()`.
4. Resolve the probe-write future with success (then repeat with failure).
5. Assert: `_monitor.recordProbeSuccess` / `recordProbeFailure` were not called, no follow-on probe armed.

### I073 — double `start()` is a no-op

1. `start()` with held interval-read.
2. `start()` again. Expect no-op.
3. Resolve the interval-read.
4. Assert: exactly one probe timer is armed, `_monitor.activityWindow` was set exactly once from the single interval response.

### I078 — activity during `start()` window is not dropped

1. `start()` with held interval-read.
2. Call `recordActivity()` — simulates a user GATT op completing during the window.
3. Resolve the interval-read.
4. Assert: the monitor's `_lastActivityAt` reflects the step-2 timestamp (i.e. the first scheduled probe's deadline is `activityWindow` from step 2, not from the interval-read resolution).

## Rollout & compatibility

- No public API change. `isRunning`'s observable behaviour narrows to "after `start()` call, before `stop()` call" — but no external caller today queries it between those boundaries for any semantic other than "is the client active."
- No Pigeon change, no platform-interface change, no protocol change. All changes are within `lifecycle_client.dart` and its test file.
- `LivenessMonitor` is untouched — pure domain, already correct.

## Out of scope

- **I079** (heartbeat starvation) is a separate PR, different file (`lifecycle_server.dart`), different change shape. It ships immediately after this one.
- **I077-style deadline-scheduling correctness** is already fixed; nothing here regresses or re-opens it.
- Deleting the now-redundant `_heartbeatCharUuid == null` defense-in-depth checks is not part of this PR — they're cheap, document intent, and removing them buys nothing.
