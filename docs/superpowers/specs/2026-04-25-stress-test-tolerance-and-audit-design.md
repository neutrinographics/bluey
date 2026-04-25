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

1. **Control location:** stress-test screen, top of the screen above the test cards. Collocated with what it affects.
2. **Control shape:** segmented control with three named options — `Strict (1)`, `Tolerant (3)`, `Very tolerant (5)`. Default is `Strict (1)` (matches library default).
3. **Behaviour on change:** disconnect → reconnect with new value → surface a brief inline status (`Reconnecting…`) → resume.
4. **Disabled-while-running:** the segmented control is disabled while any test is running (same gating that the per-test Run buttons already have).
5. **Persistence:** session-only via the existing `ConnectionSettingsCubit`. The control's selected segment derives from the cubit's current state.
6. **Description scope:** all 7 tests get audited. Most will get small subtitle sharpenings. Failure-injection gets a full rewrite of `readingResults`. Timeout-probe gets a small update to mention the post-I079 reality.

## Architecture

### UI: a new `_ConnectionToleranceBar` widget

New file: `bluey/example/lib/features/stress_tests/presentation/widgets/connection_tolerance_bar.dart`.

A small horizontal strip rendered above the test grid in `stress_tests_screen.dart`. Reads `ConnectionSettingsCubit` state, dispatches `setMaxFailedHeartbeats` on segment tap. When `state.connectionState == connecting`, shows an inline `Reconnecting…` indicator beside the device name.

The widget is purely presentational; it does not own connection lifecycle. It calls into `ConnectionSettingsCubit` (which doesn't touch the connection) and into `ConnectionCubit` (which owns the disconnect/reconnect mechanics).

### Cubit: `ConnectionCubit.applySettings(settings)`

New method on `ConnectionCubit`:

```dart
/// Applies new connection settings by tearing down the current connection
/// and reconnecting. Used when the user changes tolerance mid-session.
Future<void> applySettings(ConnectionSettings newSettings) async {
  if (newSettings == _settings) return;
  _settings = newSettings;

  final hadConnection = state.connection != null;
  await _stateSubscription?.cancel();
  _stateSubscription = null;
  await state.connection?.disconnect();
  emit(state.withoutConnection());

  if (hadConnection) {
    await connect();
  }
}
```

This goes alongside the existing `connect()` / `disconnect()`. The bar widget calls `cubit.applySettings(settings.copyWith(maxFailedHeartbeats: N))` on segment tap. The `ConnectionSettingsCubit` is updated by the same dispatch path.

The "no auto-reconnect on involuntary disconnect" policy from I087's wontfix is preserved: this method is only called from explicit user action via the new control.

### `_ConnectionToleranceBar` UI shape

```
┌─────────────────────────────────────────────────┐
│ Heartbeat tolerance:  [Strict] [Tolerant] [Very │
│ Pixel 6a                            tolerant]   │
└─────────────────────────────────────────────────┘
```

On tap of an unselected segment:
1. Widget calls `connectionSettingsCubit.setMaxFailedHeartbeats(N)`.
2. Widget calls `connectionCubit.applySettings(updatedSettings)`.
3. Cubit transitions through `disconnected → connecting → connected`.
4. Widget shows `Reconnecting with tolerance=N…` while `connectionState == connecting`.
5. Once `connected`, the bar resumes its normal layout.

If the new connection fails, the existing disconnect dialog flow handles it (same as if any connection attempt fails).

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

`ConnectionCubit` has existing tests at `bluey/example/test/features/connection/presentation/connection_cubit_test.dart` (or similar — verify path during plan). Add:

- **Red 1:** `applySettings(newSettings)` re-uses the existing connection's tear-down + connect-again machinery; the test asserts that calling `applySettings` with a different `maxFailedHeartbeats` results in the cubit calling `_disconnectDevice` and then `_connectToDevice` again with the new settings.
- **Red 2:** `applySettings` with the same settings is a no-op (no disconnect, no reconnect).
- **Red 3:** `applySettings` while no connection is active just updates `_settings` without attempting connect.

### Bar widget changes

`bluey/example/test/features/stress_tests/presentation/widgets/` already contains widget tests. Add `connection_tolerance_bar_test.dart`:

- Renders three segments with correct labels.
- The currently-selected segment matches the cubit's current state.
- Tap on an unselected segment dispatches `setMaxFailedHeartbeats(N)` AND calls `applySettings` on the connection cubit.
- Disabled when any stress test is running.

### Description audit

Existing tests in `bluey/example/test/features/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart` may assert specific strings. We **first** check what's asserted; for any string that's about to change, the test is updated to match the new wording (the tests are documenting our presentation contract — if we change the contract, we change the tests).

Subtitle moved from duplicated extensions to a single domain extension: existing tests that read `_subtitle` need updating to read from the new location. Tests for the domain `StressTest` enum (if any) get a new test verifying each test has a non-empty subtitle. We don't unit-test specific wording at the domain level — that's UI concern.

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
