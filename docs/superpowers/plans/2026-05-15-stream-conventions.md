# Bluey Stream + State-Surface Conventions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply six uniform conventions across every domain-layer stream and state-getter surface in `bluey/` (replay-on-subscribe, terminal-signal-at-end-of-life, resource-cancel, sync-getter-honesty, plus state-machine modeling for Scanner / Server-advertising), and make `Bluey` async-constructed via `Bluey.create()` to close the cold-start race.

**Architecture:** Three coordinated changes per surface. (1) Each Type A `StreamController.broadcast(...)` gains an `onListen:` replay. (2) Each Type A stream's owning class adds an invalidation path that emits a terminal signal (enum value for enum-typed streams; `addError(StaleHandleException)` otherwise) then closes. (3) Sync getters agree with the last signal. Plus `Bluey()` becomes private and `Bluey.create()` is the public entry, awaiting the first state event before returning. Scanner and Server gain `ScanState` / `AdvertisingState` enums with full transition tracking.

**Tech Stack:** Dart 3 + Flutter. Domain layer only — platform-interface and platform packages are untouched.

**Spec:** `docs/superpowers/specs/2026-05-15-stream-conventions-design.md`

**Tickets resolved:** I334, I335, PR #31 P1, PR #31 P2, plus the previously unscoped scanner-lifecycle-events gap.

**Branch:** create `feature/stream-conventions` from main before starting.

---

## File Structure

### New files
- `bluey/lib/src/discovery/scan_state.dart` — `ScanState` enum.
- `bluey/lib/src/gatt_server/advertising_state.dart` — `AdvertisingState` enum.
- `bluey/test/discovery/scanner_state_machine_test.dart` — state-transition tests for Scanner.
- `bluey/test/gatt_server/advertising_state_machine_test.dart` — state-transition tests for Server.
- `bluey/test/bluey/bluey_create_test.dart` — tests for the new async factory.
- `bluey/test/connection/state_stream_conventions_test.dart` — Type A stream conventions tests (replay + terminal-signal) for Connection's four state streams.
- `bluey/test/bluey/state_stream_conventions_test.dart` — same for `Bluey.stateStream`.

### Files modified — domain
- `bluey/lib/src/bluey.dart` — `Bluey.create()` factory, private `_Bluey._()` constructor, `stateStream` replay, `currentState` honesty, factory pre-check uses guaranteed-fresh cache.
- `bluey/lib/src/connection/connection_state.dart` — add `invalidated` enum value.
- `bluey/lib/src/connection/connection.dart` — re-export new types as needed.
- `bluey/lib/src/connection/bluey_connection.dart` — replay on all 4 Type A streams; terminal-signal on invalidation (stateChanges emits `invalidated`; servicesChanges/bondStateChanges/phyChanges emit `addError`); sync getters throw or return enum value to match.
- `bluey/lib/src/discovery/scanner.dart` (abstract) — declare `state` getter and `stateChanges` stream; mark `isScanning` as derived.
- `bluey/lib/src/discovery/bluey_scanner.dart` — full `ScanState` state machine, replay on `stateChanges`, terminal-signal on invalidation, `scan()` adds `onCancel: () => stop()`, emit `ScanStartingEvent` / `ScanStoppingEvent`.
- `bluey/lib/src/gatt_server/server.dart` (abstract) — declare `advertisingState` getter and `advertisingStateChanges` stream; mark `isAdvertising` as derived.
- `bluey/lib/src/gatt_server/bluey_server.dart` — full `AdvertisingState` state machine, replay on `advertisingStateChanges`, terminal-signal on invalidation, emit `AdvertisingStartingEvent` / `AdvertisingStoppingEvent`.
- `bluey/lib/src/events.dart` — add `ScanStartingEvent`, `ScanStoppingEvent`, `AdvertisingStartingEvent`, `AdvertisingStoppingEvent`.

### Files modified — tests
- Approximately 255 `Bluey()` callsites across `bluey/test/` and `bluey/example/` migrate to `await Bluey.create()`. Most are in `setUp(...)` blocks. Test setUp signatures may need to become async.
- `bluey/test/fakes/fake_platform.dart` — confirm `setState` emits on `stateStream` so `Bluey.create()` awaits resolve; if not, fix.
- Any test that constructs `Bluey()` in a synchronous context (rare) needs `Future` wrapping or rework.

### Files modified — backlog
- `docs/backlog/I334-statestream-no-current-value-replay.md` — status `fixed`.
- `docs/backlog/I335-scanner-stream-no-oncancel-stopscan.md` — status `fixed`.

---

### Task 1: Add `ConnectionState.invalidated` enum value

**Files:**
- Modify: `bluey/lib/src/connection/connection_state.dart`
- Test: existing `bluey/test/connection_test.dart` or wherever `ConnectionState` is tested

The new value is the terminal signal `Connection.stateChanges` emits when adapter invalidation runs. Touching it first is purely additive — no behavior change yet.

- [ ] **Step 1.1: Read the enum to see existing values**

Read `bluey/lib/src/connection/connection_state.dart` to see the current ordering and doc comments. The existing values per the I333 design are: `disconnected, connecting, linked, ready, disconnecting`.

- [ ] **Step 1.2: Add the failing test**

In `bluey/test/connection_test.dart`, find the `ConnectionState` test group. Add:

```dart
test('invalidated value exists and is distinct from disconnected', () {
  expect(ConnectionState.invalidated, isA<ConnectionState>());
  expect(ConnectionState.invalidated, isNot(equals(ConnectionState.disconnected)));
});
```

- [ ] **Step 1.3: Run to verify fail**

Run: `cd bluey && flutter test test/connection_test.dart`
Expected: compile error — `invalidated` not defined.

- [ ] **Step 1.4: Add the enum value**

Modify `bluey/lib/src/connection/connection_state.dart`. After the existing `disconnecting` value, add:

```dart
  /// Terminal state set when this connection is invalidated by an
  /// adapter-state transition (e.g. Bluetooth toggled off). Distinct
  /// from [disconnected] which represents a normal disconnect path.
  /// See I333 for the broader invalidation contract.
  invalidated,
```

- [ ] **Step 1.5: Verify**

Run: `cd bluey && flutter test test/connection_test.dart`
Expected: pass.

Run: `flutter analyze`
Expected: warnings on any non-exhaustive `switch (ConnectionState ...)` statements. Fix them by adding the new case (typically: `case ConnectionState.invalidated:` returns false / `'invalidated'` / similar, depending on the switch's purpose).

- [ ] **Step 1.6: Commit**

```bash
git add bluey/lib/src/connection/connection_state.dart bluey/test/connection_test.dart
# Plus any switch-updates that the analyzer surfaced.
git commit -m "$(cat <<'EOF'
stream-conv: add ConnectionState.invalidated

New terminal enum value used by I333 invalidation paths to signal
"this connection is dead because the adapter went away" rather than
"this connection was disconnected normally." The downstream code that
makes stateChanges/state actually emit/return this value follows in
a later commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add `ScanState` enum + scanner lifecycle events

**Files:**
- Create: `bluey/lib/src/discovery/scan_state.dart`
- Modify: `bluey/lib/src/events.dart`
- Test: `bluey/test/discovery/scan_state_test.dart` (small file, just enum membership)

- [ ] **Step 2.1: Create the enum file**

Create `bluey/lib/src/discovery/scan_state.dart`:

```dart
/// Lifecycle state of a [Scanner].
///
/// Wraps the previously-boolean `isScanning` field with explicit
/// transient states so consumers can observe the windows during which
/// the platform call is in flight.
enum ScanState {
  /// No scan active and none being started.
  stopped,

  /// `scan()` has been called; the platform-side start is in flight.
  starting,

  /// Platform confirms the scan is running.
  scanning,

  /// `stop()` has been called (or the consumer cancelled the
  /// subscription, or a `timeout` fired); the platform-side stop is
  /// in flight.
  stopping,

  /// Terminal state set when this scanner is invalidated by an
  /// adapter-state transition. Distinct from [stopped] which is a
  /// resumable rest state. See I333.
  invalidated,
}
```

- [ ] **Step 2.2: Add a sanity test**

Create `bluey/test/discovery/scan_state_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanState', () {
    test('has all five expected values', () {
      expect(ScanState.values, hasLength(5));
      expect(ScanState.values, contains(ScanState.stopped));
      expect(ScanState.values, contains(ScanState.starting));
      expect(ScanState.values, contains(ScanState.scanning));
      expect(ScanState.values, contains(ScanState.stopping));
      expect(ScanState.values, contains(ScanState.invalidated));
    });

    test('invalidated is distinct from stopped', () {
      expect(ScanState.invalidated, isNot(equals(ScanState.stopped)));
    });
  });
}
```

- [ ] **Step 2.3: Export from package-public**

In `bluey/lib/bluey.dart`, add to the export section:

```dart
export 'src/discovery/scan_state.dart';
```

Place it alphabetically next to other discovery exports.

- [ ] **Step 2.4: Add lifecycle event classes**

Modify `bluey/lib/src/events.dart`. Find the existing `ScanStartedEvent` / `ScanStoppedEvent` classes (around the existing scanner events). After `ScanStartedEvent`, add `ScanStartingEvent`; after `ScanStoppedEvent`, add `ScanStoppingEvent`:

```dart
/// Emitted when [Scanner.scan] is called and the platform-side start
/// is now in flight. Followed by [ScanStartedEvent] when the platform
/// confirms (or a failure if the platform rejects).
final class ScanStartingEvent extends BlueyEvent {
  final List<UUID>? serviceFilter;
  final Duration? timeout;

