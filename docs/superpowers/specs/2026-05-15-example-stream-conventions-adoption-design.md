# Example app: stream-conventions adoption design

**Status:** Draft, 2026-05-15
**Branch:** `feature/example-stream-conventions-adoption`
**Sibling work:** Builds on PR #32 (Stream + state-surface conventions sweep, merged as `4b1ddbf`).

## Goal

Update the `bluey/example/` Flutter app so it leverages — and demonstrates — the stream and state-surface affordances introduced in PR #32. The current example was migrated to `Bluey.create()` but otherwise still uses the pre-PR patterns: it holds a `Scanner` reference solely to call `stop()`, manually seeds state from `currentState` (workaround for missing replay), uses `bool isScanning` / `bool isAdvertising` instead of the new state enums, and has zero handling for adapter-cycle invalidation. Consumers who learn bluey by reading the example will inherit those stale patterns.

The example after this work should be a reference, not a relic.

## Scope decisions

Five conversational gates set the scope:

1. **Invalidation recovery UX: manual.** When the adapter cycles and bluey instances go invalidated, the example shows an inline banner with a `Recover` button. The user clicks it; the example reconstructs the `Bluey` root and resets feature state. No silent auto-recovery — the lesson is that consumers need to handle invalidation explicitly.

2. **Feature scope: core three + service_explorer.** `scanner`, `connection`, `server`, `service_explorer`. `stress_tests` is excluded — it's a performance harness, not a lifecycle demo.

3. **Event log placement: per-feature.** Each affected feature surfaces relevant `bluey.events` in its existing (or new) log panel. No new "Events" top-level tab; consumers learning the scanner read the scanner screen.

4. **Adapter-cycle discoverability: inline hint, no debug seam.** Each affected screen gets a quiet footer line: "Tip: toggle Bluetooth in system settings to see recovery in action." No library debug API for triggering invalidation; real OS toggle is what consumers will exercise.

## Per-feature changes

### Scanner (`bluey/example/lib/features/scanner/`)

- `BlueyScannerRepository` (`infrastructure/bluey_scanner_repository.dart`): drop the `Scanner? _scanner` stash and the explicit `stopScan()` method. `scan()` returns the stream directly; cancellation triggers the new `onCancel → stop()` path. The `StopScan` application-layer use case becomes redundant and is removed along with its DI registration.
- `ScannerCubit.initialize` (`presentation/scanner_cubit.dart`): drop the manual `_getBluetoothState.current` seed read. `Bluey.stateStream` now replays on subscribe.
- `ScannerState`: replace `bool isScanning` with `ScanState scanState` (default `ScanState.stopped`). All call sites updated in the same commit.
- `ScannerCubit` subscribes to `scanner.stateChanges` and reflects it in `scanState`.
- Scanner screen UI: action buttons disabled during `starting`/`stopping` transients; `Stop` enabled only when `scanning`.
- **New scan log panel** on the scanner screen. Subscribes to `bluey.events`, filters to `ScanStartingEvent` / `ScanStartedEvent` / `ScanStoppingEvent` / `ScanStoppedEvent` / `DeviceDiscoveredEvent`. Capped at the last 100 entries.
- Invalidation recovery: when `scanner.state == ScanState.invalidated`, render `InvalidationBanner` at the top of the screen with a `Recover` button that calls `serviceLocator.recreateBluey()`.

### Server (`bluey/example/lib/features/server/`)

- `ServerCubit.state`: replace `bool isAdvertising` with `AdvertisingState advertisingState` (default `AdvertisingState.idle`).
- `ServerCubit` subscribes to `server.advertisingStateChanges` and reflects it in `advertisingState`.
- `AdvertisingStateChip` (`shared/presentation/bluetooth_state_chip.dart`): change signature from `bool isAdvertising` to `AdvertisingState advertisingState`. Add visual cases for `starting`/`stopping` (orange chip + spinner avatar) and `invalidated` (red chip). Update all call sites.
- Existing `ServerLogEntry` log extended to ingest `bluey.events` advertising lifecycle events alongside the cubit's own ad-hoc messages. Implementation: `ServerLogEntry.fromBlueyEvent(BlueyEvent)` constructor.
- Invalidation recovery: same `InvalidationBanner` pattern.

