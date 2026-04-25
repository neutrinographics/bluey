# Server-Side Lifecycle: Pending-Request Tolerance (I079)

**Status:** proposed
**Date:** 2026-04-25
**Scope:** `bluey` package — `LifecycleServer` + `BlueyServer` wiring only. No platform-interface change, no native change, no client-side change, no protocol change.
**Backlog entry:** [I079](../../backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md).

## Problem

During the failure-injection / timeout-probe stress tests (iOS client → Android server), a deliberately-stalled write reliably tears the connection down mid-test:

1. Client writes `DelayAckCommand(delayMs: 12000)` to the stress characteristic, `withResponse: true`.
2. Server's stress handler enters `Future.delayed(12s)` before calling `respondToWrite`.
3. During those 12 s, no further traffic moves on the link in either direction. The client is parked on its OpSlot waiting for the response; the server is parked in its app-level delay.
4. Server's `LifecycleServer` heartbeat-timeout timer fires at ~10 s with no client traffic seen → `onClientGone(clientId)` → connection torn down.
5. At t=12 s the server finally calls `respondToWrite`, but the link is already gone.

The pathological framing: **the server is tearing down a client over silence the server itself is causing.** The client did nothing wrong. The link is fine. The server's own application layer is sitting on the request.

Reproduction: any test or real-world flow where a server-app response takes longer than `lifecycleInterval` (~10 s by default). File transfers, OTA, slow database reads, deliberately-stalled responses for testing — all reproduce this.

## Root cause

`LifecycleServer` defines client liveness in terms of *events* (request arrivals via `recordActivity(clientId)`). It has no notion of *state* — specifically, the state of "actively servicing a request from this client."

```dart
// lifecycle_server.dart:139–148
void _resetTimer(String clientId) {
  final interval = _interval;
  if (interval == null) return;
  _heartbeatTimers[clientId]?.cancel();
  _heartbeatTimers[clientId] = Timer(interval, () {
    _heartbeatTimers.remove(clientId);
    onClientGone(clientId);
  });
}
```

When a request arrives, the timer is reset (good). When the timer expires, `onClientGone` is invoked unconditionally — *even if the server is at that very moment holding a pending request from the client it's about to declare dead.*

The server already has the information it needs to avoid this: it's literally holding the platform `requestId`, waiting for the app to call `respondToRead` / `respondToWrite`. That signal is just never wired into `LifecycleServer`.

The I079 entry's prose suggests a client-side fix (route successful user ops into `LivenessMonitor.recordActivity`). That fix is **already in tree** — see `bluey/lib/src/connection/bluey_connection.dart:317`, `:364`, `:376`, `:619`. It does not address this scenario, because during the 12 s stall the user op has not *succeeded* yet; the client cannot fire `recordActivity` for an op it hasn't completed. The bug fundamentally lives on the server side, where a pending request is direct evidence of liveness that the lifecycle policy currently ignores.

## Non-goals