  ScanStartingEvent({
    this.serviceFilter,
    this.timeout,
    super.source,
  });
}

/// Emitted when [Scanner.stop] is called (or the consumer cancelled
/// the subscription, or a timeout fired) and the platform-side stop
/// is now in flight. Followed by [ScanStoppedEvent] when the platform
/// confirms.
final class ScanStoppingEvent extends BlueyEvent {
  ScanStoppingEvent({super.source});
}
```

- [ ] **Step 2.5: Verify**

Run: `cd bluey && flutter test test/discovery/scan_state_test.dart`
Expected: pass.

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 2.6: Commit**

```bash
git add bluey/lib/src/discovery/scan_state.dart \
        bluey/test/discovery/scan_state_test.dart \
        bluey/lib/bluey.dart \
        bluey/lib/src/events.dart
git commit -m "$(cat <<'EOF'
stream-conv: add ScanState enum + transient lifecycle events

ScanState models the full async lifecycle of a scanner instance
(stopped/starting/scanning/stopping/invalidated). ScanStartingEvent
and ScanStoppingEvent join the existing started/stopped events so
consumers can observe the transient platform-call windows.
Behavioral integration (driving the state machine from scan()/stop()
etc.) lands in a later commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add `AdvertisingState` enum + server lifecycle events

**Files:**
- Create: `bluey/lib/src/gatt_server/advertising_state.dart`
- Modify: `bluey/lib/src/events.dart`
- Test: `bluey/test/gatt_server/advertising_state_test.dart`

Same shape as Task 2, applied to the server.

- [ ] **Step 3.1: Create the enum file**

Create `bluey/lib/src/gatt_server/advertising_state.dart`:

```dart
/// Lifecycle state of a [Server]'s advertising operation.
///
/// Wraps the previously-boolean `isAdvertising` field with explicit
/// transient states so consumers can observe the windows during which
/// the platform call is in flight.
enum AdvertisingState {
  /// Not currently advertising and not in the middle of starting.
  idle,

  /// `startAdvertising()` has been called; platform-side start is in
  /// flight.
  starting,

  /// Platform confirms advertising is active.
  advertising,

  /// `stopAdvertising()` has been called; platform-side stop is in
  /// flight.
  stopping,

  /// Terminal state set when the parent [Server] is invalidated by an
  /// adapter-state transition. See I333.
  invalidated,
}
```

- [ ] **Step 3.2: Add sanity test**

Create `bluey/test/gatt_server/advertising_state_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdvertisingState', () {
    test('has all five expected values', () {
      expect(AdvertisingState.values, hasLength(5));
      expect(AdvertisingState.values, contains(AdvertisingState.idle));
      expect(AdvertisingState.values, contains(AdvertisingState.starting));
      expect(AdvertisingState.values, contains(AdvertisingState.advertising));
      expect(AdvertisingState.values, contains(AdvertisingState.stopping));
      expect(AdvertisingState.values, contains(AdvertisingState.invalidated));
    });
  });
}
```

- [ ] **Step 3.3: Export package-public**

In `bluey/lib/bluey.dart`, add:

```dart
export 'src/gatt_server/advertising_state.dart';
```

- [ ] **Step 3.4: Add lifecycle events**

In `bluey/lib/src/events.dart`, after `AdvertisingStartedEvent` add `AdvertisingStartingEvent`, after `AdvertisingStoppedEvent` add `AdvertisingStoppingEvent`:

```dart
/// Emitted when [Server.startAdvertising] is called and the
/// platform-side start is now in flight.
final class AdvertisingStartingEvent extends BlueyEvent {
  AdvertisingStartingEvent({super.source});
}

/// Emitted when [Server.stopAdvertising] is called and the
/// platform-side stop is now in flight.
final class AdvertisingStoppingEvent extends BlueyEvent {
  AdvertisingStoppingEvent({super.source});
}
```

- [ ] **Step 3.5: Verify**

Run: `cd bluey && flutter test test/gatt_server/advertising_state_test.dart`
Expected: pass.

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 3.6: Commit**

```bash
git add bluey/lib/src/gatt_server/advertising_state.dart \
        bluey/test/gatt_server/advertising_state_test.dart \
        bluey/lib/bluey.dart \
        bluey/lib/src/events.dart
git commit -m "$(cat <<'EOF'
stream-conv: add AdvertisingState enum + transient lifecycle events

Mirrors Task 2 (ScanState) for the server's advertising lifecycle.
Behavioral integration follows.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add `Bluey.create()` async factory; keep `Bluey()` working

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Create: `bluey/test/bluey/bluey_create_test.dart`

This task adds the new entry point without breaking existing callsites. The migration of those callsites is Task 5.

- [ ] **Step 4.1: Write failing tests**

Create `bluey/test/bluey/bluey_create_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  group('Bluey.create()', () {
    test('returns a Bluey whose currentState reflects the fake', () async {
      fakePlatform.setState(platform.BluetoothState.on);

      final bluey = await Bluey.create();
      addTearDown(bluey.dispose);

      expect(bluey.currentState, equals(BluetoothState.on));
    });

    test('awaits the first platform state event before returning', () async {
      // Fake's default is BluetoothState.on but the broadcast happens
      // when create() subscribes. Confirm the cache is fresh on return.
      final bluey = await Bluey.create();
      addTearDown(bluey.dispose);

      expect(bluey.currentState, isNot(equals(BluetoothState.unknown)));
    });

    test(
      'completes with unknown after the configured timeout if no state arrives',
      () async {
        // Configure the fake to never emit state by overriding setState
        // semantics. (FakeBlueyPlatform may need a way to suppress the
        // implicit on-subscribe emission — Task 4.3 confirms.)
        fakePlatform.suppressInitialStateEmission = true;

        final bluey = await Bluey.create(
          initialStateTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(bluey.dispose);

        expect(bluey.currentState, equals(BluetoothState.unknown));
      },
    );
  });
}
```

- [ ] **Step 4.2: Run to verify failure**

Run: `cd bluey && flutter test test/bluey/bluey_create_test.dart`
Expected: FAIL — `Bluey.create` does not exist; `suppressInitialStateEmission` field does not exist on `FakeBlueyPlatform`.

- [ ] **Step 4.3: Extend `FakeBlueyPlatform` to support the new test**

Modify `bluey/test/fakes/fake_platform.dart`. Add:

```dart
/// Test seam — when true, [setState] and the constructor will NOT emit
/// on [stateStream]. Used by [Bluey.create] tests to simulate platforms
/// that never publish an initial state.
bool suppressInitialStateEmission = false;
```

Then modify the `setState` (and any other setter that emits on `_stateController`) to respect the flag:

```dart
void setState(BluetoothState newState) {
  _state = newState;
  if (!suppressInitialStateEmission) {
    _stateController.add(newState);
  }
}
```

Also: confirm `FakeBlueyPlatform`'s `stateStream` actually emits the current state on subscribe (so `Bluey.create()`'s `firstWhere` resolves). Look for `_stateController = StreamController<...>.broadcast(onListen: ...)`. If the controller doesn't have `onListen` replay, add it (it should already, per Task 6 — but if Task 4 is being implemented first sequentially, the controller may need a `setState(BluetoothState.on)` call at construction to seed the initial emission).

The simplest interim fix: in the test's `setUp`, after creating the fake, immediately call `fakePlatform.setState(BluetoothState.on)` if the test needs a known state. This is already shown in the test code at Step 4.1.

- [ ] **Step 4.4: Add `Bluey.create()`**

In `bluey/lib/src/bluey.dart`, immediately after the existing `Bluey({ServerId? localIdentity})` constructor body, add the new factory:

```dart
  /// Asynchronously construct a [Bluey] instance, awaiting the first
  /// platform state event before returning.
  ///
  /// Use this in preference to the synchronous [Bluey()] constructor.
  /// The async path guarantees [currentState] reflects real adapter
  /// state by the time consumers call factories like [server],
  /// [connect], or [scanner], eliminating the cold-start race where
  /// the very first factory call could throw `BluetoothUnavailableException`
  /// spuriously because the cached state hadn't yet been refreshed.
  ///
  /// If the platform doesn't emit a state within [initialStateTimeout]
  /// (default 2 seconds — long enough for normal native init, short
  /// enough to surface a stuck platform promptly), this falls back to
  /// the synchronous-cache behavior — [currentState] may be
  /// [BluetoothState.unknown] and the first factory call may throw
  /// `BluetoothUnavailableException`. Consumers can either retry or
  /// extend the timeout.
  static Future<Bluey> create({
    ServerId? localIdentity,
    Duration initialStateTimeout = const Duration(seconds: 2),
  }) async {
    final bluey = Bluey(localIdentity: localIdentity);
    try {
      // Await the first state event so the sync cache is fresh.
      await bluey.stateStream.firstWhere(
        (s) => s != BluetoothState.unknown,
      ).timeout(initialStateTimeout);
    } on TimeoutException {
      // Fall through: bluey is returned with whatever cache state
      // exists (typically still BluetoothState.unknown). Documented
      // behavior; consumers can retry.
    }
    return bluey;
  }