### Connection (`bluey/example/lib/features/connection/`)

- `ConnectionCubit`: drop the manual `connection.state` read after subscribing to `stateChanges` — the stream now replays.
- Drop the redundant `loadServices()` call after subscribing to `servicesChanges` — also replays.
- Catch `StaleHandleException` on read/write/notify operations; map to the invalidated state and surface the banner.
- Connection screen: when `connection.state == ConnectionState.invalidated`, render `InvalidationBanner` with `Reconnect` button. `ConnectionStateChip` already has the `invalidated` case from prior I333 work — reused.

### Service Explorer (`bluey/example/lib/features/service_explorer/`)

- `ServiceCubit` subscribes to `connection.servicesChanges` for live re-discovery on Service Changed indications.
- Catch `StaleHandleException` on read/write/notify; surface via the connection-level invalidation banner (the service explorer always opens from an existing connection).
- No new event log section; existing read/write/notify `LogEntry` log stays as-is.

## Shared widgets

### `InvalidationBanner` (new, `shared/presentation/`)

Material banner widget. Takes:
- `String label` (default: "Bluetooth was cycled. Tap to recover.")
- `String actionLabel` (default: "Recover")
- `VoidCallback onRecover`

Rendered at the top of any screen whose feature is in an invalidated state. Tapping the action calls the recovery callback.

### `AdapterCycleHint` (new, `shared/presentation/`)

Stateless footer widget. Single line of muted-color body text: "Tip: toggle Bluetooth in system settings to see recovery in action." Always shown at the bottom of scanner, server, and connection screens. No dismissal state — keeps the implementation simple and the hint always discoverable.

### `AdvertisingStateChip` (modified, `shared/presentation/bluetooth_state_chip.dart`)

Signature changes from `bool isAdvertising` to `AdvertisingState advertisingState`. Visual mapping:

| State | Color | Avatar |
|---|---|---|
| `idle` | grey | `cell_tower_outlined` |
| `starting` | orange | small spinner |
| `advertising` | green | `cell_tower` |
| `stopping` | orange | small spinner |
| `invalidated` | red | `error_outline` |

## Recovery flow architecture

A cycled adapter invalidates *every* bluey-derived live instance. Per-feature recovery in isolation would race against the shared root. Recovery is centralized.

### `RecoveryNotifier` (new, `shared/domain/`)

A simple stream-based notifier (`Stream<void>`). Each affected cubit subscribes in its constructor and resets its state on tick.

### `ServiceLocator.recreateBluey()` (new method)

```text
1. Cancel any subscriptions the locator holds on the current Bluey.
2. Dispose the current Bluey instance.
3. await Bluey.create() to construct a fresh instance.
4. Re-register Scanner / Server / Connection-related factories that capture the new Bluey reference.
5. Broadcast on RecoveryNotifier so each cubit resets.
```

### Per-cubit recovery handler

Each affected cubit's constructor takes a `RecoveryNotifier`. On notification, the cubit:
- Releases its prior bluey-derived references (cancels subscriptions to the now-dead instance).
- Resets state to the post-construction starting point (no active scan, no connection, no server, empty log).
- Re-emits the clean state so the invalidation banner clears.

The user is then in a clean state and re-performs the action manually (start scan, connect, start advertising). The example does **not** auto-resume the prior action — that would conflict with the manual-recovery decision and hide the lifecycle the example is supposed to teach.

## State model changes (summary)

| Field | Before | After |
|---|---|---|
| `ScannerState.isScanning` | `bool` | `ScanState scanState` |
| `ScannerState.scanLog` | — | `List<BlueyEvent>` (capped at 100) |
| `ServerState.isAdvertising` | `bool` | `AdvertisingState advertisingState` |
| `ServerState.log` | `List<ServerLogEntry>` | unchanged; gains `ServerLogEntry.fromBlueyEvent` constructor |
| `ConnectionState` (cubit) | manual `connection.state` cache | derived from `stateChanges` replay |
| `ServiceState` (cubit) | services read once on open | subscribes to `servicesChanges` for re-discovery |

