# Client-Side LifecycleClient: Time-Based Peer-Silence Detection (I097)

**Status:** proposed
**Date:** 2026-04-26
**Scope:** `bluey` package — `LifecycleClient`, `LivenessMonitor`, `BlueyConnection`. Removes the `maxFailedHeartbeats` public parameter and adds `peerSilenceTimeout`. No platform-interface change, no native change, no protocol change.
**Backlog entry:** [I097](../../backlog/I097-client-opslot-starves-heartbeat.md).

## Problem

The failure-injection stress test reliably tears down the client connection at any `maxFailedHeartbeats` setting, because heartbeat probes accumulate failures faster than tolerance can absorb them.

Walking the chain: server drops echo #0 → CoreBluetooth's per-peripheral write-with-response queue holds the next heartbeat (CB serialises writes-with-response, doesn't dispatch the next until the in-flight one gets a `didWriteValueFor` callback) → heartbeat sits in CB's internal queue, never goes on the wire → our OpSlot's per-op timer fires → heartbeat surfaces as `GattOperationTimeoutException` to `LifecycleClient`.

The current count-based mechanism (`maxFailedHeartbeats` consecutive failures) has two structural problems beyond the immediate bug:

1. **Asymmetric trip rate by failure source.** Heartbeat probes have a 10 s OpSlot timeout plus 5 s reschedule = 15 s per probe cycle. User-op failures can occur in tight loops with no inter-failure gap. Without rate-limiting, a busy connection can trip much faster than an idle one.
2. **Misleading user-facing semantics.** `maxFailedHeartbeats` = 3 looks like "3 strikes," but the actual time-to-disconnect depends on probe cadence, op timeouts, and traffic patterns. A user wanting "disconnect after N seconds of silence" can't express it cleanly.

## Root cause

The lifecycle layer treats heartbeat probes as the *only* source of dead-peer evidence and counts failures rather than measuring silence. This produces three problems:

1. **Redundant probing during active use.** While a user op is in flight, that op is itself an outstanding peer probe — its outcome (success, status-failure, wire-timeout, or disconnect) tells us about the peer. Layering an additional heartbeat probe on top adds nothing on the *evidence* side and creates the queue contention the bug describes on the *cost* side.
2. **Missed signals from user ops.** When a user op times out, that timeout is a dead-peer signal in exactly the same way a timed-out heartbeat is — "we sent something, the peer didn't answer." Today's design discards this signal.
3. **Count semantics conflate frequency with duration.** Threshold = 3 means different things at different traffic patterns. A time-based contract is more predictable and matches user mental models.

## Symmetry with I079 (and where the symmetry ends)

I079 (server-side, fixed) refused to declare a client dead while the server held a pending request from it — using "the link is provably alive because it just delivered a request" as the override. I097 strengthens the same principle on the client side: user ops are first-class liveness signals.

But the underlying *trigger* semantics differ between sides, for principled reasons:

| Side | Trigger model | Why |
|---|---|---|
| Server (`LifecycleServer`) | Watchdog from last activity. Timer counts up since last heartbeat receipt; pending requests pause the timer; trip when interval elapsed without activity AND nothing pending. | Server passively *receives* heartbeats. There are no per-event failures — only absence of events. |
| Client (`LifecycleClient` post-fix) | Death-watch from first failure. Timer armed only on failure event; cancelled on any success; ignores pending state. | Client *initiates* exchanges and observes responses. Failure events exist explicitly (op timeouts). Pausing on pending ops would create a trap where rapid failures never trip. |

Both sides:
- Track pending exchanges (server: per-request-id Set; client: simple count).
- Reset on peer-originated activity.
- Fire a callback on prolonged silence.

The shared concept is **peer-silence detection with pending-exchange awareness**. The implementations diverge because the *direction of initiation* differs. Forcing a unified implementation would either bloat the abstraction or distort one side.

The DDD win comes from shared **vocabulary** ("peer silence," "pending exchange," "watchdog" / "death watch"), shared **protocol layer** (already in `bluey/lib/src/lifecycle.dart`), and explicit cross-references between the two sides — not from extracting shared *code*.

