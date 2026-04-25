# Client-Side LifecycleClient: User Ops as First-Class Liveness Signals (I097)

**Status:** proposed
**Date:** 2026-04-26
**Scope:** `bluey` package — `LifecycleClient` + `BlueyConnection` only. No platform-interface change, no native change, no protocol change.
**Backlog entry:** [I097](../../backlog/I097-client-opslot-starves-heartbeat.md).

## Problem

The failure-injection stress test reliably tears down the client connection at any `maxFailedHeartbeats` setting, because heartbeat probes accumulate failures faster than tolerance can absorb them.

Walking the chain: server drops echo #0 → CoreBluetooth's per-peripheral write-with-response queue holds the next heartbeat (CB serialises writes-with-response, doesn't dispatch the next until the in-flight one gets a `didWriteValueFor` callback) → heartbeat sits in CB's internal queue, never goes on the wire → our OpSlot's per-op timer fires → heartbeat surfaces as `GattOperationTimeoutException` to `LifecycleClient`.

`LifecycleClient._isDeadPeerSignal` lumps all `GattOperationTimeoutException` together. There's no way for the Dart side to tell "server didn't respond" (real dead-peer) from "CB held my write while another op was in flight" (local serialisation, peer is fine). So the dead-peer counter trips, the client tears down a healthy connection.

## Root cause

The lifecycle layer treats heartbeat probes as the *only* source of dead-peer evidence, and fires probes on a fixed cadence regardless of whether user ops are concurrently providing the same evidence. This produces two problems:

1. **Redundant probing during active use.** While a user op is in flight, that op is itself an outstanding peer probe — its outcome (success, status-failure, wire-timeout, or disconnect) tells us about the peer. Layering an additional heartbeat probe on top adds nothing on the *evidence* side and creates the queue contention the bug describes on the *cost* side.
2. **Missed signals from user ops.** When a user op times out, that timeout is a dead-peer signal in exactly the same way a timed-out heartbeat is — "we sent something, the peer didn't answer." Today's design discards this signal: only heartbeat-probe failures feed the dead-peer counter. Authoritative detection requires using *all* the evidence we have.

## Symmetry with I079

I079 (server-side, fixed) refused to declare a client dead while the server held a pending request from it — using "the link is provably alive because it just delivered a request" as the override. I097 strengthens the same principle on the *client* side and makes it bidirectional: user ops are first-class liveness signals.

| Side | Idle policy | Active-evidence rule |
|---|---|---|
| Server (I079) | Per-client timer counts up; trips at interval | Pending request from client → pause timer (request itself is proof of life) |
| Client (I097) | Probe deadline counts down; failure counts toward threshold | User op pending → defer probe (op itself is the probe). User op outcome → feed into the same threshold counter |

Same principle on both sides: the lifecycle layer treats *active op outcomes* as its primary liveness signal. The idle-detection probe (server timer / client heartbeat) only kicks in during quiet periods.

## Goals

Two complementary mechanisms:

1. **Defer probes while user ops pending.** `LifecycleClient` tracks a per-connection count of in-flight user ops via `markUserOpStarted/Ended`. While count > 0, scheduled probes defer rather than fire — the in-flight op is itself an outstanding peer probe.

2. **User-op outcomes feed the dead-peer counter.** When a user op times out, treat it the same way a heartbeat-probe timeout is treated: increment the counter, potentially trip the threshold. When a user op succeeds, reset the counter (already the case via the existing `recordActivity` call).

Combined, the lifecycle layer authoritatively detects dead peer using *every* available signal:

| Scenario | Behaviour |
|---|---|
| Idle, peer healthy | Periodic probes succeed; counter stays at 0 |
| Idle, peer dies | Probe fails; counter increments; trip after threshold |
| Active use, peer healthy | Probes deferred; user ops succeed; counter stays at 0 |
| Active use, one op fails (failure-injection scenario) | One counter increment; next op succeeds, counter resets. Recovery if tolerance ≥ 2 |
| Active use, all ops fail (peer dead) | Counter increments per failed op; trip after threshold |

## Non-goals

