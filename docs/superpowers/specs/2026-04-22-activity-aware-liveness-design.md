# Activity-Aware Liveness Design

## Problem

The Phase 2a GATT operation queue serialises user writes behind any in-flight lifecycle heartbeat. Under burst load (50+ concurrent writes via `runBurstWrite`), the heartbeat gets starved:

- Heartbeat timer fires during the burst and queues a probe write.
- Queue depth pushes the probe's in-flight time past the 10s per-op timeout.
- Timeout counts as a dead-peer signal with `maxFailedHeartbeats = 1` default → `onServerUnreachable` → disconnect.
- Android client tears down the connection mid-burst even though every preceding write successfully round-tripped to the iOS peer.

Observed in the field: burst write test against an iOS server, first run shows 21 successes followed by disconnect then 29 queue-drain failures. Subsequent runs succeed (MTU settled, connection warm), so the failure is transient but reproducible on cold connections.

The root cause is that `LifecycleClient` treats the heartbeat probe's outcome as the *only* signal of peer liveness. Successful user ops through the same GATT channel — which definitively prove the peer is alive — are ignored. Activity evidence is discarded.

A symmetric problem exists on the server: `LifecycleServer` only resets its per-client timer on writes to the lifecycle control-service characteristic. User writes to non-control chars don't count. If the client skips a heartbeat (this spec's new behaviour), the server will fire `onClientGone` even though the client is actively writing to other characteristics.

## Goal

Treat any successful GATT op on the connection as liveness evidence. Skip heartbeats when the peer has recently proven itself. Keep heartbeats as a fallback for genuinely idle connections. Do this symmetrically on both sides — client skips probe, server accepts any request as liveness.

### In scope

- A new domain class `LivenessMonitor` that owns liveness policy (state machine over activity / probe / failure events).
- Refactor of `LifecycleClient` to delegate policy to the monitor. Retains GATT mechanism.
- Hooks in `BlueyConnection` to notify the client-side `LifecycleClient` on successful GATT ops and incoming notifications.
- Small change to `LifecycleServer` / `BlueyServer` so any incoming request from a client resets its per-client timer.
- Rename private helper `_translateGattPlatformError` → `_runGattOp` on `BlueyConnection` (the helper now does more than translate errors — it also records activity on success).
- Unit tests for `LivenessMonitor` policy, updates to existing `LifecycleClient` / `LifecycleServer` / `BlueyConnection` tests.

### Out of scope

- Protocol changes (no new UUIDs, no new opcodes, no new services). Heartbeat char + lifecycle control service unchanged.
- Tuning defaults (`maxFailedHeartbeats` stays at 1; `defaultLifecycleInterval` stays at 10s).
- `PassiveLivenessMonitor` extraction on the server side. The server's liveness logic is a single timer per client; a domain class would be ceremony without payoff. Stays inline.
- MTU-related diagnostic improvements (separate spec).
- Structured-logging framework upgrade (separate spec).

## Architecture

Three units on the client side, clean separation of policy from mechanism. Server side stays as one unit with a small new entry point.

```
┌──────────────────────────────────────────────────────────────────┐
│ bluey/lib/src/connection/liveness_monitor.dart (NEW)              │
│   * Pure domain — no dart:async, no GATT, no platform            │
│   * State: _lastActivityAt, _consecutiveFailures, _probeInFlight │
│   * Events in: recordActivity, markProbeInFlight,                │
│                recordProbeSuccess, recordProbeFailure            │
│   * Decisions out: shouldSendProbe                               │
│   * Fully unit-testable with injected clock                      │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ bluey/lib/src/connection/lifecycle_client.dart (REFACTORED)       │
│   * Owns Timer.periodic and GATT write call                      │
│   * All policy decisions delegate to _monitor                    │
│   * Public recordActivity() forwarded from BlueyConnection       │
│   * Shrinks significantly — no more direct counter mutation      │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ bluey/lib/src/connection/bluey_connection.dart (MODIFIED)         │
│   * `_translateGattPlatformError` → `_runGattOp`                 │
│   * `_runGattOp` calls `_lifecycle?.recordActivity()` on success │
│   * Notification stream listener in BlueyRemoteCharacteristic    │
│     calls `_connection._lifecycle?.recordActivity()` on each     │
│     incoming notification                                         │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ bluey/lib/src/gatt_server/lifecycle_server.dart (SMALL CHANGE)    │
│   * New public method: recordActivity(clientId)                  │
│   * Delegates to existing _resetTimer                            │
│   * No state-machine changes; just a new entry point             │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ bluey/lib/src/gatt_server/bluey_server.dart (SMALL CHANGE)        │
│   * Read/write request listeners call                            │
│     `_lifecycle.recordActivity(clientId)` on requests that fall  │
│     through the control-service handlers                         │
└──────────────────────────────────────────────────────────────────┘
```

