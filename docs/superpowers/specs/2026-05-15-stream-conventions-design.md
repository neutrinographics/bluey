# Bluey Stream + State-Surface Conventions

**Tickets:** I334 (stateStream replay), I335 (scan onCancel), PR #31 P1 (cold-start race), PR #31 P2 (connection.state lies post-invalidation), plus scanner-lifecycle events surfaced during PR review.

**Status:** design draft, awaiting plan-writing. No code written.

## Problem

Bluey's public surface has accumulated multiple stream and state-getter inconsistencies that all share the same root cause: each surface was designed in isolation, without a uniform contract for "what does this stream/getter do when something interesting happens to its underlying resource."

The accumulating consumer pain:

- **I334**: `Bluey.stateStream` doesn't replay the current value on subscribe. Consumers subscribing after construction see nothing until the next adapter transition — possibly never. Forces every consumer to subscribe *and* read `currentState` separately and reconcile.
- **I335**: `Scanner.scan()`'s returned stream has no `onCancel`. Consumer cancels their subscription; the radio keeps scanning. Forces consumers to hold the `Scanner` reference and call `stop()` explicitly.
- **PR #31 P1**: On Android cold start, the native plugin publishes its initial `onStateChanged` before the Dart Pigeon handler is registered. Message dropped. `Bluey.currentState` returns `unknown` until the next adapter transition, which means the first `Bluey.server()` / `connect()` / `scanner()` call after `Bluey()` construction throws `BluetoothUnavailableException` spuriously when Bluetooth is actually on.
- **PR #31 P2**: When the adapter cycles off and I333 invalidates a `BlueyConnection`, `stateChanges` closes (subscribers see `onDone`) but the cached `_state` field never updates. `connection.state` keeps returning `ready` or `linked` indefinitely — a flat lie.
- **Pre-existing scanner-lifecycle gap**: `Scanner.isScanning` flips to `false` at the start of `stop()`, before the async platform call completes. `ScanStartedEvent` / `ScanStoppedEvent` exist but can theoretically double-emit, and there are no events for the transient "starting" / "stopping" windows.
- **Pre-existing isAdvertising gap**: `Server.isAdvertising` has the same shape as `isScanning` — flips synchronously around an async platform call.

Each was filed independently. Patched ad-hoc, they'd produce a half-dozen small PRs with no shared model. Fixing them coherently means agreeing on conventions and applying them uniformly.

## Goal

Pick a coherent set of conventions for bluey's stream and state-getter surfaces, then apply them uniformly across the library so:

- Every "current value" stream behaves like a `BehaviorSubject` (replay on subscribe + terminal signal at end-of-life).
- Every "things that happened" stream behaves like a simple broadcast (no replay).
- Every resource-backed stream stops the resource on last-subscriber cancel.
- Every sync state getter is honest — never lies about the adapter / connection / scan / advertising state.
- Lifecycle-bearing objects (Scanner, Server-advertising) have full state-machine surfaces matching the existing `ConnectionState` pattern.
- `Bluey` is honestly async-initialized.

### In scope

- New **stream conventions** documented and applied to every domain-layer Stream surface:
  - Type A (state) streams: replay-on-subscribe, terminal-signal-at-end-of-life.
  - Type B (event) streams: no replay, close cleanly on parent invalidation.
  - Resource-backed streams: `onCancel` stops the resource.
