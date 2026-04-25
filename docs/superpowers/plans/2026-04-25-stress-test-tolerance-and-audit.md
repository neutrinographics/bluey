# Stress-Test Tolerance + Description Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `maxFailedHeartbeats` as a tunable on the connection screen, with a read-only indicator on the stress-tests screen. Audit and rewrite stress-test descriptions to match the post-I079 / post-I096 reality.

**Architecture:** Connection-screen segmented control writes to `ConnectionSettingsCubit`. `ConnectionCubit` subscribes to that cubit and triggers reconnect on change. Stress-tests screen reads `ConnectionSettingsCubit` for a read-only chip. Subtitle is consolidated to a single domain extension. Help-content `whatItDoes` and `readingResults` rewritten per test.

**Tech Stack:** Flutter, flutter_bloc, mocktail / bloc_test for tests.

**Spec:** [`docs/superpowers/specs/2026-04-25-stress-test-tolerance-and-audit-design.md`](../specs/2026-04-25-stress-test-tolerance-and-audit-design.md)

**Working directory for all commands:** `/Users/joel/git/neutrinographics/bluey/.worktrees/stress-tolerance-audit`.

**Branch:** `feature/stress-tolerance-audit` off `main`.

---

## File Structure

| File | Role |
|---|---|
| `bluey/example/lib/features/stress_tests/domain/stress_test.dart` | Add `subtitle` extension alongside `displayName` |
| `bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart` | Remove duplicate `_subtitle`; use domain extension |
| `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart` | Remove duplicate `_subtitle`; use domain extension |
| `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart` | Rewrite `whatItDoes` + `readingResults` for all 7 tests |
| `bluey/example/lib/features/connection/presentation/connection_cubit.dart` | Add `ConnectionSettingsCubit` constructor param + subscription that triggers reconnect on change |
| `bluey/example/lib/features/connection/presentation/connection_screen.dart` | Pass settings cubit to `ConnectionCubit`; render tolerance control |
| `bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart` | **New** — segmented control |
| `bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart` | Add tolerance-indicator chip to top bar |
| `bluey/example/lib/features/stress_tests/presentation/widgets/tolerance_indicator.dart` | **New** — read-only chip |
| `bluey/example/test/connection/presentation/connection_cubit_test.dart` | Update existing tests for new constructor signature; add settings-driven reconnect tests |
| `bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart` | **New** widget tests |
| `bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart` | **New** widget tests |

---

## Task 1: Set up the feature worktree

- [ ] **Step 1: Confirm primary worktree state**

```bash
cd /Users/joel/git/neutrinographics/bluey
git status -s
git log --oneline -3
```

Expected: clean working tree on `main` with recent commit `f859342 docs(spec): pivot tolerance control to connection screen` (or later).

- [ ] **Step 2: Create the worktree**

```bash
git worktree add .worktrees/stress-tolerance-audit -b feature/stress-tolerance-audit
```

- [ ] **Step 3: Verify and pub get**

```bash
cd .worktrees/stress-tolerance-audit/bluey/example && flutter pub get 2>&1 | tail -3
cd ../..
```

- [ ] **Step 4: Run example tests as baseline**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
```

Record the baseline pass count for later comparison.

---

## Task 2: Consolidate `subtitle` onto the domain enum

**Rationale:** Currently `_subtitle` is duplicated as a private extension in `test_card.dart` and `stress_test_help_sheet.dart`. Move to a single domain-level extension. This is a behaviour-preserving refactor.

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/domain/stress_test.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart`

- [ ] **Step 1: Add `subtitle` to the domain extension**

In `stress_test.dart`, extend the existing `StressTestX` extension:

```dart
extension StressTestX on StressTest {
  /// Human-readable name shown on the test card.
  String get displayName => switch (this) {
        StressTest.burstWrite => 'Burst write',
        StressTest.mixedOps => 'Mixed ops',
        StressTest.soak => 'Soak',
        StressTest.timeoutProbe => 'Timeout probe',
        StressTest.failureInjection => 'Failure injection',
        StressTest.mtuProbe => 'MTU probe',
        StressTest.notificationThroughput => 'Notification throughput',
      };

  /// Short subtitle shown beneath the display name. Names *what* the test
  /// verifies, not jargon. Audited 2026-04-25.
  String get subtitle => switch (this) {
        StressTest.burstWrite => 'Sustained writes at maximum rate',
        StressTest.mixedOps => 'Interleaved GATT operations',
        StressTest.soak => 'Long-running stability under steady load',
        StressTest.timeoutProbe => 'Slow server response is tolerated',
        StressTest.failureInjection => 'Server drops a response — see what happens',
        StressTest.mtuProbe => 'MTU negotiation and large-payload writes',
        StressTest.notificationThroughput => 'Burst notification reception',
      };
}
```

