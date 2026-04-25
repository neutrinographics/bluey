# Stress-Test Tolerance Setting + Description Audit

**Status:** proposed
**Date:** 2026-04-25
**Scope:** `bluey/example` only — UI control on the stress-test screen for `maxFailedHeartbeats`, supporting mid-session reconnect, plus a full audit of all 7 stress-test descriptions and subtitles. No library changes, no platform changes.
**Backlog entry:** none new — closes the descriptive concern noted in I087's wontfix resolution.

## Problem

Two concerns surfaced during the I079 / I096 / I087 sequence:

1. **The failure-injection test's behaviour now depends on a connection-time setting (`maxFailedHeartbeats`) that the example app doesn't expose.** With the default value of `1`, a single dropped server response triggers the disconnect cascade we observed (1 timeout + N-1 disconnects). With a higher value, the same scenario produces clean recovery (1 timeout + N-1 successes). Both behaviours are intended library outcomes; both are useful to demonstrate. The example app currently only exercises one of them.

2. **Stress-test descriptions are stale or misleading.** Several tests (notably failure-injection and timeout-probe) have help-sheet copy that pre-dates the I079 fix and the post-I096 verification. Subtitles like "Protocol resilience check" and "Error handling validation" are vague enough to be unhelpful. After I087's wontfix resolution, the failure-injection description in particular needs to honestly describe the disconnect-cascade outcome and explain the tolerance setting that produces the recovery alternative.

## Goals

- Expose `maxFailedHeartbeats` as a user-tunable on the stress-test screen via a compact segmented control. Changing it triggers a transparent disconnect/reconnect.
- Audit and rewrite descriptions for all 7 stress tests so that:
  - Subtitles state *what* is verified, not jargon.
  - Help-sheet `whatItDoes` accurately describes the test's mechanics post-I079.
  - Help-sheet `readingResults` describes the *actual* current outcome with default settings, with explicit notes about the tolerance setting where it changes the test's behaviour.

## Non-goals

- **Not adding auto-reconnect to `ConnectionCubit`.** I087's wontfix resolution stands — the cubit's manual-reconnect dialog is the deliberate UX. Mid-session reconnect on settings *change* is a different mechanism (user-initiated via the segmented control), not auto-reconnect on involuntary disconnect.
- **Not adding new test parameters.** The tolerance control is a connection-level setting, not a per-test config; it lives outside the per-test config form.
- **Not changing library APIs.** `bluey.connect()` already accepts `maxFailedHeartbeats`. The example app's `ConnectionSettings` and `ConnectionSettingsCubit` already model it. Only UI and cubit wiring are added.
- **Not persisting the setting across app restarts.** Session-scoped is sufficient for a demo.
- **Not changing the failure-injection or timeout-probe runner code itself.** Their behaviour is correct; only their *descriptions* are wrong.

## Decisions locked

1. **Control location: connection screen**, not stress-tests screen. Reasoning: `StressTestsScreen` receives the `Connection` as a constructor param via `Navigator.push`, and `StressTestsCubit` captures that reference at construction. A mid-screen reconnect would leave the cubit holding a dead connection — ops would fail until the user manually re-entered the screen. Restructuring `StressTestsCubit` to observe a connection stream instead of capturing a ref is a non-trivial refactor for a demonstrative feature. The connection screen already owns the settings (line 54 of `connection_screen.dart`: `settings: getIt<ConnectionSettingsCubit>().state`), so the natural placement is there. Users switch scenarios via "back → change → forward" — two extra taps, same educational outcome.
2. **Stress-tests screen gets a read-only indicator** showing the active tolerance, so users running tests can see what mode they're in without leaving the screen. Tapping the indicator pops back to the connection screen for changes.
3. **Control shape on connection screen:** segmented control with three named options — `Strict (1)`, `Tolerant (3)`, `Very tolerant (5)`. Default is `Strict (1)` (matches library default).
4. **Behaviour on change:** dispatch `setMaxFailedHeartbeats(N)` on `ConnectionSettingsCubit`. The connection cubit observes the settings cubit and triggers a reconnect via the new `applySettings` method (disconnect → reconnect with new value → resume). The connection screen's existing `_showDisconnectedDialog` is suppressed during this user-initiated transition.
5. **Persistence:** session-only via the existing `ConnectionSettingsCubit`. The control's selected segment derives from the cubit's current state.
6. **Description scope:** all 7 tests get audited. Most will get small subtitle sharpenings. Failure-injection gets a full rewrite of `readingResults`. Timeout-probe gets a small update to mention the post-I079 reality.

