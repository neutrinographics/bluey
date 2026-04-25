# Client-Side LifecycleClient: Defer Probes While User Ops Pending (I097)

**Status:** proposed
**Date:** 2026-04-26
**Scope:** `bluey` package — `LifecycleClient` + `BlueyConnection` only. No platform-interface change, no native change, no protocol change.
**Backlog entry:** [I097](../../backlog/I097-client-opslot-starves-heartbeat.md).

## Problem

The failure-injection stress test reliably tears down the client connection at any `maxFailedHeartbeats` setting, because heartbeat probes accumulate failures faster than tolerance can absorb them.

Walking the chain: server drops echo #0 → CoreBluetooth's per-peripheral write-with-response queue holds the next heartbeat (CB serialises writes-with-response, doesn't dispatch the next until the in-flight one gets a `didWriteValueFor` callback) → heartbeat sits in CB's internal queue, never goes on the wire → our OpSlot's per-op timer fires → heartbeat surfaces as `GattOperationTimeoutException` to `LifecycleClient`.

`LifecycleClient._isDeadPeerSignal` lumps all `GattOperationTimeoutException` together. There's no way for the Dart side to tell "server didn't respond" (real dead-peer) from "CB held my write while another op was in flight" (local serialisation, peer is fine). So the dead-peer counter trips, the client tears down a healthy connection.

## Root cause

The lifecycle layer fires a *redundant* signal. While a user op is in flight, that op is itself an outstanding peer probe — its outcome (success, status-failure, wire-timeout, or disconnect) tells us about the peer. Layering an additional heartbeat probe on top adds nothing on the *evidence* side and creates the exact contention the bug describes on the *cost* side.

Heartbeats only carry information when the connection is otherwise *idle*. During active use, the user ops carry the same information.

## Symmetry with I079

I079 (server-side, fixed) refused to declare a client dead while the server held a pending request from it — using "the link is provably alive because it just delivered a request" as the override. I097 is the structural mirror: the *client* refuses to fire a redundant heartbeat probe while it has its own outstanding op to the peer — using "the user op is itself a probe" as the override.

| Side | Idle policy | Active-evidence override |
|---|---|---|
| Server (I079) | Per-client timer counts up; trips at interval | Pending request from client → pause timer |
| Client (I097) | Per-deadline probe fires; failure counts toward threshold | Own op pending → defer probe |

Same principle on both sides: the lifecycle layer doesn't fire its idle-detection mechanism while there's independent evidence of an active exchange. Once both sides land, the design is uniform.

## Goals

- `LifecycleClient` tracks a per-connection count of in-flight user ops via two methods: `markUserOpStarted()` and `markUserOpEnded()`.
- `_sendProbeOrDefer` checks the count before firing. If `> 0`, defer (reschedule), do not fire.
- `BlueyConnection` wraps each user-initiated GATT op (read, write, descriptor read/write, MTU request, set-notification, …) with `markUserOpStarted` before dispatch and `markUserOpEnded` in a `finally` block — so the count tracks pendency regardless of outcome.

## Non-goals

- **Not changing `_isDeadPeerSignal`'s classification.** The error-type taxonomy stays as is. The fix lives entirely above it: probes that get deferred never reach `_isDeadPeerSignal` in the first place.
- **Not surfacing OpSlot transmission state from iOS.** Avoided in favour of the higher-level reframe — heartbeats are for idle detection, so the contention scenario simply doesn't occur once the deferral lands.
- **Not changing `recordActivity`.** Successful user ops still call it, which still resets the failure counter and shifts the next deadline. The deferral is a separate gate orthogonal to that.
- **Not changing `maxFailedHeartbeats` defaults or semantics.** Counter and threshold logic stay exactly the same; they only kick in when a probe actually fires (no in-flight user op).
- **Not bypassing CoreBluetooth's queue.** That queue's serialisation is fine — the fix just stops firing redundant probes while it's busy with user traffic.
- **Not addressing user-op timeout handling.** When a user op times out, the user sees the exception (correct). The probe-deferral logic doesn't affect that path.

## Decisions locked