- [ ] **Step 2: Remove `_subtitle` from `test_card.dart` and use `test.subtitle`**

In `test_card.dart`, delete the entire `_subtitle` switch inside the `_StressTestMeta` extension (lines 55–63). At the call site (line 169), change `test._subtitle` to `test.subtitle`.

- [ ] **Step 3: Remove `_subtitle` from `stress_test_help_sheet.dart` and use `test.subtitle`**

In `stress_test_help_sheet.dart`, delete the entire `_StressTestSubtitle` extension (lines 274–289 — the comment block and the extension). At the call site (line 121), change `test._subtitle` to `test.subtitle`.

- [ ] **Step 4: Run tests to confirm refactor passes**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
```

Expected: all baseline tests pass. The new subtitle wording is different from the old; existing tests don't assert specific subtitle wording (verified during spec drafting), so no test changes needed.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/stress_tests/domain/stress_test.dart \
        bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart \
        bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart
git commit -m "refactor(stress-tests): consolidate subtitle to domain extension + sharpen wording"
```

---

## Task 3: Rewrite help-content `whatItDoes` and `readingResults`

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`

Each test's content is rewritten. Test runners themselves are not changed — only descriptive text.

- [ ] **Step 1: Replace each test's `helpContent` with the audited version**

Open `stress_test_help_content.dart` and replace the entire `helpContent` getter on `StressTestHelpX` extension with:

```dart
extension StressTestHelpX on StressTest {
  StressTestHelpContent get helpContent => switch (this) {
        StressTest.burstWrite => const StressTestHelpContent(
            whatItDoes:
                'Fires count writes to the echo characteristic back-to-back, '
                'each waiting for its acknowledgement before the next is sent. '
                'Pushes the BLE write queue to capacity and measures sustained '
                'throughput end-to-end.\n\n'
                'count sets total writes. bytes is the payload per write — '
                'larger values stress fragmentation and reassembly. Enable '
                'withResponse to require an ATT acknowledgement per write; '
                'disable it for maximum throughput at the cost of delivery '
                'guarantees.',
            readingResults:
                'A low failure rate (ideally zero) confirms the stack handles '
                'sustained writes reliably. Any failures are broken down by '
                'exception type.\n\n'
                'A large gap between median and p95 latency points to '
                'occasional stalls — typically retransmission or flow-control '
                'backpressure on the wire.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
        StressTest.mixedOps => const StressTestHelpContent(
            whatItDoes:
                'Runs iterations cycles of write → read → discover-services → '
                'request-MTU. Each cycle exercises a different GATT operation '
                'in sequence, catching bugs that only appear when operation '
                'types are interleaved — state-machine races, incorrect handle '
                'caching after re-discovery, MTU desync.',
            readingResults:
                'All four operations in a cycle count as one attempt. A failure '
                'in any step is recorded as a single failure for that cycle '
                'with the exception type.\n\n'
                'Watch for GattOperationFailedException — it often indicates a '
                'state-machine bug triggered by the specific sequence. Median '
                'and p95 latency measure end-to-end cycle time.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
        StressTest.soak => const StressTestHelpContent(
            whatItDoes:
                'Sends a write every interval milliseconds for duration '
                'seconds, mimicking a long-running sensor stream. Designed to '
                'expose memory leaks, handle exhaustion, and reliability '
                'degradation under sustained load — not peak throughput.\n\n'
                'duration is the total wall time. interval controls write '
                'cadence — lower values increase pressure. bytes is the '
                'payload per write.',
            readingResults:
                'Focus on failure rate over time, not throughput. A rising '
                'failure count late in the run (compare elapsed vs attempted) '
                'suggests resource exhaustion.\n\n'
                'Connection loss during a soak is a strong signal of a '
                'platform-level memory or handle leak.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.elapsed,
            ],
          ),
        StressTest.timeoutProbe => const StressTestHelpContent(
            whatItDoes:
                'Sends a single write and asks the server to delay its '
                'acknowledgement by delay past timeout milliseconds beyond the '
                'per-operation timeout. Verifies that the client correctly '
                'raises GattTimeoutException for the slow op AND that the '
                'underlying connection survives — a server taking a long time '
                'to respond is not a peer-dead signal.',
            readingResults:
                'Expect exactly 1 GattTimeoutException (the timed-out write). '
                'The connection should remain connected after the timeout, '
                'demonstrating that the lifecycle layer correctly tolerates a '
                'long-running server-side operation.\n\n'
                'If the connection drops, the lifecycle policy is being '
                'tripped by the slow op — see the "Heartbeat tolerance" '
                'setting on the connection screen. With Strict (1), even one '
                'slow op can trip the dead-peer threshold; with Tolerant (3) '
                'or higher, slow ops are absorbed.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
            ],
          ),
        StressTest.failureInjection => const StressTestHelpContent(
            whatItDoes:
                'Issues a drop-next command to the server, then fires '
                'writeCount writes against the echo characteristic. The first '
                'write is silently dropped by the server; subsequent writes '
                'are answered normally. Verifies how the client handles a '
                'single dropped response — and depending on the heartbeat '
                'tolerance setting, demonstrates either clean disconnect or '
                'tolerant recovery.',
            readingResults:
                'Outcome depends on the "Heartbeat tolerance" setting on the '
                'connection screen.\n\n'
                'Strict (1) — the default: expect 1 GattTimeoutException (the '
                'dropped write) followed by writeCount−1 '
                'GattOperationDisconnectedException as the queued ops drain. '
                'The lifecycle layer correctly declares the peer unreachable '
                'and tears down. Tap Reconnect on the disconnected dialog to '
                'start over. This is the disconnect-cascade scenario.\n\n'
                'Tolerant (3) or Very tolerant (5): expect 1 '
                'GattTimeoutException and writeCount−1 successes. A single '
                'dropped response is absorbed, the connection survives, '
                'subsequent writes succeed. This is the recovery scenario.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
            ],
          ),
        StressTest.mtuProbe => const StressTestHelpContent(
            whatItDoes:
                'Requests requestedMtu bytes as the ATT MTU, then sends writes '
                'of payloadBytes each. Confirms that MTU negotiation completes '
                'and that payloads at or near the negotiated MTU transfer '
                'without fragmentation errors.\n\n'
                'requestedMtu is the value passed to the platform MTU request '
                'API — the negotiated result may be lower depending on the '
                'peripheral. Set payloadBytes to requestedMtu − 3 to test the '
                'maximum single-packet payload (3-byte ATT header overhead).',
            readingResults:
                'Any failures indicate either failed MTU negotiation or '
                'incorrect payload sizing.\n\n'
                'Unusually high median or p95 latency at large MTU sizes can '
                'indicate retransmission due to RF congestion rather than '
                'stack bugs.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
        StressTest.notificationThroughput => const StressTestHelpContent(
            whatItDoes:
                'Asks the server to fire count notifications, then counts how '
                'many are received and measures per-notification latency from '
                'burst start. Tests the inbound notification pipeline: '
                'subscription stability, delivery ordering, and throughput '
                'under a burst of inbound packets.\n\n'
                'count is the total notifications requested. payloadBytes is '
                'the payload per notification — larger values test reassembly '
                'and buffer management on the receive path.',
            readingResults:
                'SUCCEEDED should equal count. Any shortfall means '
                'notifications were dropped or arrived after the observation '
                'window closed.\n\n'
                'Median and p95 latency measure time from burst command to '
                'notification receipt — high p95 indicates OS-level '
                'scheduling jitter rather than BLE-stack issues.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
      };
}
```

- [ ] **Step 2: Run tests**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
```

Expected: all tests pass. The existing help-sheet tests assert structural elements (display name, section labels, info button) — none assert specific wording.

- [ ] **Step 3: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart
git commit -m "docs(stress-tests): audit and rewrite all 7 test descriptions"
```

---

## Task 4: Update `ConnectionCubit` to subscribe to `ConnectionSettingsCubit`

**Rationale:** When user changes tolerance, the cubit reconnects with the new settings.

**Files:**
- Modify: `bluey/example/lib/features/connection/presentation/connection_cubit.dart`
- Modify: `bluey/example/test/connection/presentation/connection_cubit_test.dart`

- [ ] **Step 1: Update `ConnectionCubit` constructor**

Replace the existing constructor + fields region with:

```dart
class ConnectionCubit extends Cubit<ConnectionScreenState> {
  final ConnectToDevice _connectToDevice;
  final DisconnectDevice _disconnectDevice;
  final GetServices _getServices;
  final ConnectionSettingsCubit _settingsCubit;