```

Required imports at the top of the file if missing: `import 'dart:async';` for `TimeoutException`.

- [ ] **Step 4.5: Run tests to verify pass**

Run: `cd bluey && flutter test test/bluey/bluey_create_test.dart`
Expected: pass.

Run: `cd bluey && flutter test` (full suite)
Expected: all tests pass (no behavior change to existing `Bluey()` callsites).

- [ ] **Step 4.6: Commit**

```bash
git add bluey/lib/src/bluey.dart \
        bluey/test/bluey/bluey_create_test.dart \
        bluey/test/fakes/fake_platform.dart
git commit -m "$(cat <<'EOF'
stream-conv: add Bluey.create() async factory

Async constructor that awaits the first platform state event before
returning, eliminating the cold-start race documented in PR #31 P1.
Falls back to the existing sync-cache behavior after a 2s timeout if
the platform never emits, so behavior degrades gracefully on
misconfigured native plugins.

The synchronous Bluey() constructor stays for now; migration of
~255 callsites lands in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Migrate all `Bluey()` callsites to `Bluey.create()`; privatize `Bluey()`

**Files:**
- Modify: every test file using `Bluey()` (~255 callsites)
- Modify: example app callsites
- Modify: `bluey/lib/src/bluey.dart` — privatize the synchronous constructor

This is a mechanical sweep. The goal is to ensure no public `Bluey()` callsite remains, then make the constructor private.

- [ ] **Step 5.1: Enumerate callsites**

```bash
grep -rln 'Bluey()' bluey/test bluey/example > /tmp/bluey-callsites.txt
wc -l /tmp/bluey-callsites.txt
```

Expect ~30-50 distinct files (~255 individual `Bluey()` callsites — but many in the same file).

- [ ] **Step 5.2: Migrate each callsite**

For each file, find every `Bluey()` and apply one of these transforms:

**Pattern 1: in synchronous `setUp(...)`:**

```dart
// Before:
setUp(() {
  fakePlatform = FakeBlueyPlatform();
  platform.BlueyPlatform.instance = fakePlatform;
  bluey = Bluey();
});

// After:
setUp(() async {
  fakePlatform = FakeBlueyPlatform();
  platform.BlueyPlatform.instance = fakePlatform;
  bluey = await Bluey.create();
});
```

Note: `setUp` callback becomes `async`. Flutter test infra supports async setUp.

**Pattern 2: in `Bluey.shared` lazy initialization:**

```dart
// If existing: static Bluey get shared => _shared ??= Bluey();
// Becomes: static Future<Bluey> get shared async => _shared ??= await Bluey.create();
// Or remove the synchronous shared accessor and document that consumers
// must await create() explicitly. Read current source to decide.
```

**Pattern 3: in synchronous test helpers:**

```dart
// Before:
final bluey = Bluey();
final server = bluey.server();

// After:
final bluey = await Bluey.create();
final server = bluey.server();
```

If the enclosing function isn't `async`, make it `async`.

> **Verification per file**: run `flutter test test/path/to/file.dart` after each file's migration; expect green.

- [ ] **Step 5.3: Run the full suite incrementally**

After every 5-10 files migrated, run:

```bash
cd /Users/joel/git/neutrinographics/bluey && flutter analyze
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test
```

Expect clean. If failures appear, fix them as you go.

- [ ] **Step 5.4: Migrate the example app**

```bash
grep -rln 'Bluey()' bluey/example
```

For each match, apply the same transforms. The example app's `main()` is async already (it usually is in Flutter apps), so the migration is mechanical.

Example-app migration sample (most common pattern):

```dart
// In main.dart or equivalent:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bluey = await Bluey.create();
  runApp(MyApp(bluey: bluey));
}
```

- [ ] **Step 5.5: Privatize the synchronous constructor**

Modify `bluey/lib/src/bluey.dart`:

```dart
// Before:
Bluey({ServerId? localIdentity})
    : _platform = platform.BlueyPlatform.instance,
      _eventBus = BlueyEventBus(),
      _localIdentity = localIdentity {
  // ... body
}

// After:
Bluey._({ServerId? localIdentity})
    : _platform = platform.BlueyPlatform.instance,
      _eventBus = BlueyEventBus(),
      _localIdentity = localIdentity {
  // ... body unchanged
}
```

Update `Bluey.create()` to call the renamed private constructor:

```dart
static Future<Bluey> create({...}) async {
  final bluey = Bluey._(localIdentity: localIdentity);
  // ... rest unchanged
}
```

Update `Bluey.shared` accessor if it still exists — it must now go through `create()` or be removed. Recommend removing `Bluey.shared` entirely if it's an obstacle to async-only construction; the docs can recommend a single top-level `bluey` variable initialized in `main()`.

- [ ] **Step 5.6: Verify the privatization**

Run: `flutter analyze`
Expected: clean. Any remaining `Bluey()` callsites (which would now reference the no-longer-public constructor) surface here.

Run: `cd bluey && flutter test`
Expected: all green.

- [ ] **Step 5.7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
stream-conv: migrate ~255 Bluey() callsites to Bluey.create()

Mechanical sweep. setUp callbacks become async. Example app's main()
awaits the factory. Bluey() constructor is now private (Bluey._).

This closes PR #31 P1 (cold-start race): the synchronous Bluey()
construction window where _currentState was BluetoothState.unknown
no longer exists in public consumer code. After await Bluey.create(),
the cache is always fresh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Apply Convention 2 (replay-on-subscribe) to `Bluey.stateStream`

**Files:**
- Modify: `bluey/lib/src/bluey.dart` — change `_stateController` to use `onListen` replay
- Modify: `bluey/test/bluey/state_stream_conventions_test.dart` (or wherever)