### DDD notes

- **`LivenessMonitor`** is an aggregate root. State mutation happens only through its public event methods. Invariants (counter monotonic until reset, at most one probe in flight) are enforced by the class, not scattered across callers.
- **`LifecycleClient`** is an anti-corruption layer between Android's GATT queue / iOS's CoreBluetooth and the domain monitor. It translates platform outcomes into monitor events. It owns nothing of its own that the monitor doesn't also own.
- **Naming**: the monitor's ubiquitous language is "probe" (the abstract liveness-check action) and "activity" (any evidence of peer response). The concrete transport is "heartbeat" — that word stays in `LifecycleClient` (`heartbeatCharUuid`) and `lifecycle.dart` (`heartbeatValue`) because they're about the wire protocol. The monitor doesn't know what a heartbeat is.

## Components

### `LivenessMonitor` — `bluey/lib/src/connection/liveness_monitor.dart`

```dart
/// Tracks whether a peer is still alive, based on a stream of
/// observable events (successful ops, probe outcomes). Pure domain —
/// no GATT, no async, no platform dependencies.
///
/// The monitor is queried every [activityWindow] by [LifecycleClient]
/// to decide whether to send a new probe. Between ticks, the monitor
/// receives events from:
/// - User-initiated ops succeeding on the connection (recordActivity)
/// - Incoming notifications (recordActivity)
/// - Probe write lifecycle (markProbeInFlight / recordProbeSuccess /
///   recordProbeFailure)
class LivenessMonitor {
  /// Consecutive probe failures that trip peer-unreachable.
  /// Activity clears the counter before it reaches the threshold,
  /// so this only fires during genuine idle periods.
  final int maxFailedProbes;

  /// Minimum time since last activity before the monitor will ask
  /// for a probe. Typically equals the probe tick interval so that
  /// at most one probe is sent per idle window.
  final Duration activityWindow;

  /// Clock injection for deterministic tests.
  final DateTime Function() _now;

  DateTime? _lastActivityAt;
  int _consecutiveFailures = 0;
  bool _probeInFlight = false;

  LivenessMonitor({
    required this.maxFailedProbes,
    required this.activityWindow,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Any evidence that the peer is alive: a successful GATT op, an
  /// incoming notification, a completed probe. Resets the failure
  /// counter and the activity window.
  void recordActivity() {
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Decide whether the next tick should dispatch a probe.
  /// False if a probe is already pending, or activity is recent.
  bool shouldSendProbe() {
    if (_probeInFlight) return false;
    final last = _lastActivityAt;
    if (last == null) return true;
    return _now().difference(last) >= activityWindow;
  }

  /// Called by LifecycleClient just before dispatching a probe write.
  /// Prevents overlapping probes (next tick will skip via [shouldSendProbe]).
  void markProbeInFlight() {
    _probeInFlight = true;
  }

  /// Probe write completed and peer acknowledged. Equivalent to
  /// [recordActivity] plus releasing the in-flight flag.
  void recordProbeSuccess() {
    _probeInFlight = false;
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Probe write failed with a dead-peer signal. Returns true if the
  /// failure threshold has been reached (caller should tear down).
  bool recordProbeFailure() {
    _probeInFlight = false;
    _consecutiveFailures++;
    return _consecutiveFailures >= maxFailedProbes;
  }
}
```

### `LifecycleClient` — thin mechanism wrapper

Shrinks significantly. All counter logic moves to the monitor. Public surface largely unchanged — adds `recordActivity()` for `BlueyConnection` to call.

