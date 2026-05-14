# Adapter-State Invalidation of Live Server/Connection/Scanner Instances

**Ticket:** I333.

**Status:** design draft, awaiting review. No code written.

## Problem

When the Bluetooth adapter cycles off and back on (user toggle, airplane mode, low-battery, OS-level stack recovery), bluey's internal state silently desynchronizes from reality:

- `Server` references hold dead Android `BluetoothGattServer` Binder proxies; any subsequent `addService` / `startAdvertising` / `notify*` call throws `android.os.DeadObjectException`, which the current error translation surfaces as opaque `PlatformException(bluey-unknown, …)`.
- `Connection` references hold stale `BluetoothGatt` / `CBPeripheral` handles in the same shape.
- The scanner's underlying scan callback is invalidated by the platform.

The adapter-state event stream (`Bluey.stateStream: Stream<BluetoothState>`) **is already there** — bluey just doesn't act on it internally. Consumers must either (a) duplicate the listener and reconcile manually, or (b) catch opaque exceptions after the fact.

## Goal

Five changes, forming a coherent "state observation is honest at every boundary":

1. **Per-instance internal invalidation.** Each `BlueyServer`, `BlueyConnection`, and the scanner subscribes to `_platform.stateStream` at construction. On any non-`on` emission, the instance becomes terminal-failed: streams close, in-flight ops complete with the typed exception, internal caches clear, the subscription cancels.

2. **`StaleHandleException` (new).** Replaces the old "instance silently fails" path. A method call on an invalidated instance throws `StaleHandleException` — regardless of whether the adapter is currently `on` or `off`. The exception carries the state that triggered invalidation, for diagnostics. Consumer recovery: catch, construct fresh from `Bluey`.

3. **Translate `DeadObjectException` → `bluetooth-unavailable`.** Backstop on Android for the race where an op is in flight when the adapter dies. iOS's symmetric work: pre-check `centralManager.state` (and `peripheralManager.state`) at the top of each GATT op and throw `BluetoothError.notReady` if not powered on.

4. **Factories pre-check state synchronously.** `Bluey.server()`, `Bluey.connect(device)`, `Bluey.scanner.scan(...)` each check current adapter state at the top and throw the appropriate state-mapped typed exception (`BluetoothDisabledException`, `PermissionDeniedException`, `BluetoothUnavailableException`) before constructing anything. Gives a clean two-phase model: **construction-time state check** (synchronous typed throw) + **mid-life invalidation** (`StaleHandleException` via stateStream).

5. **Remove `Bluey.ensureReady()`.** Redundant after change #4 — every state-mapped exception it could throw is now thrown by the factory that actually does work. Consumers who want a non-throwing probe use `bluey.currentState` (sync cached) or `bluey.state` (async fresh). Reduces the API surface from three state-check methods to two.

### In scope

- **Invalidation primitive on `BlueyServer`, `BlueyConnection`, scanner.** `_invalidated` bool field + stateStream subscription + invalidate-and-cleanup method. Every public method (sync getter or async op) checks `_invalidated` first and throws `StaleHandleException`.
- **`StaleHandleException`** in `bluey_platform_interface/lib/src/exceptions.dart`, extending `BlueyException`. Carries:
  - `triggeringState: BluetoothState` (the state that caused invalidation)
  - `instanceType: String` (e.g. `'Server'`, `'Connection'`, `'Scanner'`) for diagnostics
- **`DeadObjectException` translation** in `bluey_android/.../Errors.kt` → existing `bluetooth-unavailable` Pigeon code.
- **iOS state-pre-check** at each GATT op entry — if `state != .poweredOn`, return `BlueyError.notReady` synchronously.
- **Stream cleanup on invalidation**: `Connection.stateChanges`, `Server.connections`, scan emissions, `connection.android?.bondStateChanges`, etc. close (the controller is closed, not just paused).
- **In-flight op resolution**: anything tracked by `_trackInFlight` or equivalent gets completed with `StaleHandleException`, not hung.
- **`PeerConnection`** inherits invalidation via its wrapped `Connection`. No new bookkeeping needed; calls on `peer.connection` will throw, and `peer.*` methods delegate to that.
- **Factory state pre-checks**: `Bluey.server()`, `Bluey.connect(device)`, `Bluey.scanner.scan(...)` each call a shared `_requireAdapterOn()` helper at the top and throw the state-mapped exception before any construction.
- **Removal of `Bluey.ensureReady()`** from `bluey/lib/src/bluey.dart`. Migrate any internal callers (tests, example app) to either the factory call itself (if they were calling it as a preamble to a factory) or to a `currentState`/`state` probe (if they wanted state-only).
- **Tests**: unit tests covering each instance type × invalidation scenario + integration test where stateStream emits `off` mid-op + factory-throws unit tests (one per factory × per state) + verification that all internal `ensureReady` callers are migrated.