- [ ] **Step 6.1: Write the failing test**

Create `bluey/test/bluey/state_stream_conventions_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Bluey.stateStream (Convention 2 — replay on subscribe)', () {
    test('replays current value to a new subscriber', () async {
      // bluey.currentState is BluetoothState.on at this point.
      final received = <BluetoothState>[];
      final sub = bluey.stateStream.listen(received.add);

      // Give the onListen replay a microtask turn to fire.
      await Future<void>.delayed(Duration.zero);

      expect(received, equals([BluetoothState.on]));

      await sub.cancel();
    });

    test('two subscribers each get the current value independently', () async {
      final received1 = <BluetoothState>[];
      final received2 = <BluetoothState>[];

      final sub1 = bluey.stateStream.listen(received1.add);
      await Future<void>.delayed(Duration.zero);
      final sub2 = bluey.stateStream.listen(received2.add);
      await Future<void>.delayed(Duration.zero);

      expect(received1, equals([BluetoothState.on]));
      expect(received2, equals([BluetoothState.on]));

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
```

- [ ] **Step 6.2: Run to verify fail**

Run: `cd bluey && flutter test test/bluey/state_stream_conventions_test.dart`
Expected: FAIL — received list is empty (no replay today).

- [ ] **Step 6.3: Apply `onListen` to `_stateController`**

Modify `bluey/lib/src/bluey.dart`. Find `_stateController`'s declaration (around line 94):

```dart
// Before:
final StreamController<BluetoothState> _stateController =
    StreamController<BluetoothState>.broadcast();

// After:
late final StreamController<BluetoothState> _stateController =
    StreamController<BluetoothState>.broadcast(
  onListen: () {
    // Convention 2 — replay the current value to new subscribers so
    // they don't have to wait for the next transition to learn the
    // adapter state. Matches BehaviorSubject semantics.
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  },
);
```

Note: `final` becomes `late final` because the closure references the controller itself.

- [ ] **Step 6.4: Run tests to verify pass**

Run: `cd bluey && flutter test test/bluey/state_stream_conventions_test.dart`
Expected: pass.

Run: `cd bluey && flutter test` (full suite)
Expected: most pass; some may fail if they were relying on "no initial emission" behavior. Audit any failures: typically a test that did `bluey.stateStream.toList()` and counted emissions — now there's one extra at the start. Update test expectations.

- [ ] **Step 6.5: Commit**

```bash
git add bluey/lib/src/bluey.dart \
        bluey/test/bluey/state_stream_conventions_test.dart
# Plus any updated tests from Step 6.4 audit.
git commit -m "$(cat <<'EOF'
stream-conv: Bluey.stateStream replays current value on subscribe

Closes I334. New subscribers receive the current BluetoothState as
their first event, matching the BehaviorSubject pattern used across
the Flutter/RxDart ecosystem. Consumers no longer need to subscribe
+ read currentState + reconcile.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Apply Convention 2 to Connection's four Type A streams

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`
- Modify: `bluey/test/connection/state_stream_conventions_test.dart` (new)

The four streams: `stateChanges`, `servicesChanges`, `bondStateChanges`, `phyChanges`. Apply the same `onListen` replay pattern to each.

- [ ] **Step 7.1: Write failing tests**

Create `bluey/test/connection/state_stream_conventions_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  Future<Connection> establish() async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Sensor',
      services: const [],
    );
    final device = Device(
      id: UUID('00000000-0000-0000-0000-aabbccddee01'),
      address: TestDeviceIds.device1,
      name: 'Sensor',
    );
    return bluey.connect(device);
  }

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Connection Type A streams (Convention 2 — replay on subscribe)', () {
    test('stateChanges replays current state', () async {
      final connection = await establish();

      final received = <ConnectionState>[];
      final sub = connection.stateChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      expect(received.last, equals(connection.state));

      await sub.cancel();
    });

    test('bondStateChanges replays current bondState (Android)', () async {
      final connection = await establish();
      final android = connection.android!;

      final received = <BondState>[];
      final sub = android.bondStateChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      expect(received.last, equals(android.bondState));

      await sub.cancel();
    });

    test('phyChanges replays current PHY (Android)', () async {
      final connection = await establish();
      final android = connection.android!;

      final received = <({Phy tx, Phy rx})>[];
      final sub = android.phyChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      expect(received.last.tx, equals(android.txPhy));
      expect(received.last.rx, equals(android.rxPhy));

      await sub.cancel();
    });

    // servicesChanges is a corner case — its value type is List<RemoteService>
    // and there's no notion of "current services" until services() has been
    // called. The replay should emit either an empty list or the current
    // cached services list. Spec says: emit the cached services if
    // discovery has happened, otherwise an empty list.
    test('servicesChanges replays current services list', () async {
      final connection = await establish();

      // Trigger initial discovery so there's a cache to replay.
      final services = await connection.services();

      final received = <List<RemoteService>>[];
      final sub = connection.servicesChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotEmpty);
      expect(received.last.length, equals(services.length));

      await sub.cancel();
    });
  });
}
```

- [ ] **Step 7.2: Run to verify fail**

Run: `cd bluey && flutter test test/connection/state_stream_conventions_test.dart`
Expected: FAIL — none of the four streams replay today.

- [ ] **Step 7.3: Apply `onListen` to each controller**

Modify `bluey/lib/src/connection/bluey_connection.dart`. For each of the four controllers, change the declaration to use `onListen`:

```dart
// _stateController — replays current ConnectionState
late final StreamController<ConnectionState> _stateController =
    StreamController<ConnectionState>.broadcast(
  onListen: () {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  },
);

// _servicesChangesController — replays current cached services (empty if undiscovered)
late final StreamController<List<RemoteService>> _servicesChangesController =
    StreamController<List<RemoteService>>.broadcast(
  onListen: () {
    if (!_servicesChangesController.isClosed) {
      _servicesChangesController.add(_cachedServices ?? const []);
    }
  },
);

// _bondStateController — replays current BondState
late final StreamController<BondState> _bondStateController =
    StreamController<BondState>.broadcast(
  onListen: () {
    if (!_bondStateController.isClosed) {
      _bondStateController.add(_bondState);
    }
  },
);

// _phyController — replays current ({tx, rx}) record
late final StreamController<({Phy tx, Phy rx})> _phyController =
    StreamController<({Phy tx, Phy rx})>.broadcast(
  onListen: () {
    if (!_phyController.isClosed) {
      _phyController.add((tx: _txPhy, rx: _rxPhy));
    }
  },
);
```

(Read the actual file before editing — field names may differ slightly; use the actual names. All four become `late final`.)

- [ ] **Step 7.4: Run tests to verify pass**

Run: `cd bluey && flutter test test/connection/state_stream_conventions_test.dart`
Expected: pass.

Run: `cd bluey && flutter test` (full suite)
Expected: most pass; audit failures the same way as Task 6.

- [ ] **Step 7.5: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/state_stream_conventions_test.dart
git commit -m "$(cat <<'EOF'
stream-conv: Connection Type A streams replay current value on subscribe