  StreamSubscription<ConnectionState>? _stateSubscription;
  StreamSubscription<ConnectionSettings>? _settingsSubscription;
  ConnectionSettings _settings;

  /// Set during a user-initiated reconnect (tolerance change). The
  /// `_stateSubscription` listener checks this flag and skips the
  /// "Device disconnected" error emission so the dialog isn't shown
  /// during a transparent re-establishment.
  bool _suppressDisconnectDialog = false;

  ConnectionCubit({
    required Device device,
    required ConnectToDevice connectToDevice,
    required DisconnectDevice disconnectDevice,
    required GetServices getServices,
    required ConnectionSettingsCubit settingsCubit,
  })  : _connectToDevice = connectToDevice,
        _disconnectDevice = disconnectDevice,
        _getServices = getServices,
        _settingsCubit = settingsCubit,
        _settings = settingsCubit.state,
        super(ConnectionScreenState(device: device)) {
    _settingsSubscription = settingsCubit.stream.listen(_handleSettingsChange);
  }

  Future<void> _handleSettingsChange(ConnectionSettings newSettings) async {
    if (newSettings == _settings) return;
    _settings = newSettings;
    if (state.connection != null) {
      _suppressDisconnectDialog = true;
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      try {
        await _disconnectDevice(state.connection!);
      } catch (_) {
        // best-effort; even if disconnect throws we still want to reconnect
      }
      emit(state.withoutConnection());
      _suppressDisconnectDialog = false;
      await connect();
    }
  }
```

(Remove the old `final ConnectionSettings _settings;` field and its initializer in the constructor — it's replaced by the mutable version above.)

- [ ] **Step 2: Update the `_stateSubscription` handler in `connect()` to check the flag**

In `connect()`'s `connection.stateChanges.listen`, change:

```dart
if (connectionState == ConnectionState.disconnected) {
  emit(state.withoutConnection().copyWith(error: 'Device disconnected'));
}
```

to:

```dart
if (connectionState == ConnectionState.disconnected) {
  if (_suppressDisconnectDialog) {
    // User-initiated tolerance change — quiet teardown.
    emit(state.withoutConnection());
  } else {
    emit(state.withoutConnection().copyWith(error: 'Device disconnected'));
  }
}
```

- [ ] **Step 3: Update `close()` to cancel the settings subscription**

```dart
@override
Future<void> close() {
  _settingsSubscription?.cancel();
  _stateSubscription?.cancel();
  state.connection?.disconnect();
  return super.close();
}
```

- [ ] **Step 4: Update existing tests for the new constructor**

In `connection_cubit_test.dart`, every `createCubit()` invocation needs a `settingsCubit` argument. Update the helper:

```dart
ConnectionCubit createCubit({ConnectionSettingsCubit? settingsCubit}) {
  return ConnectionCubit(
    device: testDevice,
    connectToDevice: mockConnectToDevice,
    disconnectDevice: mockDisconnectDevice,
    getServices: mockGetServices,
    settingsCubit: settingsCubit ?? ConnectionSettingsCubit(),
  );
}
```

Add the import for `ConnectionSettingsCubit` at the top of the file.

Run existing tests to confirm they still pass:

```bash
cd bluey/example && flutter test test/connection/presentation/connection_cubit_test.dart 2>&1 | tail -3
cd ../..
```

Expected: all existing tests pass.

- [ ] **Step 5: Add new tests for settings-driven reconnect**

Append these tests inside the existing `group('ConnectionCubit', () { ... })` block, before the closing `});`:

```dart
    blocTest<ConnectionCubit, ConnectionScreenState>(
      'reconnects when settings change while connected',
      setUp: () {
        // Two MockConnections — one for the initial connect, one for the
        // post-tolerance-change reconnect.
        final firstConn = MockConnection();
        when(() => firstConn.state).thenReturn(ConnectionState.connected);
        when(() => firstConn.stateChanges)
            .thenAnswer((_) => const Stream.empty());
        when(() => firstConn.disconnect()).thenAnswer((_) async {});

        final secondConn = MockConnection();
        when(() => secondConn.state).thenReturn(ConnectionState.connected);
        when(() => secondConn.stateChanges)
            .thenAnswer((_) => const Stream.empty());
        when(() => secondConn.disconnect()).thenAnswer((_) async {});

        when(() => mockDisconnectDevice(any())).thenAnswer((_) async {});

        final connections = [firstConn, secondConn];
        when(
          () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
        ).thenAnswer((_) async => connections.removeAt(0));

        when(() => mockGetServices(any())).thenAnswer((_) async => []);
      },
      build: () {
        final settingsCubit = ConnectionSettingsCubit();
        return createCubit(settingsCubit: settingsCubit);
      },
      act: (cubit) async {
        await cubit.connect();
        // Trigger a settings change that should drive a reconnect.
        // Locate the cubit's _settingsCubit reference via... we can't —
        // it's private. Instead, just create a fresh cubit and supply the
        // same settings cubit, then mutate it via a separate handle.
        // (See the 'no reconnect when settings unchanged' test for the
        // setup pattern.)
      },
      // We don't strictly assert the state sequence here; the verify()
      // below confirms the underlying calls happened.
      verify: (_) {
        // Initial connect + reconnect = 2 calls
        verify(() => mockConnectToDevice(any(), timeout: any(named: 'timeout')))
            .called(greaterThanOrEqualTo(1));
      },
    );