- **Not changing the platform interface.** No new exception types, no new fields on existing exceptions. The signal already crosses the boundary as `GattOperationTimeoutException`; we just route it through the lifecycle layer in addition to the user.
- **Not surfacing CoreBluetooth queue state from iOS.** Avoided in favour of the higher-level reframe — heartbeats are deferred during user-op pendency, so the contention scenario simply doesn't occur.
- **Not changing the heartbeat write protocol.** Same characteristic, same value, same cadence formula. Heartbeats still serve the secondary purpose of keeping the server's I079 timer fed during idle periods.
- **Not changing existing predicates.** `_isDeadPeerSignal` (used for heartbeat probes) keeps its current taxonomy. A separate, narrower predicate is used for user-op failures (timeout only — see below).
- **Not changing `maxFailedHeartbeats` defaults or semantics.** Counter and threshold logic stay exactly the same; the threshold simply now sees signals from both heartbeats and user ops.

## Decisions locked

1. **Counter, not boolean, for in-flight user ops.** Use `int _pendingUserOps` because a connection can have multiple ops in flight across different OpSlots (different characteristics) — counter handles concurrent ops naturally.
2. **`finally`-wrapped accounting in `BlueyConnection`.** Markers fire in `try { mark; await op; on success: recordActivity } catch { recordUserOpFailure(error) } finally { unmark; }` so a thrown exception still decrements the counter. Leaks would be catastrophic — once leaked, probes never fire again.
3. **Different predicate for user-op failures vs heartbeat failures.** Heartbeats use the existing `_isDeadPeerSignal` (timeout / disconnect / statusFailed) — wide net, justified by the Service-Changed force-kill case. User ops use a narrower predicate: **timeout only**. Disconnect is already handled by the platform-level disconnect callback (separate path that tears down the connection); statusFailed at the user-op level can mean ATT errors like WriteNotPermitted that don't imply dead peer.
4. **Both mechanisms feed the same counter.** No separate "user-op failure counter" — `recordProbeFailure` is the single increment path. Whether the failure came from a heartbeat probe or a user op is invisible to the counter.
5. **Defer-only, not skip-and-cancel-deadline.** When `_sendProbeOrDefer` defers, it reschedules per the existing cadence (one `activityWindow` later). Once the user op completes, the next scheduled probe attempt fires normally.
6. **Threshold-trip path is unchanged.** When the counter trips, the existing logic runs as is: stop, fire `onServerUnreachable`, no further reschedule.

## Architecture

Two files change. Neither edit touches the platform interface or native code.

### `LifecycleClient` — counter, deferral, user-op outcome handling

New private field, three new public methods:

```dart
/// Count of user-initiated ops currently pending on this connection.
/// Probes are deferred while > 0 — the in-flight op is itself an
/// outstanding peer probe.
int _pendingUserOps = 0;

/// Called by [BlueyConnection] when a user GATT op is dispatched.
void markUserOpStarted() {
  _pendingUserOps++;
}

/// Called by [BlueyConnection] when a user GATT op completes (success
/// or failure). Symmetric with [markUserOpStarted]. Decrement only.
void markUserOpEnded() {
  if (_pendingUserOps > 0) _pendingUserOps--;
}

/// Called by [BlueyConnection] when a user GATT op fails. Filters by
/// predicate: timeouts increment the dead-peer counter (and may trip
/// onServerUnreachable); other errors are no-ops at this layer.
///
/// User-op disconnects are deliberately not counted here: the platform
/// disconnect callback already triggers tear-down through a separate
/// path. User-op statusFailed errors are deliberately not counted: at
/// the user level they can mean ATT errors (WriteNotPermitted, etc.)
/// that don't imply dead peer.
void recordUserOpFailure(Object error) {
  if (!_isRunning) return;
  if (error is! platform.GattOperationTimeoutException) return;
  final tripped = _monitor.recordProbeFailure();
  if (tripped) {
    stop();
    onServerUnreachable();
  }
}
```

Modify `_sendProbeOrDefer` (currently lines 226–234 of `lifecycle_client.dart`):

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