## Goals

Three complementary mechanisms on the client side:

1. **Defer probes while user ops pending.** `LifecycleClient` tracks a count of in-flight user ops via `markUserOpStarted/Ended`. While count > 0, scheduled probes defer rather than fire — avoids CoreBluetooth queue contention.

2. **User-op outcomes feed the silence detector.** When a user op times out, that's a dead-peer signal indistinguishable from a timed-out heartbeat. When a user op succeeds, that's activity (already handled via `recordActivity`).

3. **Time-based silence detection.** The `LivenessMonitor` (renamed `PeerSilenceMonitor`, since "liveness" is a poor name post-refactor) tracks `_firstFailureAt`. On any failure event from any source, sets `_firstFailureAt` (if null) and arms a `Timer` for `firstFailureAt + peerSilenceTimeout`. Any activity (success / notification / probe ack) clears `_firstFailureAt` and cancels the timer. Timer firing → `onServerUnreachable`.

## Non-goals

- **Not changing the platform interface.** No new exception types, no new fields. Existing `GattOperationTimeoutException` is the signal we route into the silence detector.
- **Not surfacing CoreBluetooth queue state from iOS.** Avoided in favour of the higher-level reframe.
- **Not changing the heartbeat write protocol.** Same characteristic, same value, same scheduling. Heartbeats still serve the secondary purpose of feeding the server's I079 timer during idle periods.
- **Not unifying client and server silence-detection implementations.** Trigger semantics differ; sharing would distort.
- **Not changing `_isDeadPeerSignal`'s heartbeat-probe taxonomy.** Heartbeats use the existing wide net (timeout / disconnect / statusFailed). User ops use a narrower predicate (timeout only).

## Decisions locked

1. **Replace `maxFailedHeartbeats` (count) with `peerSilenceTimeout` (Duration).** The library has no consumers outside `bluey/example`; we update the example app's tolerance segments to express durations. Default = `4 × activityWindow` ≈ 20 s (rationale: covers a typical 10 s user-op stall with margin, well past the failure-injection scenario timing). Public on `bluey.connect()` and `bluey.peer()`.
2. **Rename `LivenessMonitor` → `PeerSilenceMonitor`.** Domain-accurate naming; "liveness" was vague.
3. **Counter, not boolean, for in-flight user ops.** A connection can have multiple ops in flight across different OpSlots — counter handles concurrent ops naturally.
4. **`finally`-wrapped accounting in `BlueyConnection`.** `try { mark; await op; on success: recordActivity } catch (error) { recordUserOpFailure(error); rethrow } finally { unmark }` so a thrown exception still decrements the counter.
5. **Different predicate for user-op failures vs heartbeat failures.** Heartbeats: existing wide net (timeout / disconnect / statusFailed). User ops: timeout only. Disconnect is handled by the platform-level disconnect callback (separate path); statusFailed at the user-op level can mean ATT errors that don't imply dead peer.
6. **Death-watch ignores pending state.** Once `_firstFailureAt` is set, the timer runs to completion regardless of whether subsequent user ops start or end. Cancelled only by success. Avoids the all-ops-fail trap (where pausing on pending would mean the timer never fires when a user keeps queuing failing ops).
7. **Single firing of `onServerUnreachable`.** When the timer fires, the lifecycle stops itself and fires the callback once. Subsequent failures are no-ops.

## Architecture

Three files change. None touch the platform interface or native code.

### `LivenessMonitor` → `PeerSilenceMonitor` (renamed + restructured)

The existing `LivenessMonitor` had count-based semantics. Post-refactor, it's a time-based silence detector.

Public surface:

```dart
class PeerSilenceMonitor {
  final Duration peerSilenceTimeout;
  final void Function() onSilent;     // fired when timer expires
  final DateTime Function() _now;

  Duration _activityWindow;            // probe scheduling cadence (unchanged)
  DateTime? _lastActivityAt;
  DateTime? _firstFailureAt;           // null = no death watch active
  Timer? _deathTimer;
  bool _probeInFlight = false;
  bool _running = false;

  PeerSilenceMonitor({
    required this.peerSilenceTimeout,
    required this.onSilent,
    required Duration activityWindow,
    DateTime Function()? now,
  });

  void start();
  void stop();    // cancels _deathTimer

  // — Activity reset path —
  void recordActivity();         // clears _firstFailureAt, cancels timer
  void recordProbeSuccess();     // alias for recordActivity + clears probeInFlight

  // — Failure / silence path —
  void recordPeerFailure();      // sets _firstFailureAt if null, arms timer
  void cancelProbe();            // transient: just clears probeInFlight, no failure recording
  void markProbeInFlight();

  // — Probe scheduling (unchanged) —
  Duration get activityWindow;
  Duration timeUntilNextProbe();
  void updateActivityWindow(Duration window);

  // — Test inspection —
  @visibleForTesting bool get probeInFlight;
  @visibleForTesting DateTime? get lastActivityAt;
  @visibleForTesting DateTime? get firstFailureAt;
  @visibleForTesting bool get isDeathWatchActive;
}
```

Implementation sketch of the core methods:

```dart
void recordPeerFailure() {
  if (!_running) return;
  _firstFailureAt ??= _now();
  if (_deathTimer != null) return;  // already armed
  final deadline = _firstFailureAt!.add(peerSilenceTimeout);
  final remaining = deadline.difference(_now());
  if (remaining.isNegative || remaining == Duration.zero) {
    _deathTimer = null;
    onSilent();
    return;
  }
  _deathTimer = Timer(remaining, _fireSilent);
}

void _fireSilent() {
  _deathTimer = null;
  if (!_running) return;
  onSilent();
  _running = false;       // single-fire
}

void recordActivity() {
  _firstFailureAt = null;
  _deathTimer?.cancel();
  _deathTimer = null;
  _lastActivityAt = _now();
}
```

Note that `recordActivity()` no longer involves a counter; it just clears the failure timestamp.

### `LifecycleClient` — pending tracking, deferral, user-op outcome handling

```dart
int _pendingUserOps = 0;

void markUserOpStarted() {
  _pendingUserOps++;
}

void markUserOpEnded() {
  if (_pendingUserOps > 0) _pendingUserOps--;
}

/// Called by [BlueyConnection] when a user GATT op fails. Filters by
/// predicate: timeouts feed the silence detector; other errors are
/// no-ops at this layer (e.g. WriteNotPermitted is application-level,
/// not dead-peer; disconnect is handled by the platform callback).
void recordUserOpFailure(Object error) {
  if (!_isRunning) return;
  if (error is! platform.GattOperationTimeoutException) return;
  _monitor.recordPeerFailure();
}
```

Modify `_sendProbeOrDefer`:

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

The `onServerUnreachable` callback that LifecycleClient takes is now invoked via `PeerSilenceMonitor.onSilent` rather than from inside `_sendProbe`'s catchError. The catchError just routes timeouts to `_monitor.recordPeerFailure()`.

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