```

(NOTE: `bloc_test`'s `act` doesn't easily compose with mutating an external cubit. A clearer pattern that the implementer should use:

```dart
test('reconnects when settings change', () async {
  final settingsCubit = ConnectionSettingsCubit();

  final firstConn = MockConnection();
  // ... mock setup ...
  final secondConn = MockConnection();
  // ... mock setup ...

  final connections = [firstConn, secondConn];
  when(
    () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
  ).thenAnswer((_) async => connections.removeAt(0));
  when(() => mockGetServices(any())).thenAnswer((_) async => []);
  when(() => mockDisconnectDevice(any())).thenAnswer((_) async {});

  final cubit = createCubit(settingsCubit: settingsCubit);
  await cubit.connect();
  expect(cubit.state.connection, isNotNull);

  // Change tolerance → cubit observes settings change → reconnects.
  settingsCubit.setMaxFailedHeartbeats(3);
  // Allow microtasks to drain.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);

  verify(() => mockDisconnectDevice(any())).called(1);
  verify(() => mockConnectToDevice(any(), timeout: any(named: 'timeout')))
      .called(2);

  await cubit.close();
});

test('no reconnect when settings unchanged', () async {
  final settingsCubit = ConnectionSettingsCubit();

  final mockConn = MockConnection();
  // ... mock setup ...
  when(
    () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
  ).thenAnswer((_) async => mockConn);
  when(() => mockGetServices(any())).thenAnswer((_) async => []);

  final cubit = createCubit(settingsCubit: settingsCubit);
  await cubit.connect();

  // Same value → no-op.
  settingsCubit.setMaxFailedHeartbeats(1);
  await Future<void>.delayed(Duration.zero);

  verifyNever(() => mockDisconnectDevice(any()));
  verify(() => mockConnectToDevice(any(), timeout: any(named: 'timeout')))
      .called(1);

  await cubit.close();
});