1. **Counter, not boolean.** Use `int _pendingUserOps` because a connection can have multiple ops in flight across different OpSlots (different characteristics) — counter handles concurrent ops naturally; boolean would either over- or under-count.
2. **`finally`-wrapped accounting in `BlueyConnection`.** Markers fire in `try { mark; await op; } finally { unmark; }` so a thrown exception (timeout, disconnect, etc.) still decrements the counter. Leaks would be catastrophic — once leaked, probes never fire again.
3. **Defer-only, not skip-and-cancel-deadline.** When `_sendProbeOrDefer` defers, it reschedules per the existing cadence (one `activityWindow` later). Doesn't reset the failure counter, doesn't skip the deadline — just postpones this specific tick. Once the user op completes, the next probe attempt fires normally.
4. **Threshold-trip path is unchanged.** When a probe *does* fire and *does* fail with a dead-peer signal (idle period + peer genuinely silent), the existing trip logic runs as is.
5. **Markers are domain-internal, no platform contract.** `markUserOpStarted/Ended` live on `LifecycleClient`. `BlueyConnection` is the sole caller. Other consumers (peer module, etc.) reach the lifecycle through `BlueyConnection`, so they get the right behaviour transparently.

## Architecture

Two files change. Neither edit touches the platform interface or native code.

### `LifecycleClient` — counter + deferral

New private field and methods:

```dart
/// Count of user-initiated ops currently pending on this connection.
/// Probes are deferred while > 0 — see I097. Maintained by
/// [markUserOpStarted] / [markUserOpEnded] from [BlueyConnection].
int _pendingUserOps = 0;

/// Called by [BlueyConnection] when a user GATT op is dispatched.
/// While the count is > 0, scheduled probes defer rather than fire,
/// because the in-flight op is itself an outstanding peer probe and
/// its outcome will tell us about the peer's liveness.
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

The deferral path uses the same reschedule cadence as the existing `_monitor.timeUntilNextProbe() > 0` early-return path: one `activityWindow` later. No new state machine, no new tunables.

Stop semantics stay correct: `stop()` doesn't need to touch `_pendingUserOps` because once `_isRunning` is false, `_sendProbeOrDefer` early-returns on the first `_heartbeatCharUuid == null` check. Lingering ops in `BlueyConnection` will still call `markUserOpEnded` (decrementing harmlessly), and the count is per-instance — discarded when the connection is replaced.

### `BlueyConnection` — wrap user-op call sites

Each user-op method on `BlueyConnection` (the same call sites that already invoke `_lifecycle?.recordActivity()` on success) wraps the platform call in a `try { markStarted; await; recordActivity } finally { markEnded; }`. The four current sites (`bluey/lib/src/connection/bluey_connection.dart:317, :364, :376, :619`) all need the wrapper.

Pseudo-shape (concrete code per site differs by op type):

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
} finally {
  _lifecycle?.markUserOpEnded();
}
```

The four sites cover read, write, set-notification, and the notification-stream callback (the last is for activity recording on inbound notifications — that one *doesn't* wrap because notifications aren't outbound user ops). The plan will list each site explicitly with the exact diff.

Edge case: `_lifecycle` is null when no Bluey peer is configured on the connection. The `?.markUserOpStarted()` chain just no-ops — counter stays at zero on the (non-existent) lifecycle, deferral logic doesn't apply. Safe.

## TDD

Tests live in `bluey/test/connection/`. Three layers.

### `LifecycleClient` (`bluey/test/connection/lifecycle_client_test.dart`)

Three new tests:

1. **Probe deferred while user op pending.** Set up a tracked client with a future probe deadline. Call `markUserOpStarted()`. Advance time past the deadline. Verify: no probe write attempted.
2. **Probe fires after user op ends.** Same setup. Call `markUserOpStarted()`, advance, verify deferred. Call `markUserOpEnded()`. Advance one `activityWindow`. Verify: probe write attempted.
3. **Multiple concurrent user ops correctly counted.** Two `markUserOpStarted()` calls. One `markUserOpEnded()`. Verify probe is still deferred. Second `markUserOpEnded()`. Verify probe fires on the next tick.

These pin the deferral contract.

### `BlueyConnection` (`bluey/test/connection/bluey_connection_test.dart`)

Two new tests covering the wrapping:

4. **User op success → markStarted called before, markEnded called after.** Use a fake platform + a spy `LifecycleClient` (or a `LivenessMonitor`-like double that exposes the counter). Issue a write that succeeds. Verify: counter went up then down.
5. **User op failure → markEnded still called.** Make the platform throw. Verify the counter still returns to zero (no leak).

These pin the connection-side accounting.

### Existing tests

Existing `LifecycleClient` and `BlueyConnection` tests continue to pass — the new code is additive. No semantic changes to existing methods.