### Out of scope

- **Auto-reinitialization on transition back to `on`.** Explicitly excluded. Consumer constructs fresh instances. See I333 for rationale.
- **Session manager / lifecycle observer pattern.** Belongs in the consumer layer (e.g. `gossip_bluey`). bluey stays primitive.
- **Adding a new event to `Bluey.events`.** `Bluey.stateStream` is the canonical adapter-state observation point. Adding a parallel event creates two ways to watch the same signal.
- **Per-platform retry / reconnect logic.** A consumer concern.
- **Refactoring `Bluey.state` / `Bluey.currentState`** — behavior unchanged. (`ensureReady` is removed; the non-throwing probes stay.)

## Final API

### New value object / exception

```dart
// bluey_platform_interface/lib/src/exceptions.dart

/// A method was called on a [Server], [Connection], or [Scanner]
/// instance that was invalidated by a prior Bluetooth-adapter state
/// transition (e.g. the user toggled Bluetooth off).
///
/// Invalidation is **terminal**: the instance is dead and will not
/// recover even if the adapter returns to [BluetoothState.on]. Construct
/// a fresh instance from [Bluey] to proceed:
///
/// ```dart
/// try {
///   await server.addService(...);
/// } on StaleHandleException {
///   server = bluey.server();
///   await server.addService(...);
/// }
/// ```
///
/// [triggeringState] is the adapter state that caused invalidation —
/// useful for diagnostics and for branching recovery logic. It does
/// **not** reflect the adapter's current state, which may have returned
/// to [BluetoothState.on] since invalidation.
class StaleHandleException extends BlueyException {
  final BluetoothState triggeringState;
  final String instanceType; // 'Server', 'Connection', 'Scanner'

  StaleHandleException({
    required this.triggeringState,
    required this.instanceType,
  }) : super(
          '$instanceType was invalidated by adapter transition to '
          '$triggeringState; construct a fresh instance from Bluey.',
        );
}
```

### Invalidation semantics (per instance type)

```dart
// Conceptual pseudo-code; actual placement follows the established
// pattern of private methods on the BlueyXxx class + facade access.

class BlueyServer implements Server {
  bool _invalidated = false;
  BluetoothState? _invalidationState;
  StreamSubscription<BluetoothState>? _stateSub;

  BlueyServer(...) {
    _stateSub = _platform.stateStream.listen(_onStateChange);
  }

  void _onStateChange(BluetoothState state) {
    if (state != BluetoothState.on && !_invalidated) {
      _invalidate(state);
    }
  }

  void _invalidate(BluetoothState triggeringState) {
    _invalidated = true;
    _invalidationState = triggeringState;
    _stateSub?.cancel();
    _stateSub = null;

    // Close all public streams.
    _connectionsController.close();
    // ... etc for every stream owned by this instance.

    // Fail in-flight ops with StaleHandleException.
    _trackInFlight.failAll(StaleHandleException(
      triggeringState: triggeringState,
      instanceType: 'Server',
    ));

    // Clear internal caches.
    _connectedClients.clear();
    // ... etc.
  }

  void _ensureValid() {
    if (_invalidated) {
      throw StaleHandleException(
        triggeringState: _invalidationState!,
        instanceType: 'Server',
      );
    }
  }

  @override
  Future<void> addService(HostedService service) async {
    _ensureValid();
    // ... existing logic
  }