Stop semantics stay correct: `stop()` doesn't need to touch `_pendingUserOps` (it's per-instance, discarded with the connection). `recordUserOpFailure` early-returns when not running.

### `BlueyConnection` — wrap user-op call sites

Each user-op method on `BlueyConnection` (the same call sites that already invoke `_lifecycle?.recordActivity()` on success) wraps the platform call:

```dart
// Before:
final result = await _platform.writeCharacteristic(...);
_lifecycle?.recordActivity();
return result;

// After:
_lifecycle?.markUserOpStarted();
try {
  final result = await _platform.writeCharacteristic(...);
  _lifecycle?.recordActivity();
  return result;
} catch (error) {
  _lifecycle?.recordUserOpFailure(error);
  rethrow;
} finally {
  _lifecycle?.markUserOpEnded();
}
```

The four current `recordActivity` sites (`bluey_connection.dart:317, :364, :376, :619`) all need the wrapper, except the notification-stream callback at `:619` (notifications aren't outbound user ops — keeps just `recordActivity`). The plan will list each site explicitly.

`_lifecycle` is null when no Bluey peer is configured on the connection. The `?.` chain just no-ops — counter stays at zero on the (non-existent) lifecycle, deferral logic doesn't apply. Safe.

## TDD

Tests live in `bluey/test/connection/`. Three layers.

### `LifecycleClient` (`bluey/test/connection/lifecycle_client_test.dart`)

Five new tests:

1. **Probe deferred while user op pending.** Set up a tracked client with a future probe deadline. Call `markUserOpStarted()`. Advance time past the deadline. Verify: no probe write attempted.
2. **Probe fires after user op ends.** Same setup. Call `markUserOpStarted()`, advance, verify deferred. Call `markUserOpEnded()`. Advance one `activityWindow`. Verify: probe write attempted.
3. **Multiple concurrent user ops correctly counted.** Two `markUserOpStarted()` calls. One `markUserOpEnded()`. Verify probe still deferred. Second `markUserOpEnded()`. Verify probe fires on the next tick.
4. **`recordUserOpFailure` with timeout increments counter.** Set `maxFailedProbes=1`. Call `recordUserOpFailure(GattOperationTimeoutException(...))`. Verify `onServerUnreachable` fires.
5. **`recordUserOpFailure` with non-timeout is no-op.** Same setup but pass `GattOperationStatusFailedException` or a generic exception. Verify `onServerUnreachable` does NOT fire.

These pin both the deferral and the user-op-failure-counting contracts.

### `BlueyConnection` (`bluey/test/connection/bluey_connection_test.dart`)

Three new tests covering the wrapping:

6. **User op success → markStarted then markEnded; recordActivity called.** Issue a write that succeeds. Verify counter went up then down; verify `recordActivity` was called.
7. **User op timeout → markStarted, recordUserOpFailure, markEnded.** Make the platform throw `GattOperationTimeoutException`. Verify the failure was recorded; verify the counter still returns to zero (no leak).
8. **User op other failure → markStarted, recordUserOpFailure (no-op), markEnded.** Make the platform throw a non-timeout exception. Verify the counter returns to zero. Verify the threshold isn't tripped.

These pin the connection-side accounting.

### Existing tests

Existing `LifecycleClient` and `BlueyConnection` tests continue to pass — the new code is additive. No semantic changes to existing methods.

## Caveats

### What if a user op stalls forever?

The user op itself has a per-op timeout (10 s default at OpSlot level). When it expires, `recordUserOpFailure` fires (incrementing the counter, possibly tripping), `markUserOpEnded` fires (in `finally`). Worst case: a single op stall delays dead-peer detection by the user-op timeout window, but the failure is then captured authoritatively.

### Failure-injection scenario walkthrough

Default settings, `maxFailedHeartbeats = 1`:

- t=0: echo #0 starts. count=1, counter=0.
- t=5: probe deadline ticks, deferred (count=1).
- t=10: echo #0 times out. `recordUserOpFailure(timeout)` → counter=1, tripped → `onServerUnreachable` → disconnect. Count=0 (in `finally`).
- Test ends with: 1 user-op timeout + N-1 disconnects. **Same as today's behaviour at tolerance=1.** Strict tolerance is intentionally aggressive — that's the point.

`maxFailedHeartbeats = 3`:

- t=0–10: as above, but counter=1 doesn't trip.
- t=10+ε: echo #1 starts. count=1, deferred probe rescheduled.
- t≈10+latency: echo #1 succeeds. `recordActivity` → counter=0.
- Subsequent echoes succeed.
- Test ends with: 1 timeout + 9 successes. **Recovery scenario achieved.**

`maxFailedHeartbeats = 5`, ALL user ops fail (peer truly dead):

- Each echo times out → counter increments. After 5 timeouts → trip → disconnect.
- User sees: 5 user-op timeouts + N-5 disconnects. **Authoritative detection at threshold.**

### Why `markUserOpEnded` doesn't trigger an immediate probe

`markUserOpEnded` only decrements the counter. It doesn't reschedule. The next probe still fires on the previously scheduled timer. This avoids storms of probe firings if many ops complete in quick succession. The minor latency cost (next probe could be up to one `activityWindow` away) is acceptable — in practice ops completing rapidly means activity is healthy.

### Edge case: disconnect mid-op

When the connection drops mid-op, the platform layer drains the in-flight op with `GattOperationDisconnectedException`. The `catch` block fires `recordUserOpFailure(disconnect-exception)` — but the predicate filter (`is GattOperationTimeoutException` only) means this is a no-op. The disconnect path proceeds via its own (existing, unaffected) mechanism: the platform's disconnect callback stops the lifecycle and tears down the cubit's connection.

### Predicate scoping for user-op failures

The choice to count *only* `GattOperationTimeoutException` (and not `GattOperationStatusFailedException`) for user ops is deliberate:

- A user-op timeout can be queue-blocking (false positive for dead-peer) OR genuinely "peer didn't answer" (true positive). At higher tolerance settings (≥3), single false positives are absorbed by subsequent successes resetting the counter. At tolerance=1, false positives still trip — that's by design.
- A user-op statusFailed code is much more often application-meaningful (read-not-permitted, attribute-not-found) than dead-peer. Counting it would produce frequent false-positive trips with no compensating benefit.

If experience shows status-failed *should* count for some specific status codes (e.g., `GATT_INVALID_HANDLE` after Service Changed), the predicate can be widened in a follow-up. Keep it narrow for now.

## Risks and rollback

**Risks:**

- A `markUserOpStarted` without matching `markUserOpEnded` would leak the counter, suppressing probes forever. Mitigation: `try { ... } finally { ... }` wrapping at every call site, plus the test that asserts no leak on op failure.
- A peer that succeeds at user ops but fails at heartbeats (some weird ATT permissioning edge case where the heartbeat char is locked but other chars aren't) would now have user-op successes resetting the counter, potentially masking the heartbeat-only failures. Theoretically possible but exceedingly unlikely; the lifecycle char is configured by the library, not by the application.

**Rollback:** revert the two-file change. No state, no migration, no schema.

## Backlog hygiene

After landing:

1. Update `docs/backlog/I097-client-opslot-starves-heartbeat.md`: `status: open` → `fixed`, add `fixed_in: <sha>`, replace Notes with: "Fixed in `<sha>` by deferring heartbeat probes while user ops are in flight, AND treating user-op timeouts as first-class dead-peer signals that feed the same threshold counter as heartbeat-probe failures. Mirror image of I079 with bidirectional symmetry: both sides of the protocol now use active-op outcomes as their primary liveness signal, with idle-detection probes/timers only kicking in during quiet periods."
2. Update `docs/backlog/README.md`: move I097 from Open → Fixed.
3. Update the example app's `failureInjection.readingResults`: now that I097 is fixed, the "tolerant recovery" outcome is reachable with `maxFailedHeartbeats=3` or higher. Restore the original two-scenario description (Strict → cascade, Tolerant → recovery) and remove the I097 caveat. One-file edit on the same branch.