## Architecture

### UI: a new `_ToleranceControl` widget on the connection screen

New file: `bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart`.

A horizontal segmented control rendered on the connection screen, near the existing service-list area (above or below the Stress Tests button — final placement decided in the plan based on layout fit). Reads `ConnectionSettingsCubit` state, dispatches `setMaxFailedHeartbeats` on segment tap.

When tapped:
1. Widget calls `connectionSettingsCubit.setMaxFailedHeartbeats(N)`.
2. The `ConnectionCubit` (which now subscribes to the settings cubit — see below) observes the change and triggers `applySettings(updatedSettings)`.
3. The connection screen's existing connection-state UI handles the transient `connecting` state visibly (the user already sees "Connecting…" on initial connect; this just re-uses that path).
4. Once reconnected, the user can proceed to Stress Tests.

The widget is purely presentational. It does not own connection lifecycle.

### Cubit: `ConnectionCubit` subscribes to `ConnectionSettingsCubit`

`ConnectionCubit`'s constructor changes to accept `ConnectionSettingsCubit` (or `Stream<ConnectionSettings>`) and subscribe to it:

```dart
ConnectionCubit({
  required Device device,
  required ConnectToDevice connectToDevice,
  required DisconnectDevice disconnectDevice,
  required GetServices getServices,
  required ConnectionSettingsCubit settingsCubit,
}) : ... {
  _settings = settingsCubit.state;
  _settingsSubscription = settingsCubit.stream.listen(_handleSettingsChange);
}

Future<void> _handleSettingsChange(ConnectionSettings newSettings) async {
  if (newSettings == _settings) return;
  _settings = newSettings;
  if (state.connection != null) {
    // User-initiated change; reconnect to apply.
    _suppressDisconnectDialog = true;
    await state.connection?.disconnect();
    _suppressDisconnectDialog = false;
    await connect();
  }
}
```

A flag `_suppressDisconnectDialog` is read by the existing `_stateSubscription.listen` handler so the "Device disconnected" error is not emitted during a user-initiated tolerance change.

### Read-only indicator on the stress-tests screen

`stress_tests_screen.dart` adds a small status pill in the top bar showing the active tolerance:

```
┌──────────────────┐
│ Stress Tests     │
│ Tolerance: Strict│  ← read-only chip; tap pops back to connection screen
└──────────────────┘
```

This widget reads `getIt<ConnectionSettingsCubit>().state.maxFailedHeartbeats` and renders the corresponding label. Tapping it calls `Navigator.of(context).pop()` to return to the connection screen where the user can change it.

This indicator is purely informational; no settings logic lives here.

### Description audit

The audit happens in two files:

- `bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart` (and the duplicate `_subtitle` extension in `stress_test_help_sheet.dart`)
- `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`

The current subtitle is also duplicated between two files — opportunistic cleanup: define `_subtitle` once on the domain `StressTest` enum in `stress_test.dart` (alongside `displayName`), and have both views read from there. Removes the duplication.

**Per-test changes (proposed wording — finalised in plan):**

| Test | Current subtitle | Proposed subtitle |
|---|---|---|
| burstWrite | Rapid throughput validation | Sustained writes at maximum rate |
| mixedOps | Read/Write/Notify sequence | Interleaved GATT operations |
| soak | Stability & memory leakage | Long-running stability under steady load |
| timeoutProbe | Protocol resilience check | Slow server response is tolerated |
| failureInjection | Error handling validation | Server drops a response — see what happens |
| mtuProbe | Maximum transfer unit check | MTU negotiation and large-payload writes |
| notificationThroughput | Notification delivery rate | Burst notification reception |

**Help-sheet `readingResults` changes:**

- **failureInjection** — full rewrite (this is the misleading one). New shape:
  > **With tolerance=1 (default):** Expect 1 `GattTimeoutException` (the dropped write) followed by `writeCount−1` `GattOperationDisconnectedException`s as the queued ops drain. The connection ends in `disconnected` state — this is the correct outcome of a dead-peer detection; tap the dialog's `Reconnect` to start over. **With tolerance=3 or higher:** Expect 1 `GattTimeoutException` and `writeCount−1` successes — the library tolerates the single dropped response and the test demonstrates clean recovery. Use the tolerance control above to switch between these scenarios.