- **Not changing the protocol.** Heartbeat characteristic UUID, value bytes, interval semantics, and `LifecycleClient` behavior all stay as they are.
- **Not changing the heartbeat interval default or making `lifecycleInterval` more configurable.** The existing knob is sufficient; tuning it is brittle (the I079 entry explicitly rejects this as fix sketch #3).
- **Not introducing a "user-op tolerance" extension knob.** Pending-request suppression is the single mechanism; it does not need a sibling parameter.
- **Not touching the client-side `LifecycleClient` / `LivenessMonitor`.** The recently-landed I077 / I073 / I078 / I070 fixes are correct as far as they go.
- **Not extending the fix to handle non-request liveness signals (notifications, indications, MTU events).** The pending-request set is keyed on platform `requestId`, which only requests carry. Other signals continue to flow through `recordActivity` unchanged.

## Decisions locked during brainstorming

1. **Activity is a state, not just an event.** A client with one or more pending requests is, by definition, currently engaged with the server; the server cannot legitimately accuse it of silence.
2. **Single mechanism, not layered.** No second timer, no extension knob. The existing per-client timer is paused while pending > 0 and resumed (with a fresh interval) the moment pending hits zero.
3. **Set-based, not counter-based.** Track `Map<String, Set<int>> _pendingRequests` keyed by `requestId`. This makes `requestCompleted` idempotent and makes diagnostic logging straightforward (we can name the leaked id if one is left behind).
4. **Untracked-client guard preserved.** `requestStarted` is a no-op for clients that have not previously sent a heartbeat — same semantics as the existing `recordActivity`. Lifecycle policy stays opt-in via heartbeat protocol participation; generic BLE centrals never get implicitly tracked.
5. **Disconnect clears pending state.** `cancelTimer(clientId)` and `_handleClientDisconnected(clientId)` (in `BlueyServer`) both clear the per-client pending set, so a reconnect / new client cannot inherit phantom pending IDs.
6. **iOS-server detection gap accepted.** See "Caveats" below — the regression is narrow and the false-positive being fixed is routine.

## Domain model

The missing concept is **the open exchange**: a request the server has accepted but not yet responded to. It has a clear lifecycle (start → complete) and identity (the platform `requestId`). It belongs inside the GATT Server bounded context, owned by `LifecycleServer`.

### Ubiquitous language addition

| Use | Avoid |
|-----|-------|
| Pending request | "in-flight op", "outstanding write", "blocking call" |

The phrase **pending request** matches the BLE / ATT vocabulary (a request is "pending" until its response goes out) and reads cleanly in the `LifecycleServer` API.

### Invariant the model enforces

> While a client has any pending request, that client's heartbeat-timeout timer is paused.

The timer represents *unjustified silence*. A pending request is *justified silence* — the client is waiting on us, not the other way around. When the last pending request for a client completes, silence resumes meaning, so we re-arm the timer with a fresh interval.

## Architecture

Two files change. No platform-interface changes, no native changes.

### `LifecycleServer` — replaces `Map<String, Timer>` with `Map<String, _ClientLiveness>`

The current state field `Map<String, Timer> _heartbeatTimers` overloads the map keys as the "tracked client" signal. Once we add a paused-timer state (during pending requests), that overload breaks: a tracked client with all requests pending would have no map entry, looking untracked. The right shape is a small private value class that holds both pieces of state per client:

```dart
class _ClientLiveness {
  Timer? timer;                       // null while paused
  final Set<int> pendingRequests = {};
}

final Map<String, _ClientLiveness> _clients = {};
```

Map-key membership becomes the unambiguous "tracked" signal: a client is tracked iff `_clients.containsKey(id)`. The `Timer?` being nullable cleanly expresses paused.

New API:

```dart
/// Marks that the server has accepted a request from [clientId] and owes
/// a response. Pauses the client's heartbeat-timeout timer until all
/// pending requests for the client have completed.
///
/// No-op for untracked clients (no prior heartbeat). Lifecycle policy is
/// opt-in: a generic BLE central reading a hosted service must not be
/// implicitly tracked as a Bluey peer.
void requestStarted(String clientId, int requestId);

/// Marks a previously-started request as complete. If the client has no
/// further pending requests, restarts the heartbeat-timeout timer with a
/// fresh interval (treated as activity).
///
/// Idempotent: completing an unknown id is a no-op.
void requestCompleted(String clientId, int requestId);
```

Modified internals:

- `_resetTimer(clientId)` cancels the existing `Timer?` unconditionally; only re-arms when `_clients[clientId]!.pendingRequests.isEmpty`. Otherwise the client's `timer` stays null (paused).
- `requestStarted` is the *only* place that adds to the pending set. It also calls `_resetTimer` (which now cancels and leaves paused).
- `requestCompleted` removes the id; if the set becomes empty, calls `_resetTimer` (which now re-arms).
- `cancelTimer(clientId)` removes the entire `_clients[clientId]` entry — both timer and pending set go away.
- `dispose()` walks `_clients.values` cancelling each timer, then clears the map.
- `recordActivity(clientId)` semantics unchanged. Still the right call for control-service writes (handled inline by `_resetTimer` directly) and write-without-response (no response owed).
- `handleWriteRequest` (heartbeat path) creates the `_ClientLiveness` entry if absent, then `_resetTimer`.

The migration from `Map<String, Timer>` to `Map<String, _ClientLiveness>` is mechanical: every existing access pattern has a one-line equivalent on the new shape.

### `BlueyServer` — wires request lifecycle into `LifecycleServer`

Three call sites change:

1. **Forwarded read requests** (`_platformReadRequestsSub`, currently lines 106–111). Reads always need a response; on arrival, call `_lifecycle.requestStarted(req.centralId, req.requestId)` instead of `recordActivity`.
2. **Forwarded write requests** (`_platformWriteRequestsSub`, currently lines 113–118). Branch on `responseNeeded`:
   - `responseNeeded == true` → `_lifecycle.requestStarted(req.centralId, req.requestId)`.
   - `responseNeeded == false` → `_lifecycle.recordActivity(req.centralId)` (no response owed; just an activity event, as today).
3. **Response paths** (`respondToRead` / `respondToWrite`). Both now call `_lifecycle.requestCompleted(client._platformId, request.internalRequestId)` **before** the platform `respondTo*` call. The lifecycle obligation is discharged the moment the app commits to a response; whether the platform layer successfully delivers it is a separate concern. Calling `requestCompleted` first (rather than after) guarantees the pending set is drained even if the platform call throws (stale request id, platform in an error state, etc.). `request.client` is already a `BlueyClient`; the cast is safe.

`_handleClientDisconnected` already calls `_lifecycle.cancelTimer(clientId)`. With the change above, that single call now clears both the timer and the pending set for the client.

### Why the wiring is in `BlueyServer`, not pushed lower

`LifecycleServer` is internal to the GATT Server bounded context and shouldn't know about `ReadRequest` / `WriteRequest` (those are `BlueyServer`'s public domain). `BlueyServer` is the natural seam: it already routes requests in (subscriptions on `_platform.readRequests` / `_platform.writeRequests`) and routes responses out (`respondToRead` / `respondToWrite`). Both ends of the exchange pass through it. No additional indirection is needed.

