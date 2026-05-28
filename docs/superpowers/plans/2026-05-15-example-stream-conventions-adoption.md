# Example app: stream-conventions adoption — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `bluey/example/` to leverage and demonstrate the affordances introduced in PR #32 — replay-on-subscribe, scan/advertising state machines, lifecycle events, cancel-stops-platform-scan, and adapter-cycle invalidation handling.

**Architecture:** Three groups of changes — (1) new shared widgets and a recovery flow built around a `ValueNotifier` tick that triggers screen rebuilds, (2) per-feature cubit/state-model migration from boolean lifecycle flags to the new state enums, and (3) `bluey.events` ingestion into existing per-feature log panels. Cubits stay widget-tree-scoped; the recovery flow rebuilds the `BlocProvider` rather than mutating live cubits.

**Tech Stack:** Flutter, flutter_bloc, GetIt, mocktail, bloc_test.

**Spec reference:** `docs/superpowers/specs/2026-05-15-example-stream-conventions-adoption-design.md`

---

## File map

**New files:**
- `bluey/example/lib/shared/domain/recovery_notifier.dart` — `ValueNotifier<int>` for recovery ticks.
- `bluey/example/lib/shared/presentation/invalidation_banner.dart` — material banner with recover action.
- `bluey/example/lib/shared/presentation/adapter_cycle_hint.dart` — quiet footer hint.
- `bluey/example/test/shared/presentation/invalidation_banner_test.dart`
- `bluey/example/test/shared/presentation/adapter_cycle_hint_test.dart`
- `bluey/example/test/shared/presentation/advertising_state_chip_test.dart`
- `bluey/example/test/shared/di/service_locator_recreate_test.dart`

**Modified files:**
- `bluey/example/lib/shared/di/service_locator.dart` — add `recreateBluey()`, register `RecoveryNotifier`.
- `bluey/example/lib/shared/presentation/bluetooth_state_chip.dart` — `AdvertisingStateChip` enum migration.
- `bluey/example/lib/features/scanner/infrastructure/bluey_scanner_repository.dart` — drop `_scanner` stash + explicit stop.
- `bluey/example/lib/features/scanner/domain/scanner_repository.dart` — drop `stopScan()` from the interface.
- `bluey/example/lib/features/scanner/application/stop_scan.dart` — **deleted**.
- `bluey/example/lib/features/scanner/di/scanner_module.dart` — drop StopScan registration.
- `bluey/example/lib/features/scanner/presentation/scanner_state.dart` — replace `isScanning` with `scanState`; add `scanLog`.
- `bluey/example/lib/features/scanner/presentation/scanner_cubit.dart` — subscribe to `stateChanges` + `bluey.events`; drop manual seed + StopScan injection.
- `bluey/example/lib/features/scanner/presentation/scanner_screen.dart` — banner + hint + scan log panel + recovery wrapper.
- `bluey/example/lib/features/server/presentation/server_state.dart` — replace `isAdvertising` with `advertisingState`; add `ServerLogEntry.fromBlueyEvent`.
- `bluey/example/lib/features/server/presentation/server_cubit.dart` — subscribe to `advertisingStateChanges` + `bluey.events`.
- `bluey/example/lib/features/server/presentation/server_screen.dart` — banner + hint + recovery wrapper.
- `bluey/example/lib/features/connection/presentation/connection_cubit.dart` — drop redundant reads; catch StaleHandle.
- `bluey/example/lib/features/connection/presentation/connection_screen.dart` — banner + hint + recovery wrapper.
- `bluey/example/lib/features/service_explorer/presentation/service_cubit.dart` — subscribe to `servicesChanges`; catch StaleHandle.
- `bluey/example/lib/features/service_explorer/presentation/service_screen.dart` — recovery wrapper.
- `bluey/example/test/mocks/mock_use_cases.dart` — adjust mocks for new cubit signatures.
- `bluey/example/test/scanner/presentation/scanner_cubit_test.dart` — migrate to new state model.
- `bluey/example/test/server/presentation/server_cubit_test.dart` — migrate to new state model.
- `bluey/example/test/connection/presentation/connection_cubit_test.dart` — invalidation + replay tests.

**Deleted files:**
- `bluey/example/lib/features/scanner/application/stop_scan.dart`
- `bluey/example/test/scanner/application/stop_scan_test.dart`

---

## Task 1: `RecoveryNotifier`

**Files:**
- Create: `bluey/example/lib/shared/domain/recovery_notifier.dart`
- Create: `bluey/example/test/shared/domain/recovery_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// bluey/example/test/shared/domain/recovery_notifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_example/shared/domain/recovery_notifier.dart';

void main() {
  group('RecoveryNotifier', () {
    test('initial tick is zero', () {
      final notifier = RecoveryNotifier();
      expect(notifier.value, equals(0));
    });

    test('notify() increments tick', () {
      final notifier = RecoveryNotifier();
      notifier.notify();
      notifier.notify();
      expect(notifier.value, equals(2));
    });

    test('listeners fire on notify', () {
      final notifier = RecoveryNotifier();
      var fired = 0;
      notifier.addListener(() => fired++);
      notifier.notify();
      notifier.notify();
      expect(fired, equals(2));
    });
  });
}
```