## Caveats

### What if a user op stalls forever?

The user op itself has a per-op timeout (10 s default at OpSlot level). When it expires, `markUserOpEnded` fires (in the `finally`), the count returns to zero, and the next probe tick can fire. Worst case we delay dead-peer detection by one user-op timeout window — reasonable, since the user op's own timeout is itself a dead-peer signal.

### What if the user dispatches ops back-to-back without idle gaps?

Heartbeats wouldn't fire — but that's fine, because the constant op stream is itself the liveness signal. The server-side I079 fix already handles this on the receiving end (server tolerates as long as activity flows). Symmetric: client doesn't need a redundant probe.

### What if every user op fails (all timeout, none succeed)?

In a tight loop where the user issues ops back-to-back and each one times out:

- Probes defer continuously (the count is > 0 most of the time; the gap between ops is sub-millisecond in a tight `await` loop).
- `recordActivity` is never called (no successful ops).
- `recordProbeFailure` is never called (no probes fired to fail).
- **The lifecycle layer's `onServerUnreachable` is never triggered.**

This is *intentional* and is the central trade-off of the design. The lifecycle layer's purpose is *idle detection* — to catch a peer that has gone silent. If the user code is actively trying to talk to the peer, the user code IS the probe: each op's exception (timeout, disconnect, status-failed) is itself a dead-peer signal that the user already observes. The lifecycle layer firing a redundant `onServerUnreachable` on top would be either:

- Race-prone (if it tears down a connection the user is mid-retry on), or
- Redundant (if the user has already noticed every op failing and reacted).

So the right behaviour is: while the user is actively asking the peer questions, trust the user to handle the answers. The lifecycle layer's tear-down resumes when the user goes quiet.

This *does* mean a connection where the peer is dead AND the user keeps queuing failing ops will not see a lifecycle-layer disconnect — it will see N consecutive `GattOperationTimeoutException`s from the user's perspective. The user's own retry / give-up policy is what governs in that case. We consider this the correct division of responsibility: the library reports the truth; the application decides what to do with it.

(For applications that want the old behaviour — automatic disconnect on N consecutive failures regardless of source — that's an application-layer policy, not a lifecycle-protocol policy. Out of scope here.)

### Edge case: disconnect mid-op

When the connection drops mid-op, the platform layer drains the in-flight op with `GattOperationDisconnectedException`. That fires the `finally`, decrementing the counter. `LifecycleClient` is then stopped via `onServerUnreachable` or the platform's disconnect event — no further probes scheduled. Counter state on the dead `LifecycleClient` is irrelevant.

### Why this is structurally simpler than the heuristic

The earlier draft proposed a `livenessWindow` heuristic. That approach trusts a time-based proxy ("recent activity exists, so probably alive") to decide whether to discount a misclassified probe. This approach addresses the misclassification by preventing the misclassified probe from firing in the first place. No magic numbers, no proxy semantics — direct cause-and-effect.

## Risks and rollback

**Risks:**

- A `markUserOpStarted` without matching `markUserOpEnded` would leak the counter, suppressing probes forever. Mitigation: `try { ... } finally { ... }` wrapping at every call site, plus the test that asserts no leak on op failure.
- A probe is *correctly* needed during a long-running user op (e.g., 60 s OTA write) — peer dies mid-op. The user op's own timeout (10 s default) catches this before the missing probes matter. No new failure mode.

**Rollback:** revert the two-file change. No state, no migration, no schema.

## Backlog hygiene

After landing:
1. Update `docs/backlog/I097-client-opslot-starves-heartbeat.md`: `status: open` → `fixed`, add `fixed_in: <sha>`, replace Notes with: "Fixed in `<sha>` by deferring heartbeat probes while user ops are in flight on the same connection. Mirror image of I079: while the client has an outstanding op to the peer, that op is itself an outstanding peer probe — firing a redundant heartbeat would only contend with it on CoreBluetooth's per-peripheral write queue. The deferral eliminates the contention that produced the false-positive."
2. Update `docs/backlog/README.md`: move I097 from Open → Fixed.
3. Update the example app's `failureInjection.readingResults`: now that I097 is fixed, the "tolerant recovery" outcome is reachable with `maxFailedHeartbeats=3` or higher. Restore the original two-scenario description (Strict → cascade, Tolerant → recovery) and remove the I097 caveat. One-file edit on the same branch.