## TDD plan

Tests live in `bluey/test/gatt_server/lifecycle_server_test.dart` and `bluey/test/gatt_server/bluey_server_test.dart`. The existing pattern uses `fake_async` and `FakeBlueyPlatform`.

### Red → Green order

**Test 1 — the bug, expressed.**
With a 10 s interval and a tracked client, calling `requestStarted(clientId, 42)` followed by `async.elapse(30s)` must not fire `onClientGone`. Drives the new field, `requestStarted`, and the suppression in `_resetTimer`.

**Test 2 — completion restarts the clock.**
After test 1's setup, `requestCompleted(clientId, 42)` followed by `async.elapse(9s)` keeps the client alive; `async.elapse(2s)` more (total 11s past completion) fires `onClientGone`. Drives the "treat completion as activity" path.

**Test 3 — concurrent requests are tracked individually.**
`requestStarted(client, 1); requestStarted(client, 2); requestCompleted(client, 1)` — timer must remain suppressed (request 2 is still open). After `requestCompleted(client, 2)` and elapsing the interval, `onClientGone` fires. Drives the set semantics.

**Test 4 — disconnect clears pending state.**
`requestStarted(client, 1); cancelTimer(client); requestCompleted(client, 1)` — the spurious completion must not resurrect the timer. Drives `cancelTimer` clearing the pending set.

**Test 5 — untracked-client guard.**
`requestStarted('stranger', 1)` followed by `async.elapse(30s)` — no spurious tracking, no `onClientGone`. Drives the untracked-client no-op (mirrors the existing `recordActivity` guard test).

**Test 6 — `BlueyServer` arrival wiring (read).**
Drive a `PlatformReadRequest` through `fakePlatform.readRequests`. Track the client first (heartbeat). Verify `LifecycleServer`'s pending set contains the request id. Drive `respondToRead` → set is empty.

**Test 7 — `BlueyServer` arrival wiring (write-with-response).**
Same, with `responseNeeded: true` → `requestStarted` invoked.

**Test 8 — `BlueyServer` arrival wiring (write-without-response).**
With `responseNeeded: false` → `recordActivity` invoked, pending set unchanged.

**Test 9 — end-to-end stall scenario (`BlueyServer`).**
Track a client. Drive a write-with-response arrival. Elapse 30 s. `onClientGone` not called. Drive `respondToWrite`. Elapse 11 s. `onClientGone` fires.

**Test 10 — disconnect mid-request leaves no leaked pending state.**
Track a client. `requestStarted(client, 1)`. Simulate a disconnect (`server._handleClientDisconnected('client')` via the `centralDisconnections` stream). Then call `respondToWrite` for request 1 — it must be a no-op (`requestCompleted` for unknown client). Re-track the same client via a fresh heartbeat. Elapse the interval. `onClientGone` fires once for the new entry — no double-fire, no phantom pending state.