```dart
class LifecycleClient {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final void Function() onServerUnreachable;
  late LivenessMonitor _monitor;

  Timer? _probeTimer;
  String? _heartbeatCharUuid;
  final int _maxFailedHeartbeats;

  LifecycleClient({
    required platform.BlueyPlatform platformApi,
    required String connectionId,
    int maxFailedHeartbeats = 1,
    required this.onServerUnreachable,
  })  : _platform = platformApi,
        _connectionId = connectionId,
        _maxFailedHeartbeats = maxFailedHeartbeats {
    _monitor = LivenessMonitor(
      maxFailedProbes: maxFailedHeartbeats,
      activityWindow: _defaultHeartbeatInterval,
    );
  }

  bool get isRunning => _probeTimer != null;

  /// Forwarded from BlueyConnection on any successful GATT op or
  /// incoming notification. Treats the peer as demonstrably alive.
  void recordActivity() => _monitor.recordActivity();

  void start({required List<RemoteService> allServices}) {
    // Unchanged: find control service + heartbeat char, read interval,
    // begin timer. When the server-provided interval is known, rebuild
    // the monitor with the correct activity window.
    // ...
  }

  Future<void> sendDisconnectCommand() async { /* unchanged */ }

  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
    // Monitor retains state until the next call to start() →
    // _beginHeartbeat(), which recreates it with the chosen interval.
    // In practice LifecycleClient is per-connection — a new connection =
    // new instance — so this edge case rarely matters.
  }

  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    // Reinitialise monitor so its activity window matches the chosen interval.
    _monitor = LivenessMonitor(
      maxFailedProbes: _maxFailedHeartbeats,
      activityWindow: interval,
    );
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(interval, (_) => _tick());
  }

  void _tick() {
    if (!_monitor.shouldSendProbe()) return;
    _sendProbe();
  }

  void _sendProbe() {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    _monitor.markProbeInFlight();
    _platform
        .writeCharacteristic(
          _connectionId, charUuid, lifecycle.heartbeatValue, true,
        )
        .then((_) => _monitor.recordProbeSuccess())
        .catchError((Object error) {
      if (!_isDeadPeerSignal(error)) {
        // Clear the in-flight flag without counting the failure — the
        // error was noise, not peer death. recordProbeSuccess is the
        // cleanest way to release the flag AND refresh activity (the
        // error ruled out "peer dead" so we can treat it as implicit
        // liveness for window purposes).
        _monitor.recordProbeSuccess();
        return;
      }
      final tripped = _monitor.recordProbeFailure();
      if (tripped) {
        stop();
        onServerUnreachable();
      }
    });
  }

  bool _isDeadPeerSignal(Object error) { /* unchanged from today */ }
}
```

### `BlueyConnection` — activity hooks

Rename `_translateGattPlatformError` → `_runGattOp`, and add a success-path call to `_lifecycle?.recordActivity()`.

```dart
/// Runs a GATT op through the error-translation pipeline and records
/// activity on success. Every public GATT op method on
/// [BlueyConnection] / [BlueyRemoteCharacteristic] / [BlueyRemoteDescriptor]
/// goes through this single helper.
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body, {
  LifecycleClient? lifecycleClient,
}) async {
  try {
    final result = await body();
    lifecycleClient?.recordActivity();
    return result;
  } on platform.GattOperationTimeoutException {
    throw GattTimeoutException(operation);
  } on platform.GattOperationDisconnectedException {
    throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
  } on platform.GattOperationStatusFailedException catch (e) {
    throw GattOperationFailedException(operation, e.status);
  }
}
```

Each call site passes `lifecycleClient: _lifecycle`. One-line change per call site.

For incoming notifications, the listener in `BlueyRemoteCharacteristic._onFirstListen` gains an activity hook:

```dart
_notificationSubscription = _platform
    .notificationStream(_connectionId)
    .where(...)
    .listen(
      (notification) {
        _lifecycleClient?.recordActivity();  // NEW
        _notificationController?.add(notification.value);
      },
      ...
    );
```

`BlueyRemoteCharacteristic` already has access to the lifecycle client through the owning `BlueyConnection`, passed via constructor. Same for `BlueyRemoteDescriptor` if its ops route through `_runGattOp` (they do today).

### `LifecycleServer` + `BlueyServer` — symmetric activity awareness

`LifecycleServer` gains one method:

```dart
/// Treats any incoming activity from [clientId] as liveness evidence.
/// Resets the per-client timer. Called by [BlueyServer] on every
/// request that isn't already routed through the control-service
/// handlers (which reset the timer internally).
void recordActivity(String clientId) {
  if (_interval == null) return;
  _resetTimer(clientId);
}
```

`_resetTimer` itself is unchanged.

`BlueyServer`'s read/write listeners already delegate to the lifecycle server first. On the fallthrough path (non-control-service request), add a single line:

```dart
_writeRequestSubscription = _observeWriteRequests().listen((request) async {
  if (_lifecycle.handleWriteRequest(request)) return;
  _lifecycle.recordActivity(request.client.id.toString());  // NEW
  // ... existing user handler dispatch (stress service, demo service) ...
});

_readRequestSubscription = _observeReadRequests().listen((request) async {
  if (_lifecycle.handleReadRequest(request)) return;
  _lifecycle.recordActivity(request.client.id.toString());  // NEW
  // ... existing user handler dispatch ...
});
```

Two lines total. No state added to `BlueyServer`.

## Data flow

### Client-side — successful user op during steady activity

```
User calls char.write(bytes)
   │
   ▼
BlueyRemoteCharacteristic.write()
   │
   ▼
_runGattOp(deviceId, 'writeCharacteristic', () => _platform.writeCharacteristic(...),
           lifecycleClient: _lifecycle)
   │  await body()
   │  returns successfully
   ▼
lifecycleClient.recordActivity()
   │
   ▼
LivenessMonitor.recordActivity()
   └─ _lastActivityAt = now
      _consecutiveFailures = 0

  … 5s later Timer.periodic fires …

LifecycleClient._tick()
   │
   ▼
LivenessMonitor.shouldSendProbe()
   └─ activity 2s ago, within 5s window → false
   ▼
skip — no probe sent
```

### Client-side — genuinely idle, probe succeeds

```
  … 5s of idle …

LifecycleClient._tick()
   │
   ▼
LivenessMonitor.shouldSendProbe()
   └─ activity 6s ago, window expired → true
   ▼
LifecycleClient._sendProbe()
   │  _monitor.markProbeInFlight()
   │  _platform.writeCharacteristic(heartbeatChar, ...)
   │  ..ack received..
   ▼
_monitor.recordProbeSuccess()
   └─ _lastActivityAt = now
      _consecutiveFailures = 0
      _probeInFlight = false
```

### Client-side — probe timeout during idle

```
  … 6s of idle, probe sent …
  ..timeout fires after 10s..

LifecycleClient catchError
   │  _isDeadPeerSignal(error) → true
   ▼
_monitor.recordProbeFailure()
   └─ _consecutiveFailures = 1
      _probeInFlight = false
   └─ returns true (threshold reached with default max=1)
   ▼
LifecycleClient.stop() + onServerUnreachable()
   └─ connection torn down
```

### Server-side — any user request resets the timer

```
Client writes to stress char
   │
   ▼
BlueyServer._observeWriteRequests().listen
   │
   ▼
_lifecycle.handleWriteRequest(request)
   └─ request is NOT a control-service write → returns false
   ▼
_lifecycle.recordActivity(clientId)
   │
   ▼
LifecycleServer._resetTimer(clientId)
   └─ cancels existing timer, starts fresh N-second timer
```

## Error handling

Four failure cases for the monitor's decision path:

| Situation | Monitor event | Client counter | Behaviour |
|---|---|---|---|
| User op succeeds | `recordActivity` | reset to 0 | Window refresh; next probe tick may skip |
| Probe succeeds | `recordProbeSuccess` | reset to 0 | Like recordActivity, plus releases in-flight flag |
| Probe fails with dead-peer signal | `recordProbeFailure` | increment | If threshold, LifecycleClient tears down |
| Probe fails with non-dead-peer error | `recordProbeSuccess` (see note) | no change | Flag released, next tick may probe again |

Note on the fourth case: non-dead-peer errors (e.g. a rare `PlatformException` with an unknown code) historically reach `catchError` but are filtered by `_isDeadPeerSignal`. The cleanest way to release `_probeInFlight` without counting is to call `recordProbeSuccess` — we didn't observe peer silence, and treating the attempt as "implicit activity" (the error at least proves the queue ran the op) is fine. Alternative `monitor.recordProbeIgnored()` introduces a fifth event for one edge case; YAGNI.