The four current `recordActivity` sites (`bluey_connection.dart:317, :364, :376, :619`) all need the wrapper, except the notification-stream callback at `:619` (notifications aren't outbound user ops — keeps just `recordActivity`).

### Public API change in `Bluey`

`bluey.connect()` and `bluey.peer()` parameter rename:

```dart
// Before:
Future<Connection> connect(
  Device device, {
  Duration? timeout,
  ConnectionSettings settings,        // contained int maxFailedHeartbeats
}) ...

// After:
Future<Connection> connect(
  Device device, {
  Duration? timeout,
  ConnectionSettings settings,        // now contains Duration peerSilenceTimeout
}) ...
```

`ConnectionSettings`:

```dart
// Before:
final int maxFailedHeartbeats;
const ConnectionSettings({this.maxFailedHeartbeats = 1});

// After:
final Duration peerSilenceTimeout;
const ConnectionSettings({
  this.peerSilenceTimeout = const Duration(seconds: 20),
});
```

The example app's `ConnectionSettingsCubit` and `ToleranceControl` segmented control are updated to express durations instead of counts. Three segments:

| Old label / count | New label / duration |
|---|---|
| Strict (1) | Strict (10 s) |
| Tolerant (3) | Tolerant (30 s) |
| Very tolerant (5) | Very tolerant (60 s) |

The numeric values are illustrative; final values can be tuned during implementation. The default (20 s) sits between Strict and Tolerant.

## TDD

Tests live in `bluey/test/connection/`.

### `PeerSilenceMonitor` (`bluey/test/connection/liveness_monitor_test.dart` — file kept, contents updated; if rename is desired, that's a follow-up)

Five new / rewritten tests:

A. **`recordPeerFailure` arms timer.** Fresh monitor, started, no activity. Call `recordPeerFailure()`. Verify `firstFailureAt` is non-null and `isDeathWatchActive` is true.
B. **Activity cancels death watch.** Failure → activity. Verify `firstFailureAt` is null and `isDeathWatchActive` is false.
C. **Multiple failures don't reset deadline.** Failure at t=0, failure at t=5. Verify `firstFailureAt` is still 0 (the *first* failure), and timer fires at 0 + peerSilenceTimeout.
D. **`onSilent` fires after `peerSilenceTimeout`.** Failure at t=0, advance fakeAsync past peerSilenceTimeout. Verify callback fired exactly once.
E. **`stop` cancels timer; `onSilent` does not fire.** Failure → stop → advance time. Verify callback not called.

### `LifecycleClient` (`bluey/test/connection/lifecycle_client_test.dart`)

Five new tests:

1. **Probe deferred while user op pending.** Tracked client, future probe deadline. `markUserOpStarted()`, advance past deadline. Verify no probe write attempted.
2. **Probe fires after user op ends.** Same setup. `markUserOpStarted()`, advance, verify deferred. `markUserOpEnded()`. Advance one `activityWindow`. Verify probe attempted.
3. **Multiple concurrent user ops correctly counted.** Two `markUserOpStarted()` calls, one `markUserOpEnded()` — probe still deferred. Second `markUserOpEnded()` — probe fires.
4. **`recordUserOpFailure` with timeout feeds the monitor.** Spy on the monitor (or inject a fake). Call with `GattOperationTimeoutException`. Verify `recordPeerFailure` was called.
5. **`recordUserOpFailure` with non-timeout is a no-op.** Same setup, pass `GattOperationStatusFailedException` or generic exception. Verify `recordPeerFailure` was NOT called.

### `BlueyConnection` (`bluey/test/connection/bluey_connection_test.dart`)

Three new tests covering the wrapping:

6. **User op success: markStarted, recordActivity, markEnded.**
7. **User op timeout: markStarted, recordUserOpFailure(timeout), markEnded.**
8. **User op other failure: markStarted, recordUserOpFailure(other) (filtered out by predicate), markEnded.**

### Existing tests

Existing tests need updates for the renamed `maxFailedHeartbeats` parameter and the count-based `recordProbeFailure` mechanism. Specifically:
- Any test that passes `maxFailedHeartbeats: N` becomes `peerSilenceTimeout: durationN`.
- Tests that asserted on `_consecutiveFailures` or trip-after-N-count-semantics get rewritten to assert on the time-based behavior.

## Caveats

### Why time-based wins over count-based

A predictable, single-knob contract — "if the peer is silent for X seconds, the connection is declared dead" — beats a multi-knob count-with-rate-limiting design on every axis we evaluated:

- **User mental model:** "30 seconds" is concrete; "3 failures, rate-limited to 5 s, give or take 25 % depending on traffic pattern" is not.
- **DDD purity:** the domain concept is *peer silence*, a duration. A wall-clock timer expresses that directly.
- **Implementation simplicity:** one timer, one timestamp, no rate-limit gating logic.
- **Symmetry with I079:** server uses a wall-clock timer keyed off interval; client now uses one keyed off silence-timeout. Different trigger conditions but same *kind* of mechanism.

### What if a user op stalls forever?

The user op itself has a per-op timeout (10 s default at OpSlot level). When it expires, `recordUserOpFailure` arms the death watch (if not already armed) and `markUserOpEnded` fires (in `finally`). If subsequent ops keep failing, the death watch runs to completion and trips at `firstFailureAt + peerSilenceTimeout`, regardless of pending state.

### Failure-injection scenario walkthrough

Default settings (`peerSilenceTimeout = 20 s`):

- t=0: prologue Reset succeeds → `recordActivity` → `firstFailureAt = null`.
- t=ε: prologue DropNext succeeds → `recordActivity`.
- t=ε: echo #0 sent, server drops it.
- t=10: echo #0 times out → `recordUserOpFailure(timeout)` → `firstFailureAt = 10`, timer armed for t=30.
- t=10+ε: echo #1 starts. count=1. Probe deferred (existing in-flight op) — irrelevant to the death watch.
- t=10+latency: echo #1 succeeds → `recordActivity` → `firstFailureAt = null`, timer cancelled.
- Subsequent echoes succeed, no further failures.
- Test ends with: 1 timeout + 9 successes. **Recovery.**

`peerSilenceTimeout = 10 s` ("Strict"):

- t=10: echo #0 fails. Timer armed for t=20.
- t=20: timer fires → `onSilent` → disconnect.
- Echoes still queued or attempted after t=20 fail with `DisconnectedException`.
- User sees: 1 timeout + N-1 disconnects. **Tight policy as intended.**

All ops fail (peer truly dead), `peerSilenceTimeout = 30 s`:

- t=10: op #1 fails. `firstFailureAt = 10`, timer for t=40.
- t=20, 30, ...: subsequent ops fail. `firstFailureAt` unchanged. Timer continues to t=40.
- t=40: timer fires → disconnect. **Authoritative detection.**

### Server-side stays as-is

`LifecycleServer` continues to use its current watchdog-from-last-activity model. The semantics differ from the client side because the server doesn't observe explicit failure events — it observes presence-or-absence of heartbeats. The two sides share the *concept* (peer silence detection with pending awareness) but the *trigger* differs by direction of initiation.

A short cross-reference doc-comment on each lifecycle class will point to the other as a sibling implementation of the shared concept. No code is shared between them beyond what's already in `bluey/lib/src/lifecycle.dart` (protocol layer).

## Risks and rollback

**Risks:**

- A `markUserOpStarted` without matching `markUserOpEnded` would leak the counter. Doesn't affect the death watch (which is failure-triggered, not pendency-triggered), but does suppress probes from firing. Mitigation: `try { ... } finally { ... }` wrapping at every call site, plus tests for the no-leak invariant on op failure.
- The `peerSilenceTimeout = 20 s` default is a guess. If real-world use shows it's too short (legitimate slow peers tripping incorrectly) or too long (slow detection of dead peers in the field), it can be tuned without API changes.

**Rollback:** revert the multi-file change. Public API change means consumers (the example app) need to migrate, but there's only one consumer.

## Backlog hygiene

After landing:

1. Update `docs/backlog/I097-client-opslot-starves-heartbeat.md`: `status: open` → `fixed`, add `fixed_in: <sha>`, replace Notes with: "Fixed in `<sha>` by switching the client-side lifecycle from count-based heartbeat-failure detection to time-based peer-silence detection. Heartbeat probes defer while user ops are in flight; user-op timeouts feed the same silence detector that heartbeat-probe timeouts feed; the detector is a wall-clock death-watch from first failure that resets on any successful exchange."
2. Update `docs/backlog/README.md`: move I097 from Open → Fixed.
3. Update the example app's `failureInjection.readingResults`: now that I097 is fixed, the recovery scenario is reachable. Restore the original two-scenario description (Strict → cascade, Tolerant → recovery) and remove the I097 caveat. One-file edit on the same branch.
4. Update the example app's `ToleranceControl` and `ToleranceIndicator`: segments now express durations ("Strict (10 s)" / "Tolerant (30 s)" / "Very tolerant (60 s)"). The labels and underlying values change; the UI shape is unchanged.
5. Optional follow-up: rename the file `liveness_monitor.dart` → `peer_silence_monitor.dart`. Not required for correctness; nice to have for naming consistency.