**Test 11 — `requestCompleted` fires even if the platform respond throws.**
Configure `FakeBlueyPlatform` to throw on `respondToWriteRequest`. Drive a write-with-response arrival. Call `respondToWrite`; expect the throw to propagate. Verify `LifecycleServer`'s pending set is empty afterwards (the timer would re-arm and `onClientGone` fires after the interval). Drives the "drain pending before platform call" ordering.

**Refactor pass.** Dartdoc on `LifecycleServer` explaining `recordActivity` vs `requestStarted` (when to use which). Logging at `dev.log` level on suppression and resume, matching the existing lifecycle-server log style.

### What stays unchanged

- `LifecycleClient` and `LivenessMonitor` — no edits, no new tests.
- The control-service request handling (`handleWriteRequest` / `handleReadRequest`) — these are auto-responded synchronously and never enter the pending set.
- `_trackClientIfNeeded` and `onHeartbeatReceived` semantics.

## Caveats

### iOS-server detection gap (accepted)

iOS has no peripheral-side disconnect callback (see [I201](../../backlog/I201-ios-client-disconnect-callback.md)). On iOS server, the heartbeat-timeout timer is the *only* mechanism that detects a client whose link has dropped.

After this fix, a client whose link drops *while the iOS server is holding a pending request* is undetectable until the app either responds (in which case the response is sent into the void with no error) or the platform eventually surfaces the drop through some other path. If the server-app code never responds (a logic bug or deliberate stall plus a dropped link), the client is never detected as gone.

This is a real but narrow regression:

- It requires the link to drop *during* the specific window that a server-app is holding a response.
- Without this fix, the same scenario instead causes routine false-positives on every long-running response (the bug we're fixing).
- The detection regression is bounded by the duration of the server-app's response delay — once the response goes out, the timer re-arms and the next interval-without-traffic detects the drop.

The trade is clearly correct: routine reproducible bug → narrow corner-case detection delay. We accept the detection gap and document it here.

### "What if the app never responds?"

A server-app that never calls `respondToRead` / `respondToWrite` for a request — a programming bug — keeps that request in the pending set forever, which keeps the client's heartbeat timer suppressed forever. The timer will never declare the client gone.

This is acceptable because:

- On Android, the OS reliably surfaces link drops via `onConnectionStateChange(STATE_DISCONNECTED)`, which calls `_handleClientDisconnected` independently of the lifecycle timer.
- On iOS, the gap above already covers this. A buggy app is no worse off than the iOS detection gap already implies.
- The server-app bug is a correctness issue in the consuming code, not in `LifecycleServer`. The library's job is not to paper over apps that never respond to requests; that's a contract violation by the caller.

### Concurrent-modification safety

`Map<String, Set<int>>` is mutated only from the Dart isolate's event loop (platform request listeners and `respondTo*` calls all run on the main isolate). No concurrent access; no synchronization needed.

## Risks and rollback

**Risks:**

- A bug in `requestCompleted` that fails to remove an id leaves the timer permanently suppressed for that client. Mitigated by set-based modeling (idempotent removal) and explicit tests for set drainage.
- A bug in the `BlueyServer` wiring that fails to call `requestCompleted` on the response path has the same effect. Mitigated by tests 6/7/9 driving the full arrival → respond cycle.
- The `BlueyClient as` cast in the response path is safe today (`BlueyServer` is the only producer of `Client` instances) but constrains future refactors. Document with a one-line comment at the cast site.

**Rollback:** revert the two-file change. The data structure is purely additive; nothing else in the codebase depends on it.

## Backlog hygiene (post-merge)

1. Update `docs/backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md`:
   - `status: open` → `fixed`
   - `last_verified: 2026-04-24` → date of merge
   - Add `fixed_in: <merge sha>`
   - Replace the stale "Notes" section. The existing prose recommends a client-side fix that is already in tree; rewrite to describe the server-side pending-request fix actually applied.
2. Update `docs/backlog/README.md`'s "Suggested order of attack" — remove I079 from the top of the list (now fixed).
3. Update the `Index → Open → domain layer` table to reflect the move from open to fixed.
4. Re-run the failure-injection / timeout-probe stress tests as the I087 follow-up note in the README anticipates ("after I079 is fixed, re-run the failure-injection stress test"). If I087 still reproduces, file separately; if not, close I087 with a verification note.