- New **sync-getter convention**: agree with the last terminal signal emitted by the paired stream; throw `StaleHandleException` if the paired stream's terminal was an `addError`.
- New **`Bluey.create()` async factory**. Private `Bluey()` constructor.
- New `ConnectionState.invalidated` enum value.
- New `ScanState` enum (`stopped, starting, scanning, stopping`) + `Scanner.state` getter + `Scanner.stateChanges` Type A stream + `ScanStartingEvent` + `ScanStoppingEvent`.
- New `AdvertisingState` enum (`idle, starting, advertising, stopping`) + `Server.advertisingState` getter + `Server.advertisingStateChanges` Type A stream + `AdvertisingStartingEvent` + `AdvertisingStoppingEvent`.
- `Scanner.isScanning` and `Server.isAdvertising` become *derived* booleans (`state == ScanState.scanning`, `advertisingState == AdvertisingState.advertising`) — kept for ergonomic convenience.
- `Scanner.scan()` picks up `onCancel: () => stop()`.
- All Type A `StreamController.broadcast()` instantiations gain `onListen` replay.
- All Type A streams gain an invalidation path that emits the terminal signal then closes.
- All sync state getters become honest post-invalidation (return enum value or throw `StaleHandleException`).
- Test fakes (`FakeBlueyPlatform`) updated to support the new construction and state-emission semantics.

### Out of scope

- **Refactoring stream value types to sealed wrapper classes** (e.g. `Stream<ServiceTreeState>` with `ServicesAvailable | TreeInvalidated` variants). Possibly worth in the future, but a much larger refactor than this design.
- **Auto-reconnect / session-management** patterns (already deferred per I333 spec).
- **Removing `BluetoothState.unknown` from the public enum**. Kept; documented as a pre-init-only value that consumers shouldn't observe after `await Bluey.create()` completes.
- **Removing `Scanner.isScanning` / `Server.isAdvertising`**. Kept as derived booleans for ergonomic convenience.
- **Lifecycle events on Connection beyond what already exists**. `ConnectingEvent` / `ConnectedEvent` stay as-is. No new `DisconnectingEvent` etc. (Connection has the full `ConnectionState` enum already; events are a separate observability concern that already has coverage.)
- **Other sync booleans on internal classes** (`LifecycleClient.isRunning`, etc.) — these aren't public surface; leave alone.

## Conventions

### Convention 1 — Stream-surface classification

Every domain-layer Stream in bluey falls into exactly one of three buckets, identified at design time:

| Bucket | Defining property | Examples |
|---|---|---|
| **Type A — state stream** | Emits transitions of a stateful thing. Consumer wants "current + future." | `Bluey.stateStream`, `Connection.stateChanges`, `Scanner.stateChanges` (new), `Server.advertisingStateChanges` (new), `Connection.servicesChanges`, `bondStateChanges`, `phyChanges` |
| **Type B — event stream** | Emits transient events. No "current value" concept. Consumer wants future events. | `Bluey.events`, `Bluey.logEvents`, `Server.connections`, `Server.peerConnections`, `Server.disconnections`, `Server.readRequests`, `Server.writeRequests` |
| **Resource-backed stream** | Backed by an expensive platform resource. Should stop when no subscribers. | `Scanner.scan()`, `RemoteCharacteristic.notifications` |

A stream is exactly one of these. The classification drives the implementation pattern.

### Convention 2 — Type A streams replay on subscribe

Every Type A `StreamController.broadcast(...)` uses `onListen:` to replay the most recent value to new subscribers:

```dart
late final StreamController<BluetoothState> _stateController =
    StreamController<BluetoothState>.broadcast(
  onListen: () {
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  },
);
```

A subscriber attaching at any time sees: current value (replay) → future transitions → terminal signal (Convention 3) → `onDone`.

The cached value (`_currentState`) is whatever the most recent observed value is, kept fresh by the existing platform-stream listener in each owning class.

### Convention 3 — Type A streams emit a terminal signal at end-of-life

When the owning instance is invalidated or otherwise reaches a terminal state, every Type A stream emits a final signal before closing:

- **If the value type is an enum bluey owns**: add a dedicated `invalidated` value to the enum and emit it. Consumer can pattern-match in their normal `switch`.
- **If the value type isn't enum-extensible** (collection, BLE-spec enum, record): emit `addError(StaleHandleException(triggeringState: ..., instanceType: ...))` then close. Consumer's `onError` callback fires with the typed exception.

The sync getter paired with the stream agrees with the last signal:
- Enum-with-`invalidated`: getter returns the `invalidated` value.
- `addError` path: getter throws the same `StaleHandleException`.