Applies Convention 2 to stateChanges, servicesChanges,
bondStateChanges, and phyChanges. New subscribers receive the
current value as their first event. Consistent with the I334 fix
for Bluey.stateStream applied in the previous commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Apply Convention 3 (terminal signal) to `Connection.stateChanges` + `connection.state`

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart` — invalidation path emits `ConnectionState.invalidated`; `state` getter returns it
- Modify: `bluey/test/connection/state_stream_conventions_test.dart` — add invalidation tests

- [ ] **Step 8.1: Write failing tests**

In `bluey/test/connection/state_stream_conventions_test.dart`, add a new group:

```dart
group('Connection.stateChanges (Convention 3 — terminal signal)', () {
  test(
    'emits ConnectionState.invalidated then closes on adapter invalidation',
    () async {
      final connection = await establish();
      final received = <ConnectionState>[];
      final completer = Completer<void>();

      connection.stateChanges.listen(
        received.add,
        onDone: completer.complete,
      );
      await Future<void>.delayed(Duration.zero);

      fakePlatform.setState(platform.BluetoothState.off);
      await completer.future;

      expect(received.last, equals(ConnectionState.invalidated));
    },
  );

  test('connection.state returns invalidated after adapter invalidation', () async {
    final connection = await establish();
    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(connection.state, equals(ConnectionState.invalidated));
  });
});
```

Required import at the top: `import 'dart:async';` for `Completer`.

- [ ] **Step 8.2: Run to verify fail**

Run: `cd bluey && flutter test test/connection/state_stream_conventions_test.dart`
Expected: FAIL — invalidation today closes the controller without emitting; `state` getter is gated by `_ensureValid` (per I333) so it throws rather than returning `invalidated`.

- [ ] **Step 8.3: Modify invalidation path to emit terminal value**

In `bluey/lib/src/connection/bluey_connection.dart`, find `_invalidate(...)` (the I333 invalidation method). Before closing `_stateController`, add:

```dart
void _invalidate(BluetoothState triggeringState) {
  if (_invalidated) return;
  _invalidated = true;
  _invalidationState = triggeringState;

  // ... existing cancellations ...

  // Convention 3 — emit terminal enum value before closing so
  // subscribers observe the transition cleanly. Set _state first so
  // the new value is consistent with the sync getter.
  _state = ConnectionState.invalidated;
  if (!_stateController.isClosed) {
    _stateController.add(ConnectionState.invalidated);
    _stateController.close();
  }

  // ... existing addError + close for the other 3 streams (Task 9) ...
  // ... rest of existing _invalidate body ...
}
```

(Place the `_state =` assignment and `_stateController.add/close` in the right spot relative to the existing teardown order — verify by reading the existing `_invalidate` body. The key constraint: `_state` must be set to `invalidated` BEFORE subscribers receive the event so a `connection.state` poll inside their handler agrees.)

- [ ] **Step 8.4: Modify `state` getter to bypass `_ensureValid` for the terminal read**

The getter currently calls `_ensureValid()` per I333, which throws `StaleHandleException`. Convention 6 says the sync getter should agree with the last signal — which for `state` means returning `ConnectionState.invalidated`, not throwing.

Modify the `state` getter:

```dart
// Before (I333):
@override
ConnectionState get state {
  _ensureValid();
  return _state;
}

// After (Convention 6):
@override
ConnectionState get state => _state;
```

Justification: `_state` is now always honest — it's `invalidated` post-invalidation, set in `_invalidate`. The `_ensureValid()` gate was there to lie loudly; now the field itself is honest, so the gate is unnecessary and harmful.

- [ ] **Step 8.5: Run tests to verify pass**

Run: `cd bluey && flutter test test/connection/state_stream_conventions_test.dart`
Expected: pass.

Run: `cd bluey && flutter test` (full suite)
Expected: all pass. If any I333 test asserted that `connection.state` throws after invalidation, that test's expectation is now wrong — update it to expect `ConnectionState.invalidated` instead. Verify those tests' intent matches: they should be about "the connection signals invalidation", not "the getter throws".

- [ ] **Step 8.6: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/state_stream_conventions_test.dart
git commit -m "$(cat <<'EOF'
stream-conv: Connection.state{Changes,} signal invalidated terminal

Closes PR #31 P2. Convention 3 + Convention 6: on adapter invalidation,
stateChanges emits ConnectionState.invalidated then closes, and the
connection.state getter returns the same value (instead of throwing).
The _ensureValid() gate is removed from the getter — _state is now
always honest, so the gate is unnecessary.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Apply Convention 3 to Connection's three other Type A streams (`addError` path)

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`
- Modify: `bluey/test/connection/state_stream_conventions_test.dart` — add tests for each

For streams whose value type isn't an enum we own (`servicesChanges`, `bondStateChanges`, `phyChanges`), terminal signal is `addError(StaleHandleException)` then close. Corresponding sync getters throw `StaleHandleException`.

- [ ] **Step 9.1: Write failing tests**

In `bluey/test/connection/state_stream_conventions_test.dart`, append:

```dart
group('Connection non-enum streams (Convention 3 — addError + close)', () {
  test(
    'servicesChanges errors with StaleHandleException then closes on invalidation',
    () async {
      final connection = await establish();
      Object? errorReceived;
      final completer = Completer<void>();

      connection.servicesChanges.listen(
        (_) {},
        onError: (e) => errorReceived = e,
        onDone: completer.complete,
      );
      await Future<void>.delayed(Duration.zero);

      fakePlatform.setState(platform.BluetoothState.off);
      await completer.future;

      expect(errorReceived, isA<StaleHandleException>());
    },
  );

  test(
    'bondStateChanges errors with StaleHandleException then closes',
    () async {
      final connection = await establish();
      final android = connection.android!;
      Object? errorReceived;
      final completer = Completer<void>();

      android.bondStateChanges.listen(
        (_) {},
        onError: (e) => errorReceived = e,
        onDone: completer.complete,
      );
      await Future<void>.delayed(Duration.zero);

      fakePlatform.setState(platform.BluetoothState.off);
      await completer.future;

      expect(errorReceived, isA<StaleHandleException>());
    },
  );

  test(
    'phyChanges errors with StaleHandleException then closes',
    () async {
      final connection = await establish();
      final android = connection.android!;
      Object? errorReceived;
      final completer = Completer<void>();

      android.phyChanges.listen(
        (_) {},
        onError: (e) => errorReceived = e,
        onDone: completer.complete,
      );
      await Future<void>.delayed(Duration.zero);

      fakePlatform.setState(platform.BluetoothState.off);
      await completer.future;

      expect(errorReceived, isA<StaleHandleException>());
    },
  );
});
```

- [ ] **Step 9.2: Run to verify fail**

Run: `cd bluey && flutter test test/connection/state_stream_conventions_test.dart`
Expected: FAIL — streams close cleanly today without `addError`.

- [ ] **Step 9.3: Modify `_invalidate` to addError on the three streams**

In `bluey/lib/src/connection/bluey_connection.dart`, in `_invalidate(...)`, replace the existing plain `close()` calls on the three non-enum controllers with `addError + close`:

```dart
void _invalidate(BluetoothState triggeringState) {
  if (_invalidated) return;
  _invalidated = true;
  _invalidationState = triggeringState;

  // ... existing cancellations ...

  // Convention 3 — stateChanges emits invalidated enum (Task 8).
  _state = ConnectionState.invalidated;
  if (!_stateController.isClosed) {
    _stateController.add(ConnectionState.invalidated);
    _stateController.close();
  }

  // Convention 3 — non-enum-valued Type A streams signal terminal
  // via addError(StaleHandleException) then close.
  final stale = StaleHandleException(
    triggeringState: _mapPlatformState(triggeringState),
    instanceType: InvalidatedInstance.connection,
  );

  if (!_servicesChangesController.isClosed) {
    _servicesChangesController.addError(stale);
    _servicesChangesController.close();
  }
  if (!_bondStateController.isClosed) {
    _bondStateController.addError(stale);
    _bondStateController.close();
  }
  if (!_phyController.isClosed) {
    _phyController.addError(stale);
    _phyController.close();
  }

  // ... rest of existing _invalidate body (cache clearing, etc.) ...
}
```

Read the existing `_invalidate` body carefully and integrate — don't double-close any controller.

- [ ] **Step 9.4: Run tests to verify pass**

Run: `cd bluey && flutter test test/connection/state_stream_conventions_test.dart`
Expected: all pass.

- [ ] **Step 9.5: Audit internal listeners**

Run: `grep -rn 'bondStateChanges\.listen\|phyChanges\.listen\|servicesChanges\.listen' bluey/lib`

For each result that uses `.listen(...)` without `onError:`, decide:
- If the listener is in code that runs only while the connection is valid (and is itself cleaned up on `_invalidate`), no `onError` needed.
- If the listener might outlive the connection, add `onError: (_) { /* expected on invalidation */ }`.

Common case: there are very few internal listeners on these streams (most consumers are external). Audit and fix.

- [ ] **Step 9.6: Run the full suite**

Run: `cd bluey && flutter test`
Expected: all pass. If any test produces "Unhandled error" warnings, that test's listener needs `onError`.