- [ ] **Step 2: Verify red**

Run: `cd bluey/example && flutter test test/shared/domain/recovery_notifier_test.dart`
Expected: build failure (file does not exist).

- [ ] **Step 3: Implement**

```dart
// bluey/example/lib/shared/domain/recovery_notifier.dart
import 'package:flutter/foundation.dart';

/// Broadcasts a tick whenever the shared [Bluey] instance is recreated.
/// Screens listen and rebuild their [BlocProvider] keyed off the tick
/// so their cubits are reconstructed with fresh use cases.
class RecoveryNotifier extends ValueNotifier<int> {
  RecoveryNotifier() : super(0);

  void notify() {
    value = value + 1;
  }
}
```

- [ ] **Step 4: Verify green**

Run: `cd bluey/example && flutter test test/shared/domain/recovery_notifier_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/domain/recovery_notifier.dart bluey/example/test/shared/domain/recovery_notifier_test.dart
git commit -m "example: add RecoveryNotifier (ValueNotifier tick)"
```

---

## Task 2: `ServiceLocator.recreateBluey()`

**Files:**
- Modify: `bluey/example/lib/shared/di/service_locator.dart`
- Create: `bluey/example/test/shared/di/service_locator_recreate_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// bluey/example/test/shared/di/service_locator_recreate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:bluey_example/shared/di/service_locator.dart';
import 'package:bluey_example/shared/domain/recovery_notifier.dart';

import '../../fakes/fake_bluey_platform_for_example.dart';

void main() {
  late FakeBlueyPlatformForExample fakePlatform;

  setUp(() async {
    fakePlatform = FakeBlueyPlatformForExample();
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    final identity = ServerId.generate();
    await setupServiceLocator(localIdentity: identity);
  });

  tearDown(() async {
    await resetServiceLocator();
  });

  test('recreateBluey swaps the singleton', () async {
    final before = getIt<Bluey>();
    await recreateBluey();
    final after = getIt<Bluey>();
    expect(identical(before, after), isFalse);
  });

  test('recreateBluey ticks the RecoveryNotifier', () async {
    final notifier = getIt<RecoveryNotifier>();
    final initial = notifier.value;
    await recreateBluey();
    expect(notifier.value, equals(initial + 1));
  });

  test('recreateBluey preserves the localIdentity', () async {
    final identityBefore = getIt<Bluey>().localIdentity;
    await recreateBluey();
    final identityAfter = getIt<Bluey>().localIdentity;
    expect(identityAfter, equals(identityBefore));
  });
}
```

(Note: a minimal `FakeBlueyPlatformForExample` may already exist under `bluey/example/test/fakes/` or `bluey/example/test/mocks/`. If not, create one that returns a `Capabilities` value and an empty `Stream<BluetoothState>`. Keep it minimal — the test only needs `BlueyPlatform.instance` to resolve so `Bluey.create()` returns.)

- [ ] **Step 2: Verify red**

Run: `cd bluey/example && flutter test test/shared/di/service_locator_recreate_test.dart`
Expected: failures around `getIt<RecoveryNotifier>()` not registered and `recreateBluey` not defined.

- [ ] **Step 3: Implement**

Modify `bluey/example/lib/shared/di/service_locator.dart`:

- Register `RecoveryNotifier` as a singleton inside `setupServiceLocator`.
- Stash `localIdentity` in a top-level `late ServerId? _capturedIdentity` so `recreateBluey()` can re-pass it.
- Add `Future<void> recreateBluey()` that:
  1. Asserts `_capturedIdentity != null` (must have been set up first).
  2. Saves a reference to the existing `RecoveryNotifier` (it stays alive across the reset; we re-register the same instance).
  3. Disposes the existing Bluey: `await getIt<Bluey>().dispose();`
  4. Calls `await getIt.reset();`
  5. Re-runs the same registration flow: register the preserved `RecoveryNotifier`, build a fresh `Bluey`, register feature modules.
  6. Calls `recoveryNotifier.notify()`.

- [ ] **Step 4: Verify green**

Run: `cd bluey/example && flutter test test/shared/di/service_locator_recreate_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/di/service_locator.dart bluey/example/test/shared/di/service_locator_recreate_test.dart bluey/example/test/fakes/
git commit -m "example: add ServiceLocator.recreateBluey()"
```

---

## Task 3: `InvalidationBanner` widget