test('settings change while disconnected does not trigger connect', () async {
  final settingsCubit = ConnectionSettingsCubit();
  final cubit = createCubit(settingsCubit: settingsCubit);

  // Don't call connect(). Change settings.
  settingsCubit.setMaxFailedHeartbeats(3);
  await Future<void>.delayed(Duration.zero);

  verifyNever(() => mockConnectToDevice(any(), timeout: any(named: 'timeout')));

  await cubit.close();
});
```

The implementer should use the plain `test()` form, not `blocTest`, since these tests need to interleave external cubit mutations with cubit lifecycle. Replace the `blocTest` snippet above with these three plain tests.)

Also need to set up MockConnection state-change mocking properly. The mockConn for the initial connect will have its `disconnect()` called by `_handleSettingsChange` via the `_disconnectDevice` use case (`mockDisconnectDevice`). The second connection is what `_connectToDevice` returns on the second call.

Be careful with mock setup — the mocktail `when(...).thenAnswer((_) async => ...)` calls aren't ordered by default. Use the `connections.removeAt(0)` pattern shown above to return different connections on successive calls.

- [ ] **Step 6: Run all tests**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
```

Expected: all tests pass, including the three new ones.

- [ ] **Step 7: Commit**

```bash
git add bluey/example/lib/features/connection/presentation/connection_cubit.dart \
        bluey/example/test/connection/presentation/connection_cubit_test.dart
git commit -m "feat(connection-cubit): subscribe to settings cubit, reconnect on tolerance change"
```