- [ ] **Step 9.7: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/state_stream_conventions_test.dart
# Plus any internal-listener fixes from Step 9.5.
git commit -m "$(cat <<'EOF'
stream-conv: non-enum Type A streams on Connection emit addError on invalidation

servicesChanges, bondStateChanges, phyChanges now emit
addError(StaleHandleException) then close on adapter invalidation
(Convention 3 — non-enum path). Their corresponding sync getters
already throw StaleHandleException per I333, so the stream and
getter agree (Convention 6).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: `Scanner.scan()` adds `onCancel: () => stop()`

**Files:**
- Modify: `bluey/lib/src/discovery/bluey_scanner.dart`
- Modify: `bluey/test/discovery/bluey_scanner_invalidation_test.dart` (or a new resource-cancel test file)

This is the I335 fix. Single-line change in the body of `scan()`.

- [ ] **Step 10.1: Write the failing test**

In `bluey/test/discovery/bluey_scanner_invalidation_test.dart` (or a new test file `bluey/test/discovery/scan_cancel_test.dart`), add:

```dart
test(
  'cancelling the scan subscription stops the platform scan',
  () async {
    final scanner = bluey.scanner();
    final sub = scanner.scan().listen((_) {});

    // Wait for scan to actually start at the platform layer.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(fakePlatform.isScanning, isTrue);

    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(fakePlatform.isScanning, isFalse);
  },
);
```

Note: `fakePlatform.isScanning` is a test seam — if it doesn't exist on `FakeBlueyPlatform`, add it as part of this task (a simple bool that flips on `scan(...)` / `stopScan()`).

- [ ] **Step 10.2: Run to verify fail**

Run: `cd bluey && flutter test test/discovery/scan_cancel_test.dart`
Expected: FAIL — `fakePlatform.isScanning` stays true after subscription cancel.

- [ ] **Step 10.3: Add `onCancel` to the controller in `scan()`**

In `bluey/lib/src/discovery/bluey_scanner.dart`, find the `scan(...)` method. Find the `StreamController<ScanResult>` creation. Change:

```dart
// Before:
final controller = StreamController<ScanResult>();

// After:
final controller = StreamController<ScanResult>(
  onCancel: () {
    // Convention 5 — last-subscriber cancel stops the platform
    // resource. stop() is idempotent: returns early if !_isScanning.
    return stop();
  },
);
```

- [ ] **Step 10.4: Run tests to verify pass**

Run: `cd bluey && flutter test test/discovery/scan_cancel_test.dart`
Expected: pass.

Run: `cd bluey && flutter test` (full suite)
Expected: all pass. Existing tests that explicitly called `scanner.stop()` after cancelling continue to work (stop is idempotent).

- [ ] **Step 10.5: Commit**

```bash
git add bluey/lib/src/discovery/bluey_scanner.dart \
        bluey/test/discovery/scan_cancel_test.dart \
        bluey/test/fakes/fake_platform.dart
git commit -m "$(cat <<'EOF'
stream-conv: Scanner.scan() stops platform scan on subscription cancel

Closes I335. Adds onCancel: () => stop() to the StreamController
returned from scan(). Cancelling the subscription is now sufficient
to stop the radio — matching Dart's resource-backed-stream convention
(Convention 5). Scanner.stop() stays for imperative control.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Scanner state machine integration

**Files:**
- Modify: `bluey/lib/src/discovery/scanner.dart` — abstract interface
- Modify: `bluey/lib/src/discovery/bluey_scanner.dart` — full implementation
- Create: `bluey/test/discovery/scanner_state_machine_test.dart`

Wire up `ScanState`, `Scanner.state`, `Scanner.stateChanges`, transient events, derived `isScanning`.

- [ ] **Step 11.1: Update the abstract `Scanner` interface**

In `bluey/lib/src/discovery/scanner.dart`, add to the abstract class:

```dart
abstract class Scanner {
  // ... existing members ...

  /// Current scan state. Replays via [stateChanges]. See [ScanState].
  ScanState get state;

  /// State transitions, replayed on subscribe (Convention 2).
  /// Terminal: emits [ScanState.invalidated] then closes on adapter
  /// invalidation.
  Stream<ScanState> get stateChanges;

  /// Whether the scanner is currently active. Derived from [state].
  /// Kept for ergonomic convenience.
  bool get isScanning;

  // ... existing `scan` and `stop` declarations unchanged ...
}
```

- [ ] **Step 11.2: Write failing state-machine tests**

Create `bluey/test/discovery/scanner_state_machine_test.dart`:

```dart
import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Scanner state machine', () {
    test('initial state is stopped', () {
      final scanner = bluey.scanner();
      expect(scanner.state, equals(ScanState.stopped));
    });

    test(
      'transitions stopped -> starting -> scanning -> stopping -> stopped',
      () async {
        final scanner = bluey.scanner();
        final observed = <ScanState>[];
        final sub = scanner.stateChanges.listen(observed.add);

        final scanSub = scanner.scan().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await scanSub.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          observed,
          containsAllInOrder([
            ScanState.stopped,    // replay
            ScanState.starting,
            ScanState.scanning,
            ScanState.stopping,
            ScanState.stopped,
          ]),
        );

        await sub.cancel();
      },
    );

    test('isScanning is derived from state', () async {
      final scanner = bluey.scanner();
      expect(scanner.isScanning, isFalse);

      final scanSub = scanner.scan().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(scanner.isScanning, isTrue);
      expect(scanner.state, equals(ScanState.scanning));

      await scanSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(scanner.isScanning, isFalse);
    });

    test('transitions to invalidated on adapter off', () async {
      final scanner = bluey.scanner();
      final observed = <ScanState>[];
      final closed = Completer<void>();
      scanner.stateChanges.listen(
        observed.add,
        onDone: closed.complete,
      );

      fakePlatform.setState(platform.BluetoothState.off);
      await closed.future;

      expect(observed.last, equals(ScanState.invalidated));
      expect(scanner.state, equals(ScanState.invalidated));
    });

    test('emits ScanStarting/ScanStopping events at transitions', () async {
      final scanner = bluey.scanner();
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      final scanSub = scanner.scan().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await scanSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.whereType<ScanStartingEvent>().length, equals(1));
      expect(events.whereType<ScanStartedEvent>().length, equals(1));
      expect(events.whereType<ScanStoppingEvent>().length, equals(1));
      expect(events.whereType<ScanStoppedEvent>().length, equals(1));
    });
  });
}
```

- [ ] **Step 11.3: Run to verify fail**

Run: `cd bluey && flutter test test/discovery/scanner_state_machine_test.dart`
Expected: FAIL — `Scanner.state`, `Scanner.stateChanges`, etc. don't exist yet.

- [ ] **Step 11.4: Implement the state machine in `BlueyScanner`**

Modify `bluey/lib/src/discovery/bluey_scanner.dart`. Add fields and the state machine:

```dart
class BlueyScanner implements Scanner {
  // ... existing fields ...

  // I333/stream-conv: replace bool _isScanning with the state machine.
  ScanState _state = ScanState.stopped;

  late final StreamController<ScanState> _stateController =
      StreamController<ScanState>.broadcast(
    onListen: () {
      if (!_stateController.isClosed) {
        _stateController.add(_state);
      }
    },
  );

  @override
  ScanState get state => _state;

  @override
  Stream<ScanState> get stateChanges => _stateController.stream;

  @override
  bool get isScanning => _state == ScanState.scanning;

  /// Transition helper. Pushes to stateChanges and emits the
  /// corresponding lifecycle event on _eventBus when applicable.
  void _setState(ScanState newState) {
    if (_state == newState) return;
    final old = _state;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
    // Emit the matching lifecycle event.
    switch (newState) {
      case ScanState.starting:
        _eventBus.emit(ScanStartingEvent(
          source: 'BlueyScanner',
        ));
      case ScanState.scanning:
        _eventBus.emit(ScanStartedEvent(source: 'BlueyScanner'));
      case ScanState.stopping:
        _eventBus.emit(ScanStoppingEvent(source: 'BlueyScanner'));
      case ScanState.stopped:
        if (old != ScanState.stopped) {
          _eventBus.emit(ScanStoppedEvent(source: 'BlueyScanner'));
        }
      case ScanState.invalidated:
        // No event for invalidated — the stateChanges stream + the
        // I333 instance invalidation are sufficient signals.
        break;
    }
  }