**Files:**
- Create: `bluey/example/lib/shared/presentation/invalidation_banner.dart`
- Create: `bluey/example/test/shared/presentation/invalidation_banner_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// bluey/example/test/shared/presentation/invalidation_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_example/shared/presentation/invalidation_banner.dart';

void main() {
  testWidgets('renders label and action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvalidationBanner(onRecover: () {}),
      ),
    ));

    expect(find.text('Bluetooth was cycled. Tap to recover.'), findsOneWidget);
    expect(find.text('Recover'), findsOneWidget);
  });

  testWidgets('calls onRecover when action tapped', (tester) async {
    var called = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvalidationBanner(onRecover: () => called++),
      ),
    ));

    await tester.tap(find.text('Recover'));
    expect(called, equals(1));
  });

  testWidgets('honours custom label and action label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvalidationBanner(
          label: 'Custom label',
          actionLabel: 'Retry',
          onRecover: () {},
        ),
      ),
    ));

    expect(find.text('Custom label'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Verify red**

Run: `cd bluey/example && flutter test test/shared/presentation/invalidation_banner_test.dart`
Expected: build failure.

- [ ] **Step 3: Implement**

```dart
// bluey/example/lib/shared/presentation/invalidation_banner.dart
import 'package:flutter/material.dart';

/// Inline banner shown on a feature screen when its underlying
/// bluey-derived instance has been invalidated (adapter cycle, etc.).
/// Tapping the action triggers the centralized recovery flow.
class InvalidationBanner extends StatelessWidget {
  final String label;
  final String actionLabel;
  final VoidCallback onRecover;

  const InvalidationBanner({
    super.key,
    this.label = 'Bluetooth was cycled. Tap to recover.',
    this.actionLabel = 'Recover',
    required this.onRecover,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(label),
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      actions: [
        TextButton(onPressed: onRecover, child: Text(actionLabel)),
      ],
    );
  }
}
```

- [ ] **Step 4: Verify green**

Run: `cd bluey/example && flutter test test/shared/presentation/invalidation_banner_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/presentation/invalidation_banner.dart bluey/example/test/shared/presentation/invalidation_banner_test.dart
git commit -m "example: add InvalidationBanner widget"
```

---

## Task 4: `AdapterCycleHint` widget

**Files:**
- Create: `bluey/example/lib/shared/presentation/adapter_cycle_hint.dart`
- Create: `bluey/example/test/shared/presentation/adapter_cycle_hint_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// bluey/example/test/shared/presentation/adapter_cycle_hint_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_example/shared/presentation/adapter_cycle_hint.dart';