- **timeoutProbe** — small update to acknowledge the post-I079 reality:
  > Expect exactly 1 `GattTimeoutException` (the slow write) and all subsequent writes to succeed against the same connection. The connection survives the slow response — this verifies that a long-running server-side operation does not trip a spurious disconnect.
- **The other five tests** — minor wording cleanups for clarity; no factual changes. Specific edits listed in the plan.

## TDD

### Cubit changes

Existing tests at `bluey/example/test/connection/presentation/connection_cubit_test.dart` use `bloc_test`'s `blocTest` helper. The cubit constructor signature changes (adds `ConnectionSettingsCubit`), so existing tests need a small update to pass a settings cubit. Then add:

- **Red 1:** When the settings cubit emits a new value with a different `maxFailedHeartbeats`, the connection cubit triggers a reconnect — visible as a `disconnected → connecting → connected` state sequence and a fresh call to `_connectToDevice` with the new settings.
- **Red 2:** When the settings cubit emits the same value, no reconnect occurs.
- **Red 3:** When the settings cubit changes while no connection is active, no reconnect attempt is made (settings just track for the next connect).
- **Red 4:** Verify the "Device disconnected" error is suppressed during a user-initiated tolerance change (the existing assertion behavior on involuntary disconnects is preserved).

### Tolerance-control widget tests

New file: `bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart`:

- Renders three segments with correct labels (`Strict`, `Tolerant`, `Very tolerant`).
- The currently-selected segment matches the cubit's `maxFailedHeartbeats` state (1 → Strict, 3 → Tolerant, 5 → Very tolerant).
- Tap on an unselected segment dispatches `setMaxFailedHeartbeats(N)` on the settings cubit.

### Stress-tests indicator widget tests

New file: `bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart`:

- Renders the current tolerance label.
- Tapping pops the navigator (back to connection screen).

### Description audit

Existing tests at `bluey/example/test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart` only assert structural elements (display name appears, section labels exist, info button is on each card) — they do NOT assert specific subtitle or `whatItDoes`/`readingResults` wording. Reviewed during spec drafting. So changing wording does not require test updates.

Subtitle is currently duplicated between `test_card.dart` and `stress_test_help_sheet.dart`. Refactor: move to a single `subtitle` extension on the domain `StressTest` enum in `stress_test.dart` (alongside `displayName`). Both views read from there. Removes duplication.

## Caveats

### Reconnection during a test

If the user changes tolerance while a test is running, the segmented control is disabled — that's the simplest gating. We do not attempt to abort+reconnect+resume mid-test; running tests run to completion (or the user stops them via the existing Stop button) before tolerance can be changed.

### What if reconnection fails?

The existing `connect()` flow handles connect failures by emitting `disconnected` with an error message. The disconnected dialog appears (just as it would if the device went out of range). This is consistent with current UX — no new failure path needed.

### Default value remains 1

Library default is `maxFailedHeartbeats = 1`. The example app's `ConnectionSettings` default is also `1`. The segmented control opens with `Strict (1)` selected. This means new users still see the disconnect-cascade behaviour by default — the tolerance setting is opt-in for those who want to demonstrate recovery.

### Test count

`bluey/example` test suite count goes up by ~5–10 (cubit + widget tests). No removals expected unless an existing test asserts wording we're changing.

## Risks and rollback

**Risks:**

- Cubit's `applySettings` reuses existing disconnect + connect logic, so failure modes (mid-flight ops at the moment of disconnect) are inherited from the existing paths. No new failure modes introduced.
- The segmented control adds vertical space to the stress test screen. Should fit; if not, the layout adjustment is trivial.

**Rollback:** revert the additive widget + cubit method + audit text changes. No state, no migration.

## Future work

- The setting should probably also be visible on the connection screen for power users who want to set it before connecting (eliminating the initial reconnect). Out of scope for this iteration.
- A "max heartbeat interval" tunable would similarly let users demonstrate I077-class scenarios. Out of scope.
- Consider expanding the wontfix table heading to formally include "superseded premise" type entries (currently just "documented platform limitations"). Cosmetic.