  // ... existing scan() ...
}
```

Now wire `_setState(...)` into `scan()` / `stop()` / the timeout / `_finishScan`:

```dart
@override
Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
  _ensureValid();
  _setState(ScanState.starting);

  final config = ...;
  final controller = StreamController<ScanResult>(
    onCancel: () => stop(),
  );

  _platformSubscription = _platform.scan(config).listen(
    (platformDevice) {
      if (_state == ScanState.starting) {
        _setState(ScanState.scanning);
      }
      // ... existing emit ...
    },
    onError: ...,
    onDone: () {
      _timeoutTimer?.cancel();
      _finishScan(controller);
    },
  );
  // ... existing timeout setup ...
  return controller.stream;
}

@override
Future<void> stop() async {
  if (_state == ScanState.stopped || _state == ScanState.stopping) {
    return;
  }
  _setState(ScanState.stopping);
  await _platform.stopScan();
  _platformSubscription?.cancel();
  _platformSubscription = null;
  _setState(ScanState.stopped);
}

void _finishScan(StreamController<ScanResult> controller) {
  if (!controller.isClosed) {
    controller.close();
  }
  _activeScanControllers.remove(controller);
  if (_state == ScanState.scanning) {
    _setState(ScanState.stopped);
  }
}
```

Update `_invalidate(...)`:

```dart
void _invalidate(BluetoothState triggeringState) {
  if (_invalidated) return;
  _invalidated = true;
  _invalidationState = triggeringState;

  // ... existing cancellations ...

  // Transition to invalidated terminal state.
  _setState(ScanState.invalidated);
  if (!_stateController.isClosed) {
    _stateController.close();
  }

  // ... existing scan-stream close + active-controllers tear-down ...
}
```

> Read the existing `BlueyScanner` carefully before editing. The state-machine integration touches several methods; do it in one pass.

- [ ] **Step 11.5: Remove the old `_isScanning` field**

The state machine replaces it. Find every reference to `_isScanning` in the file. Replace with `_state == ScanState.scanning` or remove. The public `isScanning` getter (now derived from `_state`) keeps working.

- [ ] **Step 11.6: Run tests to verify pass**

Run: `cd bluey && flutter test test/discovery/scanner_state_machine_test.dart`
Expected: pass.

Run: `cd bluey && flutter test` (full suite)
Expected: most pass; expect a few existing tests to fail if they relied on the old `_isScanning` field behavior. Update them.

- [ ] **Step 11.7: Commit**

```bash
git add bluey/lib/src/discovery/scanner.dart \
        bluey/lib/src/discovery/bluey_scanner.dart \
        bluey/test/discovery/scanner_state_machine_test.dart
git commit -m "$(cat <<'EOF'
stream-conv: Scanner state machine + transient lifecycle events

ScanState wraps the previous bool _isScanning. Scanner.state +
Scanner.stateChanges expose the lifecycle; isScanning is derived.
scan()/stop()/timeout/_finishScan drive transitions. ScanStartingEvent
and ScanStoppingEvent are emitted at the corresponding transitions.
Adapter invalidation transitions to ScanState.invalidated, closes
stateChanges, and surfaces via Convention 3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Server advertising state machine integration

**Files:**
- Modify: `bluey/lib/src/gatt_server/server.dart` — abstract interface
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart` — implementation
- Create: `bluey/test/gatt_server/advertising_state_machine_test.dart`

Same shape as Task 11, applied to advertising. Read both files first; mirror the pattern.

- [ ] **Step 12.1: Update the abstract `Server` interface**

In `bluey/lib/src/gatt_server/server.dart`:

```dart
abstract class Server {
  // ... existing members ...

  /// Current advertising state. Replays via [advertisingStateChanges].
  AdvertisingState get advertisingState;

  /// Advertising state transitions, replayed on subscribe.
  Stream<AdvertisingState> get advertisingStateChanges;

  /// Whether the server is currently advertising. Derived from
  /// [advertisingState]. Kept for ergonomic convenience.
  bool get isAdvertising;

  // ... existing members unchanged ...
}
```

- [ ] **Step 12.2: Write the state-machine tests**

Create `bluey/test/gatt_server/advertising_state_machine_test.dart`. Mirror `scanner_state_machine_test.dart` from Task 11, but for advertising:

```dart
import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Server advertising state machine', () {
    test('initial state is idle', () {
      final server = bluey.server()!;
      expect(server.advertisingState, equals(AdvertisingState.idle));
    });

    test(
      'startAdvertising / stopAdvertising drive transitions',
      () async {
        final server = bluey.server()!;
        final observed = <AdvertisingState>[];
        final sub = server.advertisingStateChanges.listen(observed.add);

        await server.startAdvertising();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await server.stopAdvertising();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          observed,
          containsAllInOrder([
            AdvertisingState.idle,        // replay
            AdvertisingState.starting,
            AdvertisingState.advertising,
            AdvertisingState.stopping,
            AdvertisingState.idle,
          ]),
        );

        await sub.cancel();
      },
    );

    test('isAdvertising derived from state', () async {
      final server = bluey.server()!;
      expect(server.isAdvertising, isFalse);

      await server.startAdvertising();
      expect(server.isAdvertising, isTrue);
      expect(server.advertisingState, equals(AdvertisingState.advertising));

      await server.stopAdvertising();
      expect(server.isAdvertising, isFalse);
    });

    test('transitions to invalidated on adapter off', () async {
      final server = bluey.server()!;
      await server.startAdvertising();
      final observed = <AdvertisingState>[];
      final closed = Completer<void>();
      server.advertisingStateChanges.listen(
        observed.add,
        onDone: closed.complete,
      );

      fakePlatform.setState(platform.BluetoothState.off);
      await closed.future;

      expect(observed.last, equals(AdvertisingState.invalidated));
      expect(server.advertisingState, equals(AdvertisingState.invalidated));
    });

    test('emits AdvertisingStarting/AdvertisingStopping events', () async {
      final server = bluey.server()!;
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      await server.startAdvertising();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await server.stopAdvertising();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(events.whereType<AdvertisingStartingEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStartedEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStoppingEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStoppedEvent>().length, equals(1));
    });
  });
}
```

- [ ] **Step 12.3: Run to verify fail**

Run: `cd bluey && flutter test test/gatt_server/advertising_state_machine_test.dart`
Expected: FAIL.

- [ ] **Step 12.4: Implement the state machine in `BlueyServer`**

Modify `bluey/lib/src/gatt_server/bluey_server.dart`. Mirror Task 11's structure:

```dart
class BlueyServer implements Server {
  // ... existing fields ...

  AdvertisingState _advertisingState = AdvertisingState.idle;

  late final StreamController<AdvertisingState> _advertisingStateController =
      StreamController<AdvertisingState>.broadcast(
    onListen: () {
      if (!_advertisingStateController.isClosed) {
        _advertisingStateController.add(_advertisingState);
      }
    },
  );

  @override
  AdvertisingState get advertisingState => _advertisingState;

  @override
  Stream<AdvertisingState> get advertisingStateChanges =>
      _advertisingStateController.stream;

  @override
  bool get isAdvertising => _advertisingState == AdvertisingState.advertising;