void main() {
  testWidgets('renders the hint text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdapterCycleHint()),
    ));

    expect(
      find.textContaining('toggle Bluetooth in system settings'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Verify red**

Run: `cd bluey/example && flutter test test/shared/presentation/adapter_cycle_hint_test.dart`
Expected: build failure.

- [ ] **Step 3: Implement**

```dart
// bluey/example/lib/shared/presentation/adapter_cycle_hint.dart
import 'package:flutter/material.dart';

/// Quiet, always-visible footer text on lifecycle-sensitive screens.
/// Tells the user how to exercise the recovery flow without requiring
/// a debug-only API in the bluey library.
class AdapterCycleHint extends StatelessWidget {
  const AdapterCycleHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Tip: toggle Bluetooth in system settings to see recovery in action.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).hintColor,
            ),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify green**

Run: `cd bluey/example && flutter test test/shared/presentation/adapter_cycle_hint_test.dart`
Expected: 1/1 pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/presentation/adapter_cycle_hint.dart bluey/example/test/shared/presentation/adapter_cycle_hint_test.dart
git commit -m "example: add AdapterCycleHint widget"
```

---

## Task 5: `AdvertisingStateChip` enum migration

**Files:**
- Modify: `bluey/example/lib/shared/presentation/bluetooth_state_chip.dart`
- Create: `bluey/example/test/shared/presentation/advertising_state_chip_test.dart`
- Modify (call sites): `bluey/example/lib/features/server/presentation/server_screen.dart` (and any other usage — grep first)

- [ ] **Step 1: Find all call sites**

Run: `grep -rn "AdvertisingStateChip" bluey/example/lib/`
Record every match. Each will be updated in Step 6.

- [ ] **Step 2: Write the failing widget test**

```dart
// bluey/example/test/shared/presentation/advertising_state_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_example/shared/presentation/bluetooth_state_chip.dart';

void main() {
  Future<void> pumpChip(WidgetTester tester, AdvertisingState state) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdvertisingStateChip(advertisingState: state),
      ),
    ));
  }

  testWidgets('idle renders "Idle"', (tester) async {
    await pumpChip(tester, AdvertisingState.idle);
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('starting renders "Starting"', (tester) async {
    await pumpChip(tester, AdvertisingState.starting);
    expect(find.text('Starting'), findsOneWidget);
  });

  testWidgets('advertising renders "Advertising"', (tester) async {
    await pumpChip(tester, AdvertisingState.advertising);
    expect(find.text('Advertising'), findsOneWidget);
  });

  testWidgets('stopping renders "Stopping"', (tester) async {
    await pumpChip(tester, AdvertisingState.stopping);
    expect(find.text('Stopping'), findsOneWidget);
  });

  testWidgets('invalidated renders "Invalidated"', (tester) async {
    await pumpChip(tester, AdvertisingState.invalidated);
    expect(find.text('Invalidated'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Verify red**

Run: `cd bluey/example && flutter test test/shared/presentation/advertising_state_chip_test.dart`
Expected: build failure (param name doesn't match).

- [ ] **Step 4: Update the chip**

Modify `bluey/example/lib/shared/presentation/bluetooth_state_chip.dart`:

```dart
class AdvertisingStateChip extends StatelessWidget {
  final bluey.AdvertisingState advertisingState;

  const AdvertisingStateChip({super.key, required this.advertisingState});

  @override
  Widget build(BuildContext context) {
    final (color, avatar, label) = switch (advertisingState) {
      bluey.AdvertisingState.idle => (
        Colors.grey,
        const Icon(Icons.cell_tower_outlined, color: Colors.white, size: 16),
        'Idle',
      ),
      bluey.AdvertisingState.starting => (
        Colors.orange,
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        'Starting',
      ),
      bluey.AdvertisingState.advertising => (
        Colors.green,
        const Icon(Icons.cell_tower, color: Colors.white, size: 16),
        'Advertising',
      ),
      bluey.AdvertisingState.stopping => (
        Colors.orange,
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        'Stopping',
      ),
      bluey.AdvertisingState.invalidated => (
        Colors.red,
        const Icon(Icons.error_outline, color: Colors.white, size: 16),
        'Invalidated',
      ),
    };

    return Chip(
      avatar: avatar,
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
```

- [ ] **Step 5: Update each call site**

For each call site found in Step 1, change `isAdvertising: <bool>` to `advertisingState: <AdvertisingState>`. The Server cubit migration in Task 9 makes `advertisingState` available; for this task, since the cubit hasn't migrated yet, pass `state.isAdvertising ? AdvertisingState.advertising : AdvertisingState.idle` as a transitional bridge. This keeps the build green between Task 5 and Task 9.

- [ ] **Step 6: Verify green**

Run: `cd bluey/example && flutter test test/shared/presentation/advertising_state_chip_test.dart && flutter analyze`
Expected: 5/5 pass; analyzer clean.

- [ ] **Step 7: Commit**

```bash
git add bluey/example/lib/shared/presentation/bluetooth_state_chip.dart bluey/example/test/shared/presentation/advertising_state_chip_test.dart bluey/example/lib/features/server/presentation/server_screen.dart
git commit -m "example: AdvertisingStateChip takes AdvertisingState enum"
```

---

## Task 6: Strip Scanner repository workaround

**Files:**
- Modify: `bluey/example/lib/features/scanner/infrastructure/bluey_scanner_repository.dart`
- Modify: `bluey/example/lib/features/scanner/domain/scanner_repository.dart`
- Modify: `bluey/example/lib/features/scanner/di/scanner_module.dart`
- Delete: `bluey/example/lib/features/scanner/application/stop_scan.dart`
- Delete: `bluey/example/test/scanner/application/stop_scan_test.dart`

- [ ] **Step 1: Remove `stopScan()` from the domain interface**

Modify `bluey/example/lib/features/scanner/domain/scanner_repository.dart` to drop the `Future<void> stopScan()` member. The repository's `scan()` returns a stream; consumers stop by cancelling the subscription.

- [ ] **Step 2: Strip the implementation**

Modify `bluey/example/lib/features/scanner/infrastructure/bluey_scanner_repository.dart`:

```dart
import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';

/// Implementation of [ScannerRepository] using the Bluey library.
///
/// Note: `scan()` returns the platform-backed stream directly. Consumers
/// stop the radio by cancelling their subscription — the `Scanner.scan()`
/// stream is wired with `onCancel: () => stop()` in bluey since PR #32
/// (Convention 5 of the stream-conventions design). No explicit stop()
/// method is needed.
class BlueyScannerRepository implements ScannerRepository {
  final Bluey _bluey;

  BlueyScannerRepository(this._bluey);

  @override
  BluetoothState get currentState => _bluey.currentState;

  @override
  Stream<BluetoothState> get stateStream => _bluey.stateStream;

  @override
  Stream<ScanResult> scan({Duration? timeout}) {
    return _bluey.scanner().scan(timeout: timeout);
  }

  @override
  Future<bool> authorize() => _bluey.authorize();

  @override
  Future<bool> requestEnable() => _bluey.requestEnable();

  @override
  Future<void> openSettings() => _bluey.openSettings();
}
```

- [ ] **Step 3: Delete the use case**

```bash
rm bluey/example/lib/features/scanner/application/stop_scan.dart
rm bluey/example/test/scanner/application/stop_scan_test.dart
```

- [ ] **Step 4: Update DI registration**

Modify `bluey/example/lib/features/scanner/di/scanner_module.dart` — remove the `StopScan` import and registration.

- [ ] **Step 5: Update mocks**

Modify `bluey/example/test/mocks/mock_use_cases.dart` — remove `MockStopScan`. Any test that referenced it now fails the build; we will fix `scanner_cubit_test.dart` in Task 7 along with the cubit migration. For other test files, drop the reference.

- [ ] **Step 6: Verify build (cubit migration not yet done — expected failures contained)**

Run: `cd bluey/example && flutter analyze 2>&1 | head -40`
Expected: errors localized to `scanner_cubit.dart` and `scanner_cubit_test.dart` referencing the now-gone `StopScan`. These are fixed in the next task.

- [ ] **Step 7: Commit (intentional partial state — repository done, cubit pending)**

```bash
git add bluey/example/lib/features/scanner/infrastructure/bluey_scanner_repository.dart bluey/example/lib/features/scanner/domain/scanner_repository.dart bluey/example/lib/features/scanner/di/scanner_module.dart bluey/example/test/mocks/mock_use_cases.dart
git rm bluey/example/lib/features/scanner/application/stop_scan.dart bluey/example/test/scanner/application/stop_scan_test.dart
git commit -m "example: drop Scanner stop() workaround (cancel-stops-platform)"
```

---

## Task 7: Scanner cubit state migration (enum + replay + log)

**Files:**
- Modify: `bluey/example/lib/features/scanner/presentation/scanner_state.dart`
- Modify: `bluey/example/lib/features/scanner/presentation/scanner_cubit.dart`
- Modify: `bluey/example/test/scanner/presentation/scanner_cubit_test.dart`

- [ ] **Step 1: Write the failing cubit tests**

Replace the existing `scanner_cubit_test.dart` tests that referenced `StopScan` and `isScanning: bool`. Tests to add:

```dart
blocTest<ScannerCubit, ScannerState>(
  'initial state is stopped with empty log',
  build: createCubit,
  verify: (cubit) {
    expect(cubit.state.scanState, ScanState.stopped);
    expect(cubit.state.scanLog, isEmpty);
  },
);

blocTest<ScannerCubit, ScannerState>(
  'startScan transitions scanState: stopped → starting → scanning',
  setUp: () { /* arrange mock to emit scan results and a ScanState transition stream */ },
  build: createCubit,
  act: (cubit) => cubit.startScan(),
  expect: () => [
    isA<ScannerState>().having((s) => s.scanState, 'scanState', ScanState.starting),
    isA<ScannerState>().having((s) => s.scanState, 'scanState', ScanState.scanning),
  ],
);

blocTest<ScannerCubit, ScannerState>(
  'cancelling subscription transitions scanState to stopping then stopped',
  // ...
);

blocTest<ScannerCubit, ScannerState>(
  'adapter-state error leaves cubit in invalidated state',
  // Trigger ScanState.invalidated via the mocked stateChanges stream;
  // assert cubit emits an ScannerState with scanState=invalidated.
);

blocTest<ScannerCubit, ScannerState>(
  'ingests ScanStartingEvent into scanLog',
  // Mock the bluey.events stream to emit a ScanStartingEvent; assert log has the entry.
);
```

The cubit test setup will need to provide a fake or mock for `scanner.stateChanges` (a `Stream<ScanState>`) and `bluey.events` (a `Stream<BlueyEvent>`). Extend `mock_use_cases.dart` and/or `mock_bluey.dart` with `MockScanner` / `MockBlueyEvents` as needed.

- [ ] **Step 2: Verify red**

Run: `cd bluey/example && flutter test test/scanner/presentation/scanner_cubit_test.dart`
Expected: build failures (new fields/parameters not yet on cubit).

- [ ] **Step 3: Update `ScannerState`**

```dart
// bluey/example/lib/features/scanner/presentation/scanner_state.dart
import 'package:bluey/bluey.dart';

enum SortMode { signalStrength, name, deviceId }

class ScannerState {
  final BluetoothState bluetoothState;
  final List<ScanResult> scanResults;
  final ScanState scanState;
  final List<BlueyEvent> scanLog;
  final SortMode sortMode;
  final String? error;

  const ScannerState({
    this.bluetoothState = BluetoothState.unknown,
    this.scanResults = const [],
    this.scanState = ScanState.stopped,
    this.scanLog = const [],
    this.sortMode = SortMode.name,
    this.error,
  });

  bool get isScanning => scanState == ScanState.scanning;
  bool get isInvalidated => scanState == ScanState.invalidated;

  ScannerState copyWith({
    BluetoothState? bluetoothState,
    List<ScanResult>? scanResults,
    ScanState? scanState,
    List<BlueyEvent>? scanLog,
    SortMode? sortMode,
    String? error,
  }) {
    return ScannerState(
      bluetoothState: bluetoothState ?? this.bluetoothState,
      scanResults: scanResults ?? this.scanResults,
      scanState: scanState ?? this.scanState,
      scanLog: scanLog ?? this.scanLog,
      sortMode: sortMode ?? this.sortMode,
      error: error,
    );
  }

  // Note: the existing operator== / hashCode block stays in place,
  // updated to include scanState and scanLog (with list-equality for scanLog).
}
```

- [ ] **Step 4: Update `ScannerCubit`**

Modify `bluey/example/lib/features/scanner/presentation/scanner_cubit.dart`:

- Drop the `StopScan` use case from the constructor.
- Drop the manual `_getBluetoothState.current` read in `initialize()` — rely on the stateStream replay.
- Take an additional dependency on `Bluey` directly (via getIt at construction site) so the cubit can call `_bluey.scanner()` and subscribe to `_bluey.scanner().stateChanges` and `_bluey.events`. (The repository wraps `scan()` only; the cubit handles lifecycle wiring.)
- In `initialize()`, also subscribe to `_bluey.scanner().stateChanges` and emit `state.copyWith(scanState: ...)` on each tick. Cap `scanLog` at 100 entries.
- In `startScan()`, the scan subscription's `onDone` no longer needs to flip `isScanning` — the state stream will deliver that. Drop the manual flips.
- `stopScan()` simply cancels the scan subscription — `onCancel` in bluey stops the platform.

- [ ] **Step 5: Verify green**

Run: `cd bluey/example && flutter test test/scanner/presentation/scanner_cubit_test.dart && flutter analyze`
Expected: all new tests pass; analyzer clean across the scanner feature.

- [ ] **Step 6: Commit**

```bash
git add bluey/example/lib/features/scanner/presentation/ bluey/example/test/scanner/presentation/ bluey/example/test/mocks/
git commit -m "example: ScannerCubit consumes ScanState + bluey.events"
```

---

## Task 8: Scanner screen — scan log panel + banner + hint + recovery wrapper

**Files:**
- Modify: `bluey/example/lib/features/scanner/presentation/scanner_screen.dart`

- [ ] **Step 1: Add the scan log panel**

Below the existing scan results list, add a collapsible (or always-shown) "Scan events" section that displays the most recent `state.scanLog` entries with their `toString()` output and a relative timestamp. Use the existing `SectionHeader` widget for the title.

- [ ] **Step 2: Add the invalidation banner**

At the top of the screen body (above the scan results), conditionally render `InvalidationBanner` when `state.scanState == ScanState.invalidated`. The `onRecover` callback calls `getIt<RecoveryNotifier>` — no, calls `recreateBluey()` directly (it's a top-level function in `service_locator.dart`).

- [ ] **Step 3: Add the adapter-cycle hint**

At the bottom of the screen body, render `const AdapterCycleHint()`.

- [ ] **Step 4: Wrap the BlocProvider in a ValueListenableBuilder**

The scanner screen currently looks like:

```dart
@override
Widget build(BuildContext context) {
  return BlocProvider(
    create: (_) => ScannerCubit(...)..initialize(),
    child: Scaffold(...),
  );
}
```

Change to:

```dart
@override
Widget build(BuildContext context) {
  return ValueListenableBuilder<int>(
    valueListenable: getIt<RecoveryNotifier>(),
    builder: (context, tick, _) => BlocProvider(
      key: ValueKey('scanner-$tick'),
      create: (_) => ScannerCubit(...)..initialize(),
      child: Scaffold(...),
    ),
  );
}
```

The `ValueKey('scanner-$tick')` is what forces the BlocProvider to recreate its cubit when the tick changes.

- [ ] **Step 5: Manually verify and commit**

Run: `cd bluey/example && flutter test && flutter analyze`
Expected: all tests pass, analyzer clean.

```bash
git add bluey/example/lib/features/scanner/presentation/scanner_screen.dart
git commit -m "example: scanner screen wires invalidation banner + scan log + recovery"
```

---

## Task 9: Server cubit state migration + log ingestion

**Files:**
- Modify: `bluey/example/lib/features/server/presentation/server_state.dart`
- Modify: `bluey/example/lib/features/server/presentation/server_cubit.dart`
- Modify: `bluey/example/test/server/presentation/server_cubit_test.dart`

- [ ] **Step 1: Write the failing cubit tests**

```dart
blocTest<ServerCubit, ServerScreenState>(
  'initial advertisingState is idle',
  build: createCubit,
  verify: (cubit) => expect(cubit.state.advertisingState, AdvertisingState.idle),
);

blocTest<ServerCubit, ServerScreenState>(
  'startAdvertising transitions idle → starting → advertising',
  // arrange mock Server.advertisingStateChanges to emit those states
);

blocTest<ServerCubit, ServerScreenState>(
  'advertising lifecycle events land in log',
  // mock bluey.events with AdvertisingStartingEvent; assert ServerLogEntry created
  // via fromBlueyEvent appears in state.log
);

blocTest<ServerCubit, ServerScreenState>(
  'adapter invalidation surfaces in state',
  // mock advertisingStateChanges to emit AdvertisingState.invalidated;
  // assert state reflects invalidated.
);
```

- [ ] **Step 2: Verify red**

Run: `cd bluey/example && flutter test test/server/presentation/server_cubit_test.dart`
Expected: build failures.

- [ ] **Step 3: Update `ServerScreenState`**

Replace `bool isAdvertising` with `AdvertisingState advertisingState` (default `AdvertisingState.idle`). Add `bool get isAdvertising => advertisingState == AdvertisingState.advertising;` only if existing screen widgets need the derived value during the transition — once the screen is migrated to use the enum directly, drop the helper.

Add a factory to `ServerLogEntry`:

```dart
class ServerLogEntry {
  // ... existing fields ...
  ServerLogEntry(this.tag, this.message) : timestamp = DateTime.now();

  /// Create a log entry from a [BlueyEvent] for uniform display of
  /// library-emitted lifecycle events alongside the cubit's own messages.
  factory ServerLogEntry.fromBlueyEvent(BlueyEvent event) {
    return ServerLogEntry(event.runtimeType.toString(), event.toString());
  }
}
```

- [ ] **Step 4: Update `ServerCubit`**

- Inject `Bluey` so the cubit can subscribe to `server.advertisingStateChanges` and `_bluey.events`.
- Subscribe to `server.advertisingStateChanges` after `getServer()` returns; on each tick, emit `state.copyWith(advertisingState: ...)`.
- Subscribe to `_bluey.events`; filter to `AdvertisingStartingEvent` / `AdvertisingStartedEvent` / `AdvertisingStoppingEvent` / `AdvertisingStoppedEvent`; for each, prepend `ServerLogEntry.fromBlueyEvent(event)` to the log.
- Drop the manual `emit(state.copyWith(isAdvertising: true|false))` lines around `startAdvertising` / `stopAdvertising` — the state stream now drives those.

- [ ] **Step 5: Verify green**

Run: `cd bluey/example && flutter test test/server/presentation/server_cubit_test.dart && flutter analyze`
Expected: tests pass; analyzer clean.

- [ ] **Step 6: Commit**

```bash
git add bluey/example/lib/features/server/presentation/ bluey/example/test/server/presentation/
git commit -m "example: ServerCubit consumes AdvertisingState + bluey.events"
```

---

## Task 10: Server screen — banner + hint + recovery wrapper

**Files:**
- Modify: `bluey/example/lib/features/server/presentation/server_screen.dart`

- [ ] **Step 1: Apply the same banner/hint/recovery pattern as Task 8**

- Add `InvalidationBanner` at the top of the screen body, conditional on `state.advertisingState == AdvertisingState.invalidated`. (Alternative source for the invalidation signal: the cubit can also derive it from a `bool get isInvalidated`.)
- Add `const AdapterCycleHint()` at the bottom.
- Wrap the `BlocProvider` in `ValueListenableBuilder<int>` listening to `getIt<RecoveryNotifier>()`, using `ValueKey('server-$tick')`.

- [ ] **Step 2: Verify and commit**

Run: `cd bluey/example && flutter test && flutter analyze`
Expected: all green.

```bash
git add bluey/example/lib/features/server/presentation/server_screen.dart
git commit -m "example: server screen wires invalidation banner + recovery"
```

---

## Task 11: Connection cubit — drop redundant reads, catch StaleHandle

**Files:**
- Modify: `bluey/example/lib/features/connection/presentation/connection_cubit.dart`
- Modify: `bluey/example/test/connection/presentation/connection_cubit_test.dart`

- [ ] **Step 1: Write the failing test for replay behavior**

```dart
blocTest<ConnectionCubit, ConnectionScreenState>(
  'connect() uses stateChanges replay for initial state (no manual read)',
  // mock connection.stateChanges to first emit ConnectionState.ready (replay);
  // assert state.connectionState becomes ready without a separate connection.state read.
);
```

- [ ] **Step 2: Write the failing test for StaleHandleException handling**

```dart
blocTest<ConnectionCubit, ConnectionScreenState>(
  'StaleHandleException flips state to invalidated',
  // mock connection.stateChanges to emit ConnectionState.invalidated;
  // assert state reflects it. Also: mock a read() that throws
  // StaleHandleException; assert state goes invalidated too.
);
```

- [ ] **Step 3: Update the cubit**

- Remove `connectionState: connection.state` from the `emit` at line 136 — `stateChanges` replays the current value, so the first listener event sets it.
- Remove the explicit `await loadServices()` at line 172 — `servicesChanges` replays as well.
- In `onError` of the `_stateSubscription`, check `if (error is StaleHandleException)` and flip to a dedicated invalidated state instead of the generic "Connection state error" message.
- Optionally add a `bool get isInvalidated => connectionState == ConnectionState.invalidated;` helper on `ConnectionScreenState` for cleaner screen code.

- [ ] **Step 4: Verify green**

Run: `cd bluey/example && flutter test test/connection/presentation/connection_cubit_test.dart && flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/connection/presentation/connection_cubit.dart bluey/example/test/connection/presentation/connection_cubit_test.dart
git commit -m "example: ConnectionCubit drops redundant reads, handles StaleHandle"
```

---

## Task 12: Connection screen — banner + hint + recovery wrapper

**Files:**
- Modify: `bluey/example/lib/features/connection/presentation/connection_screen.dart`

- [ ] **Step 1: Same pattern as Tasks 8 and 10**

- `InvalidationBanner` when `state.connectionState == ConnectionState.invalidated`. The banner's `onRecover` calls `recreateBluey()`.
- `const AdapterCycleHint()` at the bottom.
- Wrap `BlocProvider` in `ValueListenableBuilder<int>` keyed `'connection-$tick'`.

- [ ] **Step 2: Verify and commit**

Run: `cd bluey/example && flutter test && flutter analyze`

```bash
git add bluey/example/lib/features/connection/presentation/connection_screen.dart
git commit -m "example: connection screen wires invalidation banner + recovery"
```

---

## Task 13: Service explorer — subscribe to servicesChanges + catch StaleHandle

**Files:**
- Modify: `bluey/example/lib/features/service_explorer/presentation/service_cubit.dart`
- Modify: `bluey/example/test/service_explorer/presentation/characteristic_cubit_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('subscribes to servicesChanges and updates services on re-discovery', () async {
  // mock connection.servicesChanges to emit a new service list;
  // assert cubit re-emits with the new services.
});

test('StaleHandleException during read flips state to invalidated', () async {
  // mock characteristic.read() to throw StaleHandleException;
  // assert cubit state reflects invalidation.
});
```

- [ ] **Step 2: Implement**

- Subscribe to `connection.servicesChanges` in the cubit's constructor / `initialize` path; on each emission, emit a state update with the new services list.
- Wrap read/write/notify-subscribe operations in `try { ... } on StaleHandleException catch (_) { /* emit invalidated state */ }`. The user recovers by tapping the banner on the connection screen (which is the parent of service explorer), so the service cubit need only stop further operations and surface the state.

- [ ] **Step 3: Verify and commit**

Run: `cd bluey/example && flutter test test/service_explorer/ && flutter analyze`

```bash
git add bluey/example/lib/features/service_explorer/presentation/service_cubit.dart bluey/example/test/service_explorer/presentation/characteristic_cubit_test.dart
git commit -m "example: ServiceCubit consumes servicesChanges + handles StaleHandle"
```

---

## Task 14: Integration test — adapter cycle through scanner screen

**Files:**
- Create: `bluey/example/test/integration/adapter_cycle_recovery_test.dart`

This is the single end-to-end golden path called out in the spec. Drives the scanner screen through start → adapter cycle → banner → recover → fresh scan, verifying the wiring across cubit, RecoveryNotifier, ServiceLocator, and the BlocProvider rebuild.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'package:bluey_example/features/scanner/presentation/scanner_screen.dart';
import 'package:bluey_example/shared/di/service_locator.dart';

import '../fakes/fake_bluey_platform_for_example.dart';

void main() {
  late FakeBlueyPlatformForExample fakePlatform;

  setUp(() async {
    fakePlatform = FakeBlueyPlatformForExample();
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    await setupServiceLocator(localIdentity: ServerId.generate());
  });

  tearDown(() async {
    await resetServiceLocator();
  });

  testWidgets('scanner survives adapter cycle via Recover', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScannerScreen()));
    await tester.pumpAndSettle();

    // No banner before adapter cycle.
    expect(find.text('Recover'), findsNothing);

    // Cycle the adapter off — banner appears.
    fakePlatform.setState(platform.BluetoothState.off);
    await tester.pumpAndSettle();
    expect(find.text('Recover'), findsOneWidget);

    // Bring the adapter back on so create() returns; tap Recover.
    fakePlatform.setState(platform.BluetoothState.on);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    // Banner cleared; the fresh cubit/screen is in its initial state.
    expect(find.text('Recover'), findsNothing);
  });
}
```

- [ ] **Step 2: Verify red, then green after Tasks 1-13 are merged**

Run: `cd bluey/example && flutter test test/integration/adapter_cycle_recovery_test.dart`
Expected: red until the recovery wiring (Tasks 1, 2, 8) is in place; green once all prior tasks complete.

If the test fails after all prior tasks are complete, debug the wiring — common causes: `RecoveryNotifier` not registered before screens read it, `ValueKey` not changing across rebuilds, `recreateBluey()` not awaited.

- [ ] **Step 3: Commit**

```bash
git add bluey/example/test/integration/adapter_cycle_recovery_test.dart
git commit -m "example: integration test for adapter-cycle recovery on scanner"
```

---

## Task 15: Final verification

**Files:** none — verification only.

- [ ] **Step 1: Run the full example test suite**

Run: `cd bluey/example && flutter test 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 2: Run the full library test suite (regression check)**

Run: `cd bluey && flutter test 2>&1 | tail -5`
Expected: 989/989 still pass (library was not touched, but verify nothing leaked).

- [ ] **Step 3: Run analyzer across the workspace**

Run: `flutter analyze 2>&1 | tail -5`
Expected: No issues found.

- [ ] **Step 4: Manual sanity check (recommended)**

Build the example on a device or simulator: `cd bluey/example && flutter run -d <device>`. Verify:
- Scanner screen shows a scan log under the results.
- Toggle Bluetooth off in system settings — invalidation banner appears on scanner / server / connection screens.
- Tap Recover — banner clears, Bluetooth re-enabled, can scan again.
- Server's existing log now contains `AdvertisingStartingEvent` / `AdvertisingStartedEvent` etc. alongside its own entries.
- Adapter-cycle hint visible at the bottom of all three affected screens.

If a device isn't available, skip Step 4 and document in the PR that on-device verification is pending.

- [ ] **Step 5: Open PR**

After all tasks land, open a PR titled "example: adopt PR #32 stream conventions" with a summary that references the spec and lists the per-feature changes.
