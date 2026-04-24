# Lifecycle client guards — design

**Covers:** I070 + I073 + I078
**Status:** approved, ready for plan
**Related:** I077 (predecessor lifecycle fix, same file)

## Goal

Three known bugs in `LifecycleClient` all share the same root cause: the class has no authoritative "running" sentinel. Today it reads `_probeTimer != null` via the `isRunning` getter in some places and `_heartbeatCharUuid != null` in others, and neither correctly represents "`start()` has committed to run and `stop()` has not yet unwound it."

The fix is to add a single `_isRunning` flag that is set at the commit point inside `start()` (after the pre-commit null checks pass) and cleared at the top of `stop()`, and to consult it in every place where the class currently guards on a stale proxy. `start()` itself becomes transactional: either the object transitions cleanly into the running state or it does not transition at all — no partial-start state can outlive the call.

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

`_isRunning` is the authoritative "I have committed to running and have not been stopped" flag. Its lifecycle is atomic: a call to `start()` either transitions the object cleanly into the running state (flag up, heartbeat char set, probe scheduled or interval-read dispatched) or leaves it fully in the pre-start state. There is no partial-start state that outlives the call.

```dart
class LifecycleClient {
  bool _isRunning = false;

  void start({required List<RemoteService> allServices}) {
    if (_isRunning) return;                         // I073 guard

    // Pre-commit: failing these checks means we never had work to do.
    // `_isRunning` stays false so a later retry (e.g. after service
    // discovery finds the control service) can still start us.
    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where((c) => c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid)
        .firstOrNull;
    if (heartbeatChar == null) return;

    // Commit point. From here on, any failure must fully unwind —
    // `_isRunning = true` is an invariant and cannot leak.
    _isRunning = true;
    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    dev.log('heartbeat started: char=$_heartbeatCharUuid', name: 'bluey.lifecycle');

    try {
      _sendProbe();

      final intervalChar = controlService.characteristics
          .where((c) => c.uuid.toString().toLowerCase() == lifecycle.intervalCharUuid)
          .firstOrNull;

      if (intervalChar != null) {
        _platform
            .readCharacteristic(_connectionId, intervalChar.uuid.toString())
            .then((bytes) {
          if (!_isRunning) return;               // I070 guard
          final serverInterval = lifecycle.decodeInterval(bytes);
          _beginHeartbeat(Duration(milliseconds: serverInterval.inMilliseconds ~/ 2));
        }).catchError((_) {
          if (!_isRunning) return;               // I070 guard
          _beginHeartbeat(_defaultHeartbeatInterval);
        });
      } else {
        _beginHeartbeat(_defaultHeartbeatInterval);
      }
    } catch (_) {
      // A synchronous throw from a platform call (or any line inside
      // the try block) would leave the object in an inconsistent
      // state. Unwind fully and re-raise so the caller sees the real
      // failure instead of a silent inert client.
      stop();
      rethrow;
    }
  }

  void stop() {
    _isRunning = false;                           // flag down at top of stop()
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
    _monitor.cancelProbe();                       // release any in-flight probe
  }

  bool get isRunning => _isRunning;               // getter reflects the flag
}
```

`_heartbeatCharUuid` is kept as a separate field, but its meaning is narrowed: it's now strictly "we discovered a heartbeat characteristic on this server and know its UUID for writes." It is **not** a running-sentinel. The in-code comment on the field should say so explicitly, so future readers don't re-conflate the two.

### Why two sentinels, not one

One could imagine making `_isRunning` a computed getter based on observable state (e.g. `_heartbeatCharUuid != null`). That conflation is what produced I078 in the first place — `_heartbeatCharUuid != null` means "we know a heartbeat char UUID" and that meaning doesn't cleanly capture "`start()` has committed to run." Keeping them as two fields with precisely-scoped meanings keeps each invariant local and checkable.

### The commit-point discipline

Three categories of failure are handled explicitly:

| Failure point | Result | Rationale |
|---|---|---|
| No control service or heartbeat char found | Early return before commit. `_isRunning` stays `false`. A later retry with a different `allServices` list can proceed. | These are legitimate "this server doesn't speak our protocol" outcomes, not exceptions. |
| Synchronous throw from a platform call after commit | `stop()` unwinds everything; exception is rethrown. | The class owns its invariants; it must not leave partial state for the caller to clean up. |
| Asynchronous platform failure (interval read rejects) | Handled by the existing `.catchError` fallback → `_beginHeartbeat(_defaultHeartbeatInterval)`. | Graceful degradation: we still run heartbeats, just with the default interval. |

The `.catchError` callbacks also check `_isRunning` first (see I070 guards) so that a late rejection arriving after `stop()` does not accidentally re-arm timers.

### `_sendProbe` callback guards

The pseudocode above shows the `_isRunning` guard in the `start()` interval-read callbacks. The same guard is also added to both `_sendProbe` callbacks:

- `.then` (on successful heartbeat write) — guards before `_monitor.recordProbeSuccess` and the follow-on `_scheduleProbe`.
- `.catchError` (on failed heartbeat write) — guards before `_monitor.cancelProbe` / `_monitor.recordProbeFailure` and any follow-on scheduling or `onServerUnreachable` invocation.

Re-entrancy concern: `onServerUnreachable()` (called from the failure `.catchError` when the threshold trips) typically triggers a connection tear-down, which in turn calls `_lifecycle.stop()`. The existing code calls `stop()` immediately before `onServerUnreachable()` in this path, so a re-entrant `stop()` call from the downstream tear-down is idempotent (already handled by the `_isRunning` check).

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

### Partial-start — pre-commit early return leaves state clean

Two cases, one per early return:

1. `start(allServices: <no control service>)`. Assert: `isRunning == false`, `_heartbeatCharUuid == null`, no timer armed. Then `start(allServices: <with control service>)`. Assert: starts normally — the earlier failed attempt did not block the retry.
2. `start(allServices: <control service without heartbeat char>)`. Assert: same — `isRunning == false`, state untouched, retryable.

### Partial-start — synchronous throw after commit unwinds fully

1. Configure `FakeBlueyPlatform` so `writeCharacteristic` throws synchronously (not via a rejected Future) — simulates a platform-layer sync throw.
2. Call `start(allServices: <valid services>)` → expect the exception to propagate out.
3. Assert: `isRunning == false`, `_heartbeatCharUuid == null`, no timer armed, `_monitor.probeInFlight == false`. The object is back in its pre-`start()` state.
4. Call `start()` again with a non-throwing platform → assert: starts normally.

## Rollout & compatibility

- No public API change. `isRunning`'s observable behaviour narrows to "after `start()` call, before `stop()` call" — but no external caller today queries it between those boundaries for any semantic other than "is the client active."
- No Pigeon change, no platform-interface change, no protocol change. All changes are within `lifecycle_client.dart` and its test file.
- `LivenessMonitor` is untouched — pure domain, already correct.

## Out of scope

- **I079** (heartbeat starvation) is a separate PR, different file (`lifecycle_server.dart`), different change shape. It ships immediately after this one.
- **I077-style deadline-scheduling correctness** is already fixed; nothing here regresses or re-opens it.
- Deleting the now-redundant `_heartbeatCharUuid == null` defense-in-depth checks is not part of this PR — they're cheap, document intent, and removing them buys nothing.
