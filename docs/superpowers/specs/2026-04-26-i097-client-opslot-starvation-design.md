# Client-Side LifecycleClient: Recent-Activity Guard on Probe Failure (I097)

**Status:** proposed
**Date:** 2026-04-26
**Scope:** `bluey` package — `LivenessMonitor` + `LifecycleClient` only. No platform-interface change, no native change, no protocol change.
**Backlog entry:** [I097](../../backlog/I097-client-opslot-starves-heartbeat.md).

## Problem

The failure-injection stress test reliably tears down the client connection at any `maxFailedHeartbeats` setting, because heartbeat probes accumulate failures faster than tolerance can absorb them.

Walking the chain: server drops echo #0 → CoreBluetooth's per-peripheral write-with-response queue holds the next heartbeat (CB serialises writes-with-response, doesn't dispatch the next until the in-flight one gets a `didWriteValueFor` callback) → heartbeat sits in CB's internal queue, never goes on the wire → our OpSlot's per-op timer fires → heartbeat surfaces as `GattOperationTimeoutException` to `LifecycleClient`.

`LifecycleClient._isDeadPeerSignal` lumps all `GattOperationTimeoutException` together. There's no way for the Dart side to tell "server didn't respond" (real dead-peer) from "CB held my write while another op was in flight" (local serialisation, peer is fine). So the dead-peer counter trips, the client tears down a healthy connection.

## Root cause

`_sendProbe`'s catchError branches on whether the error is a dead-peer signal, but doesn't cross-check the result against any other liveness evidence. We *do* have other evidence — `LivenessMonitor` already tracks `_lastActivityAt`, refreshed by `recordActivity` whenever any user op succeeds, any notification arrives, or any probe is acknowledged. If that timestamp is recent, the link is provably alive.

The misclassification is that we ignore that evidence when a probe times out.

## Symmetry with I079

I079 (server-side, fixed) refused to declare a client dead while the server held a pending request from it — using "the link is provably alive because it just delivered a request" as the override. This fix uses "the link is provably alive because we just received a successful response" as a symmetric override on the client side. Same principle: tolerate a probe failure when independent evidence contradicts the dead-peer interpretation.

## Goals

- Add a `livenessWindow` field to `LivenessMonitor`, defaulted to `4 × activityWindow` and rescaled in lockstep with `updateActivityWindow`. Wider than `activityWindow` because the bug case (heartbeat queued behind a 10 s user-op stall) needs more headroom than the probe-deadline cadence offers.
- Add a `hasRecentActivity` predicate that returns true when `_lastActivityAt` is within `_livenessWindow` of now.
- In `LifecycleClient._sendProbe`'s catchError, when the error is a dead-peer signal AND `hasRecentActivity` is true, treat the failure as transient: cancel the in-flight flag, reschedule, do not increment the failure counter.

## Non-goals

- **Not changing `_isDeadPeerSignal`'s classification.** The set of error types that *can* indicate dead peer is unchanged — only the gating logic above it.
- **Not exposing OpSlot transmission state.** A more invasive fix would surface "did this op actually go on the wire?" through Pigeon to Dart. We're choosing the simpler approach: cross-check against existing activity signal. If the activity-window approach proves insufficient, the more invasive route remains available.
- **Not changing the `recordActivity` call sites in `BlueyConnection`.** Those already populate `_lastActivityAt` correctly.
- **Not changing `maxFailedHeartbeats` defaults or semantics.** The counter logic only kicks in when there's no recent activity — same intent as today, just better-gated.
- **Not addressing user-op timeout handling.** When user ops time out, the user sees the exception (correct). Only the lifecycle layer's *internal* dead-peer determination needs the new guard.

## Decisions locked

1. **Fix lives entirely in `LivenessMonitor` + `LifecycleClient`.** Dart-only. No platform-interface or native change.
2. **Liveness window is wider than activity window.** `activityWindow` (the probe-deadline cadence) is too narrow to cover a typical 10 s user-op stall — by the time the queued heartbeat times out at OpSlot level, the last successful response is older than `activityWindow`. The new `hasRecentActivity` predicate uses a separate `livenessWindow`, defaulted to `4 × activityWindow` (≈ `2 × heartbeatInterval`, ≈ 20 s by default). This is "longest plausible user-op duration plus margin" — covers the failure-injection case with headroom.
3. **`livenessWindow` is computed inside the monitor, not exposed as a constructor parameter for now.** YAGNI. If experience shows the multiplier is wrong, it becomes a knob in a follow-up. For the first iteration, `livenessWindow = activityWindow * 4` internally, and `updateActivityWindow` recomputes the liveness window in lockstep.
4. **Order of checks in `catchError` matters.** Existing transient-error path stays first (non-dead-peer errors are still ignored without an activity check). The new activity guard wraps the dead-peer branch only.
5. **Threshold-trip path is unchanged.** When a probe failure *does* count, the rest of the trip logic stays exactly as is — including reschedule cadence and `onServerUnreachable` callback firing.