## Testing

Library code is unchanged; no new bluey-package tests.

**Cubit tests** (`bluey/example/test/`)

- `ScannerCubit`: state-transition tests for `stopped → starting → scanning → stopping → stopped` driven by the underlying scanner stream. Invalidation test: simulate `FakeBlueyPlatform.setState(off)`, assert cubit emits the invalidated state, then call `recreateBluey()` and assert clean reset. Event log test: assert lifecycle events land in `scanLog`.
- `ServerCubit`: equivalent for advertising state transitions, invalidation, and log ingestion.
- `ConnectionCubit`: invalidation test (assert `StaleHandleException` on a stale read is caught, state flips to invalidated, banner-ready). `stateChanges` replay test (assert initial state is observed without a separate read).
- `ServiceCubit`: `servicesChanges` replay test; `StaleHandleException` handling.

**Widget tests**

- `InvalidationBanner`: renders correctly, callback fires on tap.
- `AdvertisingStateChip`: each enum case renders the expected color + avatar.

**Integration test (single golden path)**

Full adapter-cycle scenario through the scanner screen: start a scan, cycle the adapter, verify the banner appears, tap recover, verify a fresh scan can start cleanly. One end-to-end is enough; cubit unit tests cover the edges.

## Migration order

Each step lands as its own commit so the diff is reviewable feature-by-feature.

1. **Foundations.** `RecoveryNotifier`, `ServiceLocator.recreateBluey()`, `InvalidationBanner`, `AdapterCycleHint`. Pure additions with their own tests.
2. **AdvertisingStateChip.** Signature change + all call-site updates in one commit so the build stays green.
3. **Scanner feature.** Repository, cubit, screen, scan log. Most-affected feature; first to validate the recovery flow end-to-end.
4. **Server feature.** Cubit, screen, log ingestion.
5. **Connection feature.** Cubit changes (drop redundant reads, catch `StaleHandleException`, wire banner).
6. **Service explorer.** Subscribe to `servicesChanges`; catch `StaleHandleException`.
7. **Adapter-cycle hint.** Add `AdapterCycleHint` to scanner / server / connection screens.

## Non-goals

- **No bluey library changes.** The library shipped in PR #32 is the contract. If the example reveals a gap, it goes into the backlog as a separate issue.
- **No `stress_tests` updates.** Excluded by scope decision.
- **No global event-inspection panel.** Excluded by scope decision; per-feature only.
- **No SharedPreferences / persistence** for the adapter-cycle hint. Static text, always shown.
- **No auto-resume** of the prior action after recovery. Manual, by design.

## Open questions / risks

- **Recovery while a stress test is running.** The `stress_tests` feature uses bluey extensively. If the adapter cycles mid-test, the cubit will see invalidation; behavior is undefined under this work's scope. Acceptable: stress tests are out of scope, and the diagnostic value of "the test crashed because Bluetooth cycled" is itself a useful demo of why invalidation matters.
- **Connection screen recovery flow needs the prior Device reference.** `Reconnect` button must remember which device the user was connected to. The cubit already retains the device reference for display purposes; verify it's available post-invalidation. If not, the recovery button degrades to "go back to scanner" — acceptable but worth confirming during implementation.

## Success criteria

- All call sites of `Bluey.scanner()` use the cancel-stops-scan affordance; no example code holds a `Scanner` reference solely for `stop()`.
- All `bool isScanning` / `bool isAdvertising` UI state replaced with the corresponding enum.
- Cycling the adapter while any feature is active surfaces an `InvalidationBanner`; `Recover` returns the example to a clean usable state.
- New scan event log on the scanner screen displays lifecycle events.
- Server's existing log displays advertising lifecycle events alongside its own messages.
- All existing example tests still pass; new cubit/widget tests added.