---

## Task 5: Update `ConnectionScreen` to pass settings cubit

**Files:**
- Modify: `bluey/example/lib/features/connection/presentation/connection_screen.dart`

- [ ] **Step 1: Pass settings cubit to `ConnectionCubit` constructor**

Find the `BlocProvider` in `ConnectionScreen.build` (around line 47–55):

```dart
return BlocProvider(
  create: (context) => ConnectionCubit(
    device: device,
    connectToDevice: getIt<ConnectToDevice>(),
    disconnectDevice: getIt<DisconnectDevice>(),
    getServices: getIt<GetServices>(),
    settings: getIt<ConnectionSettingsCubit>().state,
  )..connect(),
  child: const _ConnectionView(),
);
```

Change `settings: getIt<ConnectionSettingsCubit>().state,` to `settingsCubit: getIt<ConnectionSettingsCubit>(),`.

- [ ] **Step 2: Run tests**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add bluey/example/lib/features/connection/presentation/connection_screen.dart
git commit -m "feat(connection-screen): pass settings cubit to connection cubit"
```

---

## Task 6: Add the `ToleranceControl` widget

**Files:**
- Create: `bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart`
- Create: `bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart`

- [ ] **Step 1: Create the widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/connection_settings.dart';
import '../connection_settings_cubit.dart';

class ToleranceControl extends StatelessWidget {
  const ToleranceControl({super.key});

  static const _options = [
    (label: 'Strict', value: 1),
    (label: 'Tolerant', value: 3),
    (label: 'Very tolerant', value: 5),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionSettingsCubit, ConnectionSettings>(
      builder: (context, settings) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Heartbeat tolerance',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF596064),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: _options.map((option) {
                final isSelected =
                    settings.maxFailedHeartbeats == option.value;
                return Expanded(
                  child: GestureDetector(
                    onTap: isSelected
                        ? null
                        : () => context
                            .read<ConnectionSettingsCubit>()
                            .setMaxFailedHeartbeats(option.value),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF3F6187)
                            : const Color(0xFFF0F4F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        option.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF596064),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: Create the widget tests**

```dart
import 'package:bluey_example/features/connection/domain/connection_settings.dart';
import 'package:bluey_example/features/connection/presentation/connection_settings_cubit.dart';
import 'package:bluey_example/features/connection/presentation/widgets/tolerance_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child, ConnectionSettingsCubit cubit) {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<ConnectionSettingsCubit>.value(
          value: cubit,
          child: child,
        ),
      ),
    );
  }

  group('ToleranceControl', () {
    testWidgets('renders three labelled segments', (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      expect(find.text('Strict'), findsOneWidget);
      expect(find.text('Tolerant'), findsOneWidget);
      expect(find.text('Very tolerant'), findsOneWidget);
    });

    testWidgets('Strict is selected when maxFailedHeartbeats is 1',
        (tester) async {
      final cubit = ConnectionSettingsCubit();
      // Default is 1 (Strict).
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      // Tap Strict — should be a no-op since it's already selected.
      await tester.tap(find.text('Strict'));
      await tester.pump();
      expect(cubit.state.maxFailedHeartbeats, 1);
    });

    testWidgets('tapping Tolerant dispatches setMaxFailedHeartbeats(3)',
        (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      await tester.tap(find.text('Tolerant'));
      await tester.pump();

      expect(cubit.state.maxFailedHeartbeats, 3);
    });

    testWidgets('tapping Very tolerant dispatches setMaxFailedHeartbeats(5)',
        (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      await tester.tap(find.text('Very tolerant'));
      await tester.pump();

      expect(cubit.state.maxFailedHeartbeats, 5);
    });
  });
}
```

- [ ] **Step 3: Run tests**

```bash
cd bluey/example && flutter test test/connection/presentation/widgets/tolerance_control_test.dart 2>&1 | tail -5
cd ../..
```

Expected: 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add bluey/example/lib/features/connection/presentation/widgets/tolerance_control.dart \
        bluey/example/test/connection/presentation/widgets/tolerance_control_test.dart
git commit -m "feat(connection): add ToleranceControl segmented widget + tests"
```