### Server-side — timer expiration on silence

Unchanged. If no activity reaches the server within `_interval`, the per-client timer fires `onClientGone(clientId)`. Activity includes control-service writes (heartbeats, disconnect commands) AND now any other request from the client.

## Testing

### `LivenessMonitor` — pure unit tests with injected clock

Place in `bluey/test/connection/liveness_monitor_test.dart`. No async, no fakes — just direct state transitions.

- Initial state: `shouldSendProbe` true (no recorded activity yet).
- `recordActivity` resets counter AND records timestamp.
- `shouldSendProbe` false when `_probeInFlight` is true.
- `shouldSendProbe` false when activity is within window.
- `shouldSendProbe` true after window expires.
- `recordProbeSuccess` releases in-flight flag, resets counter, records timestamp.
- `recordProbeFailure` increments counter, releases in-flight flag.
- `recordProbeFailure` returns true exactly when the threshold is reached.
- `recordActivity` during `_probeInFlight` resets counter without affecting the flag (subsequent `recordProbeSuccess`/`recordProbeFailure` is still required to release).

### `LifecycleClient` — updated existing tests

Existing tests in `bluey/test/connection/lifecycle_client_test.dart` continue to cover the mechanism (heartbeat timer, control service discovery, dead-peer signal classification). Add:

- A test that `recordActivity` on the client causes `shouldSendProbe` to return false on the next tick.
- A test that non-dead-peer errors don't count toward the threshold (this was implicit before; more explicit now).
- A test that `_isDeadPeerSignal` gating still works correctly against the new flow.

### `LifecycleServer` — new test

In `bluey/test/gatt_server/lifecycle_server_test.dart` (create if doesn't exist):

- After `recordActivity(clientId)`, the per-client timer is reset (assert via `fake_async` time advancement that `onClientGone` does NOT fire within the window, then does fire after another full interval of silence).

### `BlueyServer` — new test

Assert that a user write to a non-control-service characteristic (e.g. the stress service UUID) triggers `LifecycleServer.recordActivity` — use a spy `LifecycleServer` or equivalent.

### `BlueyConnection` — new test

Assert that after a successful GATT op (write / read / etc.), the `LifecycleClient.recordActivity` was called. Use a spy lifecycle client or equivalent.

## Migration plan

TDD-first commit order, each leaves the suite green:

1. `test(bluey): add LivenessMonitor tests (red)` — unit tests for the policy state machine. Fails because `LivenessMonitor` doesn't exist.

2. `feat(bluey): add LivenessMonitor domain class (green)` — new file `liveness_monitor.dart`. Tests pass.

3. `refactor(bluey): LifecycleClient delegates to LivenessMonitor` — existing `LifecycleClient` tests continue to pass. Counter state moves out of the class; `_monitor.shouldSendProbe` guards each tick. `recordActivity()` public method added.

4. `refactor(bluey): rename _translateGattPlatformError → _runGattOp + record activity on success` — `BlueyConnection` call sites updated. Notification listener adds the hook. Existing connection tests stay green; new test asserts the hook fires.

5. `feat(bluey): LifecycleServer.recordActivity + BlueyServer wiring` — new public method on `LifecycleServer`, called from `BlueyServer` listeners. New test exercises the path.

6. `docs(bluey): update ANDROID_BLE_NOTES and lifecycle doc for activity-aware liveness` — brief note in relevant docs explaining the new behaviour ("heartbeats skip when other GATT activity is recent; server accepts any client request as liveness").

## Success criteria

- All existing tests pass. All new tests pass.
- `flutter analyze` clean.
- `runBurstWrite` in the stress test suite no longer triggers spontaneous disconnects on a cold connection against an iOS peer (manual verification).
- `LifecycleClient` shrinks by ~30 LOC as counter logic moves to the monitor.
- `LivenessMonitor` is ~80 LOC with 100% test coverage of transitions.
- No public API changes. `maxFailedHeartbeats` constructor parameter unchanged. `recordActivity()` is a new but optional method on `LifecycleClient`; callers that don't use it (none outside `BlueyConnection`) are unaffected.

## Open questions

None at design time. All scoping decisions settled above.