This means there is **always a way** to know whether an instance is terminal, whether you're using the stream or polling the getter. They never disagree.

### Convention 4 — Type B streams close cleanly on invalidation

Type B streams have no current-value concept. On owner invalidation, the controller just closes. Subscribers see `onDone`. No `addError`, no synthetic terminal value.

Consumers who want to know *why* an event stream ended check the parent's state (which after Convention 3 is honest).

### Convention 5 — Resource-backed streams stop on last-subscriber cancel

Every resource-backed `StreamController` has an `onCancel` that stops the underlying resource:

```dart
final controller = StreamController<ScanResult>(
  onCancel: () => stop(),
);
```

Imperative methods (`Scanner.stop()`) remain for consumers who prefer them, but cancelling the subscription is sufficient.

Single-subscription controllers: `onCancel` fires when the single subscriber cancels.
Broadcast controllers: `onCancel` fires when the last subscriber cancels; `onListen` fires when a new subscriber attaches to a previously-empty controller.

### Convention 6 — Sync state getters are always honest

A sync state getter never returns a value that contradicts what the paired Type A stream has signaled. Specifically:

- Returns the *enum value last emitted* on the paired stream (including `invalidated`).
- If the paired stream's terminal was an `addError` rather than an enum value, the getter throws the same exception.
- During normal operation, returns the cached value updated by the stream's own update path.
- Pre-construction-completion (e.g. before `await Bluey.create()` returns): may return a sentinel value like `BluetoothState.unknown`. Documented per-getter.

## Lifecycle modeling

### Async `Bluey` construction

```dart
// Old:
final bluey = Bluey();

// New:
final bluey = await Bluey.create({ServerId? localIdentity});
```

`Bluey()` becomes a private constructor. `Bluey.create()` is an async factory that:

1. Constructs the internal `Bluey` instance with `_currentState = BluetoothState.unknown`.
2. Subscribes to `_platform.stateStream`.
3. Awaits the first emission on that stream (which the platform plugin should publish on attach).
4. Returns the fully-initialized `Bluey` with `_currentState` reflecting reality.

After `await Bluey.create()` completes, the cold-start race is gone — `currentState` is honest, and `Bluey.server()` / `connect()` / `scanner()` synchronous pre-checks see the real adapter state.

`Bluey` itself is durable across adapter cycles; only derived instances (Server / Connection / Scanner) get invalidated per I333. Consumers don't recreate `Bluey` when Bluetooth toggles — they construct fresh derived instances.

#### Edge case: what if the first state event never arrives?

`Bluey.create()` awaits with a reasonable timeout (e.g. 2 seconds — long enough for normal platform-side init, short enough that hung initialization is visible). On timeout, completes with `_currentState` set to whatever was synchronously available (typically `unknown`). Consumer can either retry or proceed and handle the resulting `BluetoothUnavailableException` from factories.

### Scanner state machine

```dart
enum ScanState { stopped, starting, scanning, stopping, invalidated }

abstract class Scanner {
  /// Current scan state. Replays via [stateChanges].
  ScanState get state;

  /// State transitions, replayed on subscribe.
  Stream<ScanState> get stateChanges;

  /// Whether the scanner is currently active. Derived from [state].
  bool get isScanning => state == ScanState.scanning;

  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout});
  Future<void> stop();
}
```

State transitions (normal lifecycle):
- `stopped` → `starting`: `scan()` called, platform call in flight.
- `starting` → `scanning`: platform `startScan` confirmed.
- `scanning` → `stopping`: `stop()` called OR last subscriber cancelled (via `onCancel`) OR `timeout` fired.
- `stopping` → `stopped`: platform `stopScan` confirmed.

State transitions (terminal):
- Any state → `invalidated`: adapter invalidation (per I333). Terminal — no further transitions.