## Architecture

Two files change. Both edits are additive.

### `LivenessMonitor` — `livenessWindow` field + `hasRecentActivity` predicate

Add a new private field `_livenessWindow` initialised from the constructor's `activityWindow * 4`. When `updateActivityWindow` is called, recompute `_livenessWindow` in lockstep.

```dart
Duration _livenessWindow;
// ... in constructor:
_livenessWindow = activityWindow * 4,
// ... in updateActivityWindow:
_livenessWindow = window * 4;
```

Add the predicate:

```dart
/// True iff [recordActivity] has been called recently enough that the
/// peer's liveness can be inferred from independent evidence — within
/// [_livenessWindow] of now (`4 × activityWindow` by default).
///
/// Wider than [activityWindow] (the probe-deadline cadence) on
/// purpose: a successful peer response 10 s ago is still strong
/// evidence the link is alive, even if the next probe deadline has
/// already passed. Used by [LifecycleClient] to override the
/// dead-peer interpretation of a probe failure when other ops are
/// proving the link is alive (see I097).
bool get hasRecentActivity {
  final last = _lastActivityAt;
  if (last == null) return false;
  return _now().difference(last) < _livenessWindow;
}
```

Expose `_livenessWindow` via a `@visibleForTesting` getter so tests can verify the value tracks `activityWindow` correctly.

### `LifecycleClient._sendProbe` — guard the dead-peer branch

Current shape (`bluey/lib/src/connection/lifecycle_client.dart:254-285`):

```dart
.catchError((Object error) {
  if (!_isRunning) return;
  if (!_isDeadPeerSignal(error)) {
    _monitor.cancelProbe();
    _scheduleProbe(after: _monitor.activityWindow);
    return;
  }
  final tripped = _monitor.recordProbeFailure();
  // ... log + tripped branch
});
```