  void _setAdvertisingState(AdvertisingState newState) {
    if (_advertisingState == newState) return;
    final old = _advertisingState;
    _advertisingState = newState;
    if (!_advertisingStateController.isClosed) {
      _advertisingStateController.add(newState);
    }
    switch (newState) {
      case AdvertisingState.starting:
        _eventBus.emit(AdvertisingStartingEvent(source: 'BlueyServer'));
      case AdvertisingState.advertising:
        _eventBus.emit(AdvertisingStartedEvent(source: 'BlueyServer'));
      case AdvertisingState.stopping:
        _eventBus.emit(AdvertisingStoppingEvent(source: 'BlueyServer'));
      case AdvertisingState.idle:
        if (old != AdvertisingState.idle) {
          _eventBus.emit(AdvertisingStoppedEvent(source: 'BlueyServer'));
        }
      case AdvertisingState.invalidated:
        break;
    }
  }
}
```

Wire `_setAdvertisingState` into `startAdvertising()` / `stopAdvertising()`:

```dart
@override
Future<void> startAdvertising({...}) async {
  _ensureValid();
  _setAdvertisingState(AdvertisingState.starting);
  try {
    await _platform.startAdvertising(...);
    _setAdvertisingState(AdvertisingState.advertising);
  } catch (e) {
    _setAdvertisingState(AdvertisingState.idle);
    rethrow;
  }
}

@override
Future<void> stopAdvertising() async {
  _ensureValid();
  if (_advertisingState != AdvertisingState.advertising) return;
  _setAdvertisingState(AdvertisingState.stopping);
  await _platform.stopAdvertising();
  _setAdvertisingState(AdvertisingState.idle);
}
```

Wire into `_invalidate`:

```dart
void _invalidate(BluetoothState triggeringState) {
  if (_invalidated) return;
  // ... existing teardown ...

  _setAdvertisingState(AdvertisingState.invalidated);
  if (!_advertisingStateController.isClosed) {
    _advertisingStateController.close();
  }
}
```

- [ ] **Step 12.5: Remove `_isAdvertising` field**

Replace internal references with `_advertisingState == AdvertisingState.advertising`. The public `isAdvertising` getter (derived) keeps working.

- [ ] **Step 12.6: Run tests to verify pass**

Run: `cd bluey && flutter test test/gatt_server/advertising_state_machine_test.dart`
Expected: pass.

Run: `cd bluey && flutter test`
Expected: full suite green; audit any pre-existing tests that touched the old `_isAdvertising` field.

- [ ] **Step 12.7: Commit**

```bash
git add bluey/lib/src/gatt_server/server.dart \
        bluey/lib/src/gatt_server/bluey_server.dart \
        bluey/test/gatt_server/advertising_state_machine_test.dart
git commit -m "$(cat <<'EOF'
stream-conv: Server advertising state machine + transient events

Mirrors Task 11 (Scanner state machine) for server advertising.
AdvertisingState wraps the previous bool _isAdvertising. Server
exposes advertisingState + advertisingStateChanges + isAdvertising
(derived). Transient events (AdvertisingStartingEvent /
AdvertisingStoppingEvent) emitted at the corresponding transitions.
Adapter invalidation transitions to AdvertisingState.invalidated.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Audit internal listeners; final verification

**Files:**
- Modify: any internal listener on a Type A stream that doesn't currently handle `onError`

After Tasks 8 and 9, some Type A streams emit `addError(StaleHandleException)` on invalidation. Internal listeners that don't handle errors will produce "Unhandled error" warnings during tests.

- [ ] **Step 13.1: Find internal listeners**

```bash
grep -rn '\.stateChanges\.listen\|\.servicesChanges\.listen\|\.bondStateChanges\.listen\|\.phyChanges\.listen\|\.advertisingStateChanges\.listen' bluey/lib
```

For each result, check whether the `.listen(...)` call passes an `onError:` callback. If not, decide based on the listener's lifetime:

**If the listener is automatically cleaned up when the parent connection invalidates** (e.g. it's owned by the same class and the class disposes the subscription before invalidation closes the stream): probably fine, but adding a `onError: (_) {}` makes the intent explicit.

**If the listener may outlive the connection** (rare in bluey internals): definitely needs `onError`.

Apply this pattern:

```dart
// Before:
subscription = connection.servicesChanges.listen(_onServicesChanged);

// After:
subscription = connection.servicesChanges.listen(
  _onServicesChanged,
  onError: (_) {
    // Convention 3 — invalidated streams emit StaleHandleException
    // via addError before closing. The subscription is about to fire
    // onDone too; nothing to do here.
  },
);
```

- [ ] **Step 13.2: Run the full suite**

```bash
cd /Users/joel/git/neutrinographics/bluey && flutter analyze
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey_platform_interface && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey_ios && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey/example && flutter test
```

All green; no `Unhandled error` warnings during tests.

- [ ] **Step 13.3: Commit (if any fixes made)**

```bash
git add -A
git commit -m "$(cat <<'EOF'
stream-conv: handle stream errors on internal Type A listeners

Adds onError handlers to internal .listen() calls on Type A streams
that don't already have them, so adapter-invalidation addError
emissions don't surface as "Unhandled error" warnings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Mark I334 and I335 fixed; backlog hygiene

**Files:**
- Modify: `docs/backlog/I334-statestream-no-current-value-replay.md`
- Modify: `docs/backlog/I335-scanner-stream-no-oncancel-stopscan.md`

- [ ] **Step 14.1: Mark I334 fixed**

Modify `docs/backlog/I334-statestream-no-current-value-replay.md`. Change `status: open` to `status: fixed`. Add a Resolution section after the frontmatter:

```markdown
## Resolution (2026-05-15)

Closed by the stream-conventions sweep on branch
`feature/stream-conventions`. Per Convention 2 of
`docs/superpowers/specs/2026-05-15-stream-conventions-design.md`,
every Type A stream in bluey now uses `onListen:` replay. `Bluey.stateStream`
is the canonical one, but the convention applies uniformly to
`Connection.stateChanges`, `Connection.servicesChanges`,
`AndroidConnectionExtensions.bondStateChanges`,
`AndroidConnectionExtensions.phyChanges`, plus the new
`Scanner.stateChanges` and `Server.advertisingStateChanges`.

New subscribers receive the current value as their first emission;
the consumer-side `onListen` workaround in `gossip_bluey` can be
removed.
```

- [ ] **Step 14.2: Mark I335 fixed**

Same treatment for `docs/backlog/I335-scanner-stream-no-oncancel-stopscan.md`:

```markdown
## Resolution (2026-05-15)

Closed by the stream-conventions sweep on branch
`feature/stream-conventions`. Per Convention 5 of the design,
`Scanner.scan()`'s returned `StreamController` now has
`onCancel: () => stop()`. Cancelling the subscription stops the
platform scan; `Scanner.stop()` stays for imperative use.

The consumer-side workaround in `gossip_bluey` (holding the
`Scanner` reference and calling `stop()` explicitly) can be removed.
```

- [ ] **Step 14.3: Commit**

```bash
git add docs/backlog/I334-statestream-no-current-value-replay.md \
        docs/backlog/I335-scanner-stream-no-oncancel-stopscan.md
git commit -m "$(cat <<'EOF'
stream-conv: mark I334 and I335 resolved in backlog

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist

After implementation, verify before declaring done:

- [ ] `flutter analyze` clean across all packages.
- [ ] `bluey` package test suite passes.
- [ ] `bluey/example` test suite passes.
- [ ] `bluey_platform_interface`, `bluey_android`, `bluey_ios` test suites pass.
- [ ] `git grep "Bluey()"` returns only platform-interface / private references (no public-API construction sites).
- [ ] `git grep -E '\.broadcast\(\s*\)' bluey/lib` — every match should be a Type B stream. Verify.
- [ ] `Connection.state` returns `ConnectionState.invalidated` after `_invalidate()` runs (verified by test, not just grep).
- [ ] `connection.servicesChanges` / `bondStateChanges` / `phyChanges` emit `addError(StaleHandleException)` before closing on invalidation (verified by test).
- [ ] `Scanner.scan()` cancel stops the platform scan (verified by test).
- [ ] `Scanner.state` transitions through `stopped → starting → scanning → stopping → stopped` (verified by test).
- [ ] `Server.advertisingState` transitions through `idle → starting → advertising → stopping → idle` (verified by test).
- [ ] All transient lifecycle events fire (`ScanStartingEvent`, `ScanStoppingEvent`, `AdvertisingStartingEvent`, `AdvertisingStoppingEvent`).
- [ ] `Bluey.create()` exists; `Bluey()` is private (`Bluey._`).
- [ ] All commits use `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` footer.
- [ ] I334 and I335 frontmatter `status: fixed`.