Events emitted on `Bluey.events`:
- `ScanStartingEvent` on `stopped` → `starting`.
- `ScanStartedEvent` on `starting` → `scanning`.
- `ScanStoppingEvent` on `scanning` → `stopping`.
- `ScanStoppedEvent` on `stopping` → `stopped`.

On adapter invalidation: `state` becomes `ScanState.invalidated`. The `stateChanges` stream emits `invalidated` then closes (per Convention 3, enum-value path). The active scan stream from `scan()` closes with `addError(StaleHandleException)` (resource-backed stream, plus its value type `ScanResult` isn't an enum).

### Server advertising state machine

```dart
enum AdvertisingState { idle, starting, advertising, stopping, invalidated }

abstract class Server {
  /// Current advertising state. Replays via [advertisingStateChanges].
  AdvertisingState get advertisingState;

  /// Advertising-state transitions, replayed on subscribe.
  Stream<AdvertisingState> get advertisingStateChanges;

  /// Whether the server is currently advertising. Derived from [advertisingState].
  bool get isAdvertising => advertisingState == AdvertisingState.advertising;

  Future<void> startAdvertising({...});
  Future<void> stopAdvertising();
  // ... other server methods unchanged
}
```

Same pattern as Scanner. Events: `AdvertisingStartingEvent`, `AdvertisingStartedEvent`, `AdvertisingStoppingEvent`, `AdvertisingStoppedEvent`.

When `BlueyServer` is invalidated (per I333), `advertisingState` transitions to `AdvertisingState.invalidated`. The advertising-state lifecycle is one of several things the server tracks (alongside connected clients, peer identification, etc.); on server invalidation, all of them go terminal.

### Connection invalidation enum value

```dart
enum ConnectionState {
  disconnected,
  connecting,
  linked,
  ready,
  disconnecting,
  invalidated,  // NEW — set by I333 invalidation path
}
```

`Connection.stateChanges` emits `invalidated` then closes on adapter cycle. `connection.state` returns `invalidated`. Consumer pattern-matches.

### Other Type A streams on Connection (and its Android extensions)

These streams' value types aren't bluey-owned enums, so they use the `addError` form:

- `Connection.servicesChanges: Stream<List<RemoteService>>` → `addError(StaleHandleException)` on invalidation.
- `AndroidConnectionExtensions.bondStateChanges: Stream<BondState>` → same.
- `AndroidConnectionExtensions.phyChanges: Stream<({Phy tx, Phy rx})>` → same.

Their paired sync getters throw `StaleHandleException` after invalidation (matching the existing I333 pattern for the other methods).

## Migration impact

### Public API breakage (consumers must update)

- `Bluey()` → `await Bluey.create()`. Every `Bluey()` callsite migrates.
- `BlueyServer.isAdvertising` and `BlueyScanner.isScanning` stay as derived bool — no breakage, but consumers can now reach the state machine if they want.
- `ConnectionState`, `ScanState`, `AdvertisingState` gain new enum values — any consumer-side `switch (state)` without a `default` branch now needs to handle the new values. (Dart's exhaustiveness checking surfaces these at compile time.)

### No-break additions

- New events (`ScanStartingEvent`, `AdvertisingStartingEvent`, etc.) — consumers that don't handle them just won't react. No regression.
- `onListen` replay on Type A streams — existing consumers get an extra initial emission. Most won't notice; those who did `await firstWhere((s) => s == X)` will get the answer faster.
- `onCancel` on `Scanner.scan()` — existing consumers who already called `Scanner.stop()` keep working (idempotent).

### Test fakes

- `FakeBlueyPlatform` needs to support the async-init path: `getState()` should be callable, the broadcast `stateStream` should emit on demand.
- `MockBlueyPlatform` in existing test files needs `currentState` override + state-stream support to drive lifecycle transitions deterministically.

### Internal call sites

- Every internal listener on a Type A stream now handles error events (since invalidation may surface as `addError` on non-enum-typed streams). Audit and add `onError` handling where missing.
- Every internal sync getter that today returns a stale post-invalidation value needs to throw or return the terminal value.

## Decisions

### D1 — Mixed model for Type A end-of-life signal

Enum-extensible types use a new `invalidated` enum value (best ergonomics for switch-based consumers). Non-extensible types use `addError(StaleHandleException)`. The unifying rule is "the stream signals end-of-life and the sync getter agrees" — not the specific shape of the signal.

Rejected alternatives:
- Pure `addError` everywhere: more consistent internally but worse consumer ergonomics for the streams that *can* express terminal as an enum value (notably `ConnectionState`).
- Pure `invalidated` enum value everywhere: requires inventing wrapper types for non-enum streams (e.g. `Stream<ServiceTreeState>` instead of `Stream<List<RemoteService>>`), much larger refactor.

### D2 — Async `Bluey.create()` is the only honest fix for cold-start

Synchronous Pigeon round-trips aren't available on Android (MethodChannel is async-only). Any synchronous reading of native state at `Bluey()` construction must either:
- Use a cached value that might be `unknown` (today's bug), or
- Be moved to async code.

`Bluey.create()` makes the asynchrony honest at the single, natural setup point. Subsequent factory calls stay synchronous.

Rejected alternatives:
- `bluey.ready` Future + sync `Bluey()`: depends on consumer remembering to await; race remains in non-compliant code.
- Async factories (`bluey.server()` returns `Future`): more callsite changes, doesn't even match the natural shape (Server construction is synchronous after state is known).

### D3 — Keep `BluetoothState.unknown` as a pre-init-only sentinel

Removing `unknown` from the enum would force every consumer's `switch (state)` to drop the case — a compile-time change for everyone. Net benefit is small, since post-`create` consumers don't see `unknown` anyway. Documented as "pre-init-only; consumers should not observe this after `await Bluey.create()`."

### D4 — `isScanning` / `isAdvertising` kept as derived booleans

Backwards-compatible convenience. Costs nothing — they're one-line getters that read the state enum. Consumers who prefer the enum can use that; consumers who want a quick boolean check still can.

### D5 — `Bluey` is durable across adapter cycles (per I333)

`Bluey` is the stable factory that produces derived instances. Adapter cycles invalidate derived instances; `Bluey` itself keeps observing the platform state, so consumers have a single durable subscription point to know when to retry.

### D6 — Scanner-lifecycle events live on `Bluey.events`, not on the `Scanner` instance

Following the existing pattern: per-instance state lives on the instance (`Scanner.state` + `Scanner.stateChanges`); cross-cutting observability lives on the global `Bluey.events`. Consumers who want one or the other have a clean choice.

### D7 — `Bluey.create()` timeout falls back to existing `unknown` semantics

If the platform's first state event never arrives (e.g. plugin misconfigured, native-side bug, mock platform that never emits), `Bluey.create()` completes after a short timeout with `_currentState = BluetoothState.unknown`. Subsequent factory calls throw the same `BluetoothUnavailableException` they would have without this design. No new failure mode; the existing one stays as the fallback.

Timeout value: 2 seconds. Long enough to absorb real-world plugin init; short enough to surface a stuck initialization promptly.

## Test strategy

### Per-convention tests

Each convention gets its own test group:

- **Convention 2 (replay on subscribe)**: for each Type A stream, assert that a late subscriber receives the current value as its first event.
- **Convention 3 (terminal signal)**: for each Type A stream, simulate invalidation and assert either the enum value is emitted (for enum-extensible types) or `addError` fires with `StaleHandleException`. Then assert the paired sync getter returns/throws to match.
- **Convention 4 (Type B clean close)**: for each Type B stream, simulate invalidation and assert `onDone` fires with no error.
- **Convention 5 (resource cancel)**: `Scanner.scan()` consumer cancels their subscription; assert `_platform.stopScan()` was called.
- **Convention 6 (sync getter honesty)**: each sync getter exercised post-invalidation, asserts agreement with the stream's last signal.

### Lifecycle state-machine tests

- **Scanner**: each `ScanState` transition exercised. Events emitted at the right transitions. `isScanning` derived correctly.
- **Server**: same for `AdvertisingState`.

### Async-init tests

- `Bluey.create()` returns with `currentState != unknown` when the fake platform emits state at attach.
- `Bluey.create()` returns with `currentState == unknown` after the 2s timeout if the fake doesn't emit.
- `bluey.scanner()` after a successful `Bluey.create()` doesn't throw spuriously.

### Existing test impact

- Most existing tests construct `Bluey()` synchronously. They all migrate to `await Bluey.create()`. This is a sweep — ~20-30 test files.
- Existing fakes (`FakeBlueyPlatform`, `MockBlueyPlatform`) need to support `Bluey.create()`'s first-event-await:
  - On `simulatePeripheral`, the fake should emit the cached state via `stateStream` to satisfy the await.
  - Or: the fake's defaults should automatically emit `BluetoothState.on` on subscribe.

## Sequencing (rough phases — actual plan will refine)

Each phase is a green checkpoint.

1. **Add new enum values** (`ConnectionState.invalidated`, new `ScanState`, new `AdvertisingState`) and lifecycle events. No behavior change yet.
2. **Apply Convention 2** (replay on subscribe) to every Type A stream + new `Bluey.create()`. Updates I334 + PR P1.
3. **Apply Convention 3** (terminal signal at end-of-life) to every Type A stream. Updates PR P2.
4. **Apply Convention 5** (resource-backed `onCancel`) to `Scanner.scan()`. Updates I335.
5. **Scanner state machine** integration: route `scan()` / `stop()` / `timeout` / `onCancel` through the `ScanState` transitions. Emit transient events.
6. **Server advertising state machine**: same shape.
7. **Migrate internal call sites** (every internal listener handles new error/terminal events; existing tests updated for async `Bluey.create()`).
8. **Mark tickets resolved** (I334, I335, PR comments, scanner-lifecycle-event scope).

## Risks

- **R1: Test migration sweep is large.** ~20-30 test files construct `Bluey()` synchronously. Each becomes async. Possible mechanical errors. Mitigation: do this as one focused commit with `flutter analyze` + full test suite green at the end.

- **R2: Internal listeners may not handle `addError` paths.** Every internal `.listen(...)` on a Type A stream that doesn't pass `onError` will produce `Unhandled exception` warnings when invalidation fires. Mitigation: audit during Convention 3 work; add `onError` handlers explicitly to every internal listener.

- **R3: The 2-second `Bluey.create()` timeout might be wrong for some platforms.** Slow Android cold start could exceed it; very fast iOS might not need it. Mitigation: make it configurable via a parameter on `Bluey.create({Duration? initialStateTimeout = const Duration(seconds: 2)})`. Default that handles 99% of cases; consumers can tune for edge devices.

- **R4: Adding new enum values is technically breaking** for consumers with exhaustive `switch` statements. Mitigation: bluey has no external consumers per the I325/I333 context — this is fine. Document the new values in CHANGELOG / migration notes if external consumers ever exist.

- **R5: `Server.advertisingStateChanges` is a new public surface.** Worth confirming the abstract `Server` interface placement matches the rest of the file. Mitigation: align with how `Connection.stateChanges` is declared. Trivial.

- **R6: Adapter-cycle edge case during `Bluey.create()`.** If the adapter cycles off *during* the 2-second window, the first state event might be `off` rather than `on`. The factory returns with `currentState = off`. Next factory call throws `BluetoothDisabledException` correctly. No regression — this is exactly what we want.

## Non-goals

- Auto-reconnect / session-replay.
- Removing `BluetoothState.unknown`.
- Sealed-class stream wrappers (`Stream<ServiceTreeState>` etc.).
- New events on Connection beyond what exists (`ConnectingEvent` / `ConnectedEvent` stay).
- Backwards-compatibility shims for the `Bluey()` → `Bluey.create()` migration. No existing external consumers; bluey-internal code migrates directly.