After:

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
  if (_monitor.hasRecentActivity) {
    // Dead-peer-shaped error, but we have independent evidence the
    // link is alive (a successful op or notification within the
    // activity window). The probe likely failed because of local
    // serialisation (CoreBluetooth's per-peripheral write queue,
    // OpSlot starvation behind a stalled user op). Treat as
    // transient — see I097.
    _monitor.cancelProbe();
    _scheduleProbe(after: _monitor.activityWindow);
    return;
  }
  // Genuine dead-peer signal — count toward the failure threshold.
  final tripped = _monitor.recordProbeFailure();
  // ... existing log + tripped branch unchanged
});
```

The dev.log message inside the `tripped` branch can stay; we may want to add an info-level log on the new "absorbed by recent-activity guard" path for diagnostic visibility, but that's a follow-up nicety, not required for correctness.

## TDD

Tests live in `bluey/test/connection/`. Two layers.

### `LivenessMonitor` (`bluey/test/connection/liveness_monitor_test.dart`)

Four new tests:

1. **No activity recorded yet → `hasRecentActivity` false.**
2. **Activity recorded within `livenessWindow` → true.** (e.g., 15 s elapsed with default 20 s window)
3. **Activity recorded older than `livenessWindow` → false.** (e.g., 25 s elapsed)
4. **`updateActivityWindow` rescales `livenessWindow` in lockstep.** Set initial activity window to 5 s, advance time, call `updateActivityWindow(10s)` — the new liveness window should be 40 s and `hasRecentActivity` should reflect the wider window.

These pin the predicate's contract. Use the existing `now: () => fakeNow` injection pattern that the file already uses for time control.

### `LifecycleClient` (`bluey/test/connection/lifecycle_client_test.dart`)

Two new tests for the guarded catchError path:

1. **Probe failure absorbed when recent activity exists.** Set up a connected client with `recordActivity` recently called, then trigger a probe that fails with `GattOperationTimeoutException`. Assert: failure counter is NOT incremented; probe is rescheduled; `onServerUnreachable` is NOT called even at `maxFailedProbes=1`.

2. **Probe failure counted when no recent activity.** Same as above but without recording activity. Assert: failure counter IS incremented; with `maxFailedProbes=1`, `onServerUnreachable` fires.

These are the regression tests for I097. The existing tests for the unguarded dead-peer path (no recent activity → trip threshold) remain valid; they're equivalent to test 2.

### Failing-first order

The plan executes the `LivenessMonitor` predicate tests first (3 reds → green), then the `LifecycleClient` guard tests (2 reds → green via the catchError edit). Each test is added before the code change that makes it pass.

## Caveats

### Sizing the liveness window

Walking through the failure-injection scenario with default settings (heartbeat interval 10 s, `activityWindow` 5 s, `livenessWindow` 20 s):

- t=0: prologue Reset succeeds → `recordActivity`.
- t≈ε: prologue DropNext succeeds → `recordActivity`.
- t≈ε: echo #0 sent. Server drops it.
- t≈5: heartbeat probe fires write. CB queues it (echo #0 still in flight at the CB level).
- t≈10: echo #0 OpSlot timeout fires → user-visible `GattTimeoutException`, no `recordActivity`.
- t≈15: heartbeat OpSlot timeout fires (queued at t≈5 with 10 s timeout) → `GattOperationTimeoutException` reaches `_sendProbe.catchError`.

At t≈15, `_lastActivityAt` is t≈ε. Elapsed: ~15 s. With `livenessWindow = 4 × activityWindow = 20 s`: 15 s < 20 s → guard absorbs the failure. Connection survives. ✓

A second probe failure under similar conditions might land at t≈25 — outside the 20 s window. With `maxFailedHeartbeats=1`, the connection trips at that point. Acceptable: by then, two genuine wire-level dead-peer signals have accumulated, which is reasonable evidence.

The 4× multiplier was chosen to give a window that comfortably covers a typical 10 s user-op stall plus the heartbeat scheduling cadence, with margin. If real-world timing pushes outside this — e.g., user ops with 30 s timeouts — the multiplier or window can be retuned.

### Edge case: peer dies right after a successful op

A peer that genuinely went silent right after a successful op (e.g., 100 ms later) gets one extra probe-failure absorption before the lifecycle layer trips. With `maxFailedHeartbeats=1`, this delays disconnect by one probe interval (~5 s default). Acceptable trade-off — the alternative is the false-positive disconnect we're explicitly fixing.

### Why not surface "did this op transmit?" from iOS

A more invasive fix would expose CoreBluetooth's "in-flight at peripheral level" state through Pigeon to Dart, so `_isDeadPeerSignal` could distinguish wire-timeouts from queue-timeouts directly. We're choosing the simpler approach because:

1. The Dart-side `_lastActivityAt` already encodes the right signal — *we have evidence the peer is alive*.
2. Adding new platform-interface fields is invasive and doesn't change the fundamental classification gap (the iOS layer also can't see CB's internal queue state directly — it would have to track in-flight ops itself).
3. If the activity-window approach turns out insufficient in practice, the more invasive route remains available as a follow-up.

## Risks and rollback

**Risks:**
- The 2× multiplier may not be enough for very long user-op stalls. Mitigation: failure-injection on-device verification will tell us; if not enough, bump multiplier or expose as a knob.
- A peer that genuinely went silent right after a successful op (e.g., 100ms later) gets one extra probe-failure absorption before the lifecycle layer trips. With `maxFailedHeartbeats=1`, this delays disconnect by one probe interval (~5s default). Acceptable.

**Rollback:** revert the two-file change. No state, no migration.

## Backlog hygiene

After landing:
1. Update `docs/backlog/I097-client-opslot-starves-heartbeat.md`: `status: open` → `fixed`, add `fixed_in: <sha>`, replace Notes with "Fixed in `<sha>` by adding a recent-activity guard to `LifecycleClient._sendProbe`'s catchError. The dead-peer signal is no longer counted as a probe failure if `LivenessMonitor.hasRecentActivity` is true (peer activity within `livenessWindow = 2 × activityWindow`)."
2. Update `docs/backlog/README.md`: move I097 from Open → Fixed.
3. Update the example app's `failureInjection.readingResults`: now that I097 is fixed, the "tolerant recovery" outcome is reachable. Restore the original two-scenario description (Strict → cascade, Tolerant → recovery) and remove the I097 caveat. This is a one-file edit on the same branch.