  // ... etc for every public method (including sync getters).
}
```

### Public surface — small breaking changes (no consumers; safe)

- `Server`, `Connection`, `Scanner` interfaces: **unchanged** (new behavior is internal).
- `Bluey.stateStream`, `Bluey.state`, `Bluey.currentState`: **unchanged**.
- `Bluey.server()`: **breaking — now throws synchronously** if adapter is not `on`. Previously returned a non-null `BlueyServer` regardless of state (or `null` only if `!canAdvertise`). Post-change: throws `BluetoothDisabledException` / `PermissionDeniedException` / `BluetoothUnavailableException` per the state mapping. Still returns `null` if `!canAdvertise` (capability-level "this platform can never have a server").
- `Bluey.connect(device)`: **breaking — now throws synchronously** with a state-mapped exception before any platform call if adapter is not `on`. Previously returned a `Future` that failed with `ConnectionException`.
- `Bluey.scanner.scan(...)`: **breaking — now throws synchronously** before returning the scan stream if adapter is not `on`. (The accessor `Bluey.scanner` itself remains a non-throwing getter; the throw is on `.scan(...)`.)
- `Bluey.ensureReady()`: **removed**. Migration: drop the call; the next factory call you would have made handles it. If you wanted state-only without taking action, use `bluey.currentState` or `await bluey.state`.

## Decisions

### D1 — `StaleHandleException` always wins over state-mapped exceptions

Earlier draft considered throwing `BluetoothDisabledException` / `PermissionDeniedException` from invalidated instances based on the cached state. Rejected: an invalidated instance that's accessed while the adapter is currently `on` would throw `BluetoothDisabledException`, which lies about the *current* state. `StaleHandleException` is honest — it says "this *instance* is dead, regardless of current adapter state."

### D2 — Invalidation is terminal; no resurrection

Once invalidated, the instance never returns to a usable state. Even if `stateStream` later emits `on`, the instance stays dead. Consumer constructs fresh from `Bluey`.

Rationale: BLE-level state (added services, advertise config, subscribed centrals, GATT cache on remote peer) is gone after a stack-level adapter cycle, so a "resurrected" instance would have stale state and need re-applying anyway. Better to make construction explicit.

### D3 — Per-instance subscription, not central registry

Each `BlueyServer` / `BlueyConnection` / scanner manages its own subscription. Matches the existing pattern (e.g. `BlueyConnection._handleServiceChange` listens to its own platform events). No new registry needed.

### D4 — `BluetoothState` enum unchanged

The existing enum has `unknown`, `unsupported`, `unauthorized`, `off`, `on`. We treat *anything not `on`* as invalidating. No new state needed.

Specifically: `unknown` *is* invalidating. If the platform hasn't determined state yet, an instance that was constructed before state was known is unsafe. (In practice, instances are usually constructed after state-on is observed via `ensureReady`, so this is a rare path.)

### D5 — Factories pre-check state synchronously

`Bluey.server()`, `Bluey.connect(device)`, `Bluey.scanner.scan(...)` call `_requireAdapterOn()` at the top and throw the state-mapped exception before any construction or platform call. The exception types are exactly the ones `ensureReady` used to throw: `BluetoothDisabledException` (`off` / `turningOff`), `PermissionDeniedException` (`unauthorized`), `BluetoothUnavailableException` (`unsupported`, `unknown`, `resetting`).

Rationale: It's more ergonomic than "construct, then call a method, then get an error" — the failure is at the natural decision point (the factory call), with a typed exception that says *why*. Pairs cleanly with `StaleHandleException` for the mid-life case: construction-time exceptions describe "the adapter wasn't ready when you asked"; `StaleHandleException` describes "the instance you held is dead because of a past transition."

Earlier draft kept factories non-throwing on the argument that `Bluey.ensureReady()` exists. Reversed because (a) the factory throw and `ensureReady` do the same work, so having both is duplication; (b) the factory-throws path is what consumers should be doing anyway; (c) explicit pre-checks (`ensureReady`) become a footgun — easy to forget — when the typed exception path is inline.

### D6 — `DeadObjectException` translation uses existing `bluetooth-unavailable` code

No new Pigeon error code. `Errors.kt` adds a `DeadObjectException` arm to its existing translation table that emits the `bluetooth-unavailable` code. Dart side maps that to `BluetoothUnavailableException` as it already does for `getState() == .unsupported`.

This is the **backstop** for the race where A's invalidation hasn't fired yet but the op was already on its way to the native side. After A is solid, this case should be vanishingly rare.

### D7 — iOS pre-check at op-entry, not `DeadObjectException` analogue

iOS doesn't throw an equivalent of `DeadObjectException`; calls against a `.poweredOff` `CBCentralManager` silently no-op (no completion fires). Symmetric fix: in each iOS GATT op handler, check `centralManager.state != .poweredOn` at the top and complete the Pigeon callback with `BlueyError.notReady` synchronously.

### D8 — `PeerConnection` inherits invalidation via its wrapped `Connection`

`PeerConnection` is a composition wrapper around `Connection`. When the underlying `Connection` is invalidated, calls on `peer.connection.*` throw `StaleHandleException`. Methods directly on `peer.*` (e.g. `peer.disconnect()`) delegate to the wrapped connection and propagate naturally. No invalidation bookkeeping on `_BlueyPeerConnection` itself.

### D9 — `Scanner` is part of `Bluey`, not a separate aggregate

The "scanner" in this design is the active scan stream returned from `bluey.scanner.scan(...)`. Each `scan()` call produces a fresh `Stream<ScanResult>` backed by a `StreamController`. Invalidation closes the controller and any active subscription.

The `Bluey.scanner` accessor itself is a getter, not a stateful instance. It returns a small object whose only operation is `scan(...)`. The object isn't invalidated; the *stream* it produces is. The factory pre-check (D5) lives on `scan()`, not on the `Bluey.scanner` getter.

### D10 — Remove `Bluey.ensureReady()`

`ensureReady` was a one-shot probe that mapped current state to a typed exception. Every state-mapped exception it could throw is now thrown by the factories themselves (D5). The remaining "probe state without taking action" use case is served by `bluey.currentState` (sync cached) and `bluey.state` (async fresh).

Keeping `ensureReady` after D5 would be:
- Three ways to check state (`ensureReady` throws, `state` returns Future, `currentState` returns sync).
- Footgun for consumers — easy to call the factory without `ensureReady` and miss the natural call site for the typed throw (though D5 now closes that gap by making the factory itself the natural site).

Migration: delete `Bluey.ensureReady`. Audit internal callers (tests, example app). For each call:
- If it was a preamble to a factory call: delete it; the factory now does the equivalent.
- If it was a state-only probe: replace with `bluey.currentState != BluetoothState.on` (sync) or `await bluey.state != BluetoothState.on` (async).

## Test strategy

### Unit tests

For each of `BlueyServer`, `BlueyConnection`, `Scanner`:

- `invalidates on stateStream emitting off`
- `invalidates on stateStream emitting unauthorized`
- `invalidates on stateStream emitting unknown`
- `does not invalidate on stateStream emitting on`
- `does not re-invalidate on subsequent non-on emissions (no double-cleanup)`
- `subsequent public method calls throw StaleHandleException` (one test per public method)
- `streams close on invalidation` (assert via `isBroadcast` and stream completion)
- `in-flight op resolves with StaleHandleException` (set up async op, emit invalidating state, await op, expect throw)
- `triggeringState reflects the state that caused invalidation` (not subsequent re-on)

### Integration tests

- **Server lifecycle**: `bluey.server() → addService → startAdvertising`, then `stateStream` emits `off`, assert: server is invalidated, `connections` stream closed, subsequent `addService` throws `StaleHandleException`. Then emit `on`, assert: server stays invalidated. Construct new server, assert: it works.
- **Connection lifecycle**: similar for `bluey.connect(...) → services() → characteristic.read()`, with state cycle in the middle.
- **Scanner lifecycle**: active scan, state cycle, scan stream closes, next `bluey.scanner.scan(...)` produces a fresh working stream.

### Factory-throws tests

For each of `Bluey.server()`, `Bluey.connect(device)`, `Bluey.scanner.scan(...)`:

- `throws BluetoothDisabledException when state is off`
- `throws BluetoothDisabledException when state is turningOff`
- `throws PermissionDeniedException when state is unauthorized`
- `throws BluetoothUnavailableException when state is unsupported`
- `throws BluetoothUnavailableException when state is unknown`
- `succeeds when state is on` (returns a working instance)

These are simple to write against `FakeBlueyPlatform` by setting the simulated state before calling the factory.

### Removal-migration tests

- `Bluey.ensureReady` no longer exists in the public API: a grep test or a deliberate compile-time absence assertion (calling it should fail to compile).
- Internal callers of `ensureReady` (tests, example app) are migrated. Final `flutter analyze` and `flutter test` are the verification.

### Platform-level tests

- **Android**: unit test for `Errors.kt` translating `DeadObjectException` to `bluetooth-unavailable`.
- **iOS**: unit test for each GATT op handler pre-checking state.

### Existing test impact

- `bluey/test/connection/bluey_connection_state_gating_test.dart`: covers per-op disconnect throwing. Add a parallel group for "after stateStream emits off, throws StaleHandleException."
- `bluey/test/bluey_server_test.dart`: similar — add a "post-state-off" group.
- Any test that mocks `BlueyPlatform.stateStream`: ensure it can simulate state emissions. `FakeBlueyPlatform` already has `stateStream`; verify it can emit non-`on` states.

## Sequencing

Each phase is a green checkpoint — full test suite passes, `flutter analyze` clean.

1. **Phase 1: `StaleHandleException` value object** (with red tests).
2. **Phase 2: `_requireAdapterOn()` helper on `Bluey`** + factory throws on `Bluey.server()`, `Bluey.connect(device)`, `Bluey.scanner.scan(...)`. Red tests for each factory × each non-`on` state. Pre-existing tests that previously constructed against non-`on` states will need to be migrated (pin platform to `on` or assert the new throw).
3. **Phase 3: Remove `Bluey.ensureReady`.** Migrate internal callers in `bluey/test/` and `bluey/example/`. Each call site either becomes a factory call (lets the factory throw) or a non-throwing probe (`bluey.currentState`).
4. **Phase 4: Invalidation primitive on `BlueyServer`.** Subscribe to stateStream, invalidate on non-on, throw `StaleHandleException` from public methods. Unit tests.
5. **Phase 5: Invalidation on `BlueyConnection`.** Same shape.
6. **Phase 6: Invalidation on `Scanner`** (scan stream closes on invalidation).
7. **Phase 7: Android `DeadObjectException` translation.**
8. **Phase 8: iOS state pre-check at GATT op entry.**
9. **Phase 9: Integration tests** (full adapter cycle, mid-op invalidation, post-`on`-construction success).
10. **Phase 10: Mark I333 fixed in backlog.**

Phases 2 + 3 are bundled at the front because they're the breaking-API changes; landing them first means subsequent phases work against the new API shape. Phases 4–6 are independent (could parallelize) but kept sequential for review clarity.

## Risks

- **R1: Subscription leaks.** Each instance owns a `StreamSubscription` that must be canceled in `dispose()`. Forgetting this leaks one listener per instance. Mitigation: add to existing disposal paths; test verifies subscription is cancelled.
- **R2: Double-invalidation.** If stateStream emits non-on multiple times during teardown (e.g. `off`, then `turningOff`), `_invalidate` should be idempotent. Mitigation: `if (_invalidated) return;` guard.
- **R3: Stream-closing races.** Closing a `StreamController` while subscribers are mid-listen has well-known pitfalls. Mitigation: use `close()` (not `addError + close`); `_ensureValid()` gates new subscriptions.
- **R4: In-flight op resolution.** If `_trackInFlight` doesn't support "fail-all-pending", we may need to add it. Mitigation: design phase verifies the API exists; otherwise extend.
- **R5: iOS pre-check site sprawl.** Each iOS GATT op needs the check. ~10 op handlers in `CentralManagerImpl.swift` and `PeripheralManagerImpl.swift`. Mitigation: extract a small helper (`guard ensureReady() else { return }`).
- **R6: `FakeBlueyPlatform.stateStream` emission semantics.** Verify it's a true broadcast that fires on `setState(...)` or equivalent. If not, tests can't simulate the cycle.
- **R7: Test fallout from factory-throws.** Pre-existing tests construct `Bluey.server()` / `bluey.connect(...)` against a `FakeBlueyPlatform` whose initial state may not be `on`. Once factories throw, these tests will fail. Mitigation: audit during Phase 2; pin platform to `on` (the common case) or assert the new throw (the deliberate-failure case).
- **R8: `Bluey.ensureReady` removal scope.** Internal callers may have non-obvious uses (e.g. retry loops, lifecycle observers). Mitigation: Phase 3 enumerates every call site before changing the call sites; each migration is a one-line decision (factory vs. probe). Risk is small but non-zero.
- **R9: Migration of the example app.** The example UI may have flows that depend on `ensureReady`. The example is a learning surface for consumers, so the migration should also serve as documentation of the new pattern. Mitigation: review example diff explicitly; if non-trivial, write a brief consumer-migration note in the I333 backlog resolution.

## Non-goals

- Auto-reinitialization.
- Session-replay pattern.
- New events on `Bluey.events`.
- Refactoring `Bluey.ensureReady`.
- Per-platform-error-code minutiae.
- Backward-compat shims (no consumers).