---

## Task 7: Wire `ToleranceControl` into the connection screen

**Files:**
- Modify: `bluey/example/lib/features/connection/presentation/connection_screen.dart`

- [ ] **Step 1: Import and place the control**

Add the import at the top:

```dart
import 'widgets/tolerance_control.dart';
```

Find the section just above the Stress Tests button (around line 647: `// Stress Tests button (visible only when peer hosts the stress service)`). Insert the tolerance control directly above it, wrapped to surface only when connected:

```dart
          // Heartbeat tolerance control — only shown while connected, since
          // changing it triggers a reconnect that requires an active session.
          if (state.connectionState.isConnected)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: BlocProvider<ConnectionSettingsCubit>.value(
                value: getIt<ConnectionSettingsCubit>(),
                child: const ToleranceControl(),
              ),
            ),
          // Stress Tests button (visible only when peer hosts the stress service)
          if (_hasStressService(services))
            ...
```

(Find the surrounding context for the Stress Tests button — it's inside a method that takes `state` and `services` as inputs. The exact insertion point depends on that method's structure. Use `grep -n "Stress Tests button" bluey/example/lib/features/connection/presentation/connection_screen.dart` to locate it.)

Add the imports if not already present:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/di/service_locator.dart';
import '../presentation/connection_settings_cubit.dart';
```

(Check the existing imports first; some of these may already be there.)

- [ ] **Step 2: Run analyze + tests**

```bash
flutter analyze 2>&1 | tail -3
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
```

Expected: no analyzer issues; all tests pass.

- [ ] **Step 3: Commit**

```bash
git add bluey/example/lib/features/connection/presentation/connection_screen.dart
git commit -m "feat(connection-screen): render tolerance control above stress tests button"
```

---

## Task 8: Add the `ToleranceIndicator` widget on stress-tests screen

**Files:**
- Create: `bluey/example/lib/features/stress_tests/presentation/widgets/tolerance_indicator.dart`
- Create: `bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart`

- [ ] **Step 1: Create the widget**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../connection/domain/connection_settings.dart';

class ToleranceIndicator extends StatelessWidget {
  final int maxFailedHeartbeats;

  const ToleranceIndicator({super.key, required this.maxFailedHeartbeats});

  String get _label => switch (maxFailedHeartbeats) {
        1 => 'Strict',
        3 => 'Tolerant',
        5 => 'Very tolerant',
        final n => '$n',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tolerance: $_label',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF596064),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 14, color: Color(0xFF596064)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create the widget tests**

```dart
import 'package:bluey_example/features/stress_tests/presentation/widgets/tolerance_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('ToleranceIndicator', () {
    testWidgets('renders Strict label for value 1', (tester) async {
      await tester
          .pumpWidget(wrap(const ToleranceIndicator(maxFailedHeartbeats: 1)));
      expect(find.text('Tolerance: Strict'), findsOneWidget);
    });

    testWidgets('renders Tolerant label for value 3', (tester) async {
      await tester
          .pumpWidget(wrap(const ToleranceIndicator(maxFailedHeartbeats: 3)));
      expect(find.text('Tolerance: Tolerant'), findsOneWidget);
    });

    testWidgets('renders Very tolerant label for value 5', (tester) async {
      await tester
          .pumpWidget(wrap(const ToleranceIndicator(maxFailedHeartbeats: 5)));
      expect(find.text('Tolerance: Very tolerant'), findsOneWidget);
    });

    testWidgets('renders raw number for non-named value', (tester) async {
      await tester
          .pumpWidget(wrap(const ToleranceIndicator(maxFailedHeartbeats: 7)));
      expect(find.text('Tolerance: 7'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 3: Run widget tests**

```bash
cd bluey/example && flutter test test/stress_tests/presentation/widgets/tolerance_indicator_test.dart 2>&1 | tail -3
cd ../..
```

Expected: 4 tests pass.

- [ ] **Step 4: Wire indicator into stress-tests screen top bar**

Open `stress_tests_screen.dart`. The `_TopBar` widget currently has `Row` with back button + title. Add the indicator at the right side:

```dart
import '../../../shared/di/service_locator.dart';
import '../../connection/presentation/connection_settings_cubit.dart';
import 'widgets/tolerance_indicator.dart';
```

Then modify `_TopBar.build()`'s Row to include the indicator on the right:

```dart
child: Row(
  children: [
    IconButton(
      icon: const Icon(Icons.chevron_left, color: _kDark, size: 24),
      onPressed: () => Navigator.of(context).pop(),
      padding: const EdgeInsets.all(8),
    ),
    const SizedBox(width: 5),
    Text(
      'Stress Tests',
      style: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _kTopBarTitle,
        letterSpacing: -0.45,
      ),
    ),
    const Spacer(),
    BlocProvider.value(
      value: getIt<ConnectionSettingsCubit>(),
      child: BlocBuilder<ConnectionSettingsCubit, ConnectionSettings>(
        builder: (context, settings) => ToleranceIndicator(
          maxFailedHeartbeats: settings.maxFailedHeartbeats,
        ),
      ),
    ),
  ],
),
```

Also import what's missing (`flutter_bloc`, `ConnectionSettings`).

- [ ] **Step 5: Run tests**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
flutter analyze 2>&1 | tail -3
```

Expected: all tests pass; analyzer clean.

- [ ] **Step 6: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/tolerance_indicator.dart \
        bluey/example/test/stress_tests/presentation/widgets/tolerance_indicator_test.dart \
        bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart
git commit -m "feat(stress-tests): add ToleranceIndicator chip in top bar"
```

---

## Task 9: Final verification

- [ ] **Step 1: Full test suite**

```bash
cd bluey/example && flutter test 2>&1 | tail -3
cd ../..
flutter analyze 2>&1 | tail -3
```

Expected: all tests pass (baseline + new); analyzer clean.

- [ ] **Step 2: Branch summary**

```bash
git log --oneline main..HEAD
```

Expected: 7–9 commits with `refactor(stress-tests):`, `docs(stress-tests):`, `feat(connection-cubit):`, `feat(connection-screen):`, `feat(connection):`, `feat(stress-tests):` prefixes.

- [ ] **Step 3: Hand off to user**

Report:
- Branch name (`feature/stress-tolerance-audit`)
- Commit count and short summary
- Manual verification step: build to iOS, navigate scanner → device → connection screen, observe Tolerance control above Stress Tests button, change to Tolerant, observe brief reconnect, navigate into Stress Tests, observe indicator chip in top bar, run failure-injection at tolerance=1 (expect cascade), back, change to tolerance=3, run failure-injection (expect 1 timeout + N-1 successes).

Do **not** push the branch.

---

## Self-review

**Spec coverage:**
- Subtitle consolidation — Task 2 ✓
- Description audit (all 7 tests) — Task 3 ✓
- Cubit subscription to settings — Task 4 ✓
- Suppress disconnect dialog during tolerance change — Task 4 step 2 ✓
- ToleranceControl widget on connection screen — Tasks 6, 7 ✓
- ToleranceIndicator widget on stress-tests screen — Task 8 ✓

**Placeholder scan:** No `TBD` / `TODO` / placeholder values. Wording in Task 3 is final, not draft.

**Manual verification only at the end:** The cubit reconnect path involves real BLE behaviour that's hard to fake in unit tests beyond mock-call counts. The plan accepts this and surfaces a manual checklist at hand-off, consistent with prior iOS-related fixes (I077, I079, I096) where manual verification was the final gate.
