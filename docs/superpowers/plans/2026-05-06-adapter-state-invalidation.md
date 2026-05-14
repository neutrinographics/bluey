# Adapter-State Invalidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the Bluetooth adapter transitions out of `BluetoothState.on`, all live `BlueyServer` / `BlueyConnection` / `BlueyScanner` instances become terminal-failed and throw `StaleHandleException` on any subsequent call; factories pre-check state and throw the appropriate state-mapped exception synchronously; `Bluey.ensureReady` is removed as redundant; `DeadObjectException` (Android) and iOS post-`poweredOff` operations are translated to `BluetoothUnavailableException`.

**Architecture:** Each instance owns a `StreamSubscription` to `_platform.stateStream` established at construction. A single `_invalidate(BluetoothState)` method (idempotent) sets `_invalidated = true`, caches the triggering state, cancels the subscription, closes owned `StreamController`s, fails in-flight ops, and clears caches. A private `_ensureValid()` helper checks `_invalidated` at the entry of every public method and throws `StaleHandleException`. Factories on `Bluey` call a shared `_requireAdapterOn()` helper to throw state-mapped exceptions before any construction.

**Tech Stack:** Dart 3 + Flutter, Pigeon platform channels, Kotlin (Android), Swift (iOS). Domain layer has zero framework dependencies.

**Spec:** `docs/superpowers/specs/2026-05-06-adapter-state-invalidation-design.md`

**Ticket:** I333.

---

## File Structure

### New files
- `bluey/lib/src/shared/stale_handle_exception.dart` — `StaleHandleException` value object (or appended into `shared/exceptions.dart` — see Task 1).
- `bluey/test/connection/stale_handle_exception_test.dart` — unit tests for the exception type.
- `bluey/test/connection/adapter_state_invalidation_test.dart` — integration test for full adapter-cycle scenarios across `BlueyServer` / `BlueyConnection` / scanner.
- `bluey/test/bluey/factory_state_check_test.dart` — unit tests for factory state pre-checks.

### Files modified — domain
- `bluey/lib/src/shared/exceptions.dart` — add `StaleHandleException` (or split into its own file).
- `bluey/lib/src/bluey.dart` — add `_requireAdapterOn()` helper; pre-check in `server()`, `connect()`, `scanner()`; **remove `ensureReady()`**.
- `bluey/lib/src/gatt_server/bluey_server.dart` — add invalidation primitive.
- `bluey/lib/src/connection/bluey_connection.dart` — add invalidation primitive.
- `bluey/lib/src/discovery/bluey_scanner.dart` — add invalidation primitive.

### Files modified — platform implementations
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt` — translate `DeadObjectException` to `bluetooth-unavailable`.
- `bluey_ios/ios/Classes/CentralManagerImpl.swift` — pre-check `state` at top of each GATT op (~10 sites).
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift` — same.

### Files modified — tests
- `bluey/test/bluey_test.dart` — delete `ensureReady` test group.
- Migration sweep: any test that constructs `Bluey.server()` / `bluey.connect(...)` / `bluey.scanner()` against a `FakeBlueyPlatform` whose initial state isn't `on` must either pin to `on` or assert the new throw.

### Files modified — example app
- `bluey/example/lib/...` — any call site to `ensureReady` migrated. (Audit during Phase 3.)

### Files modified — backlog
- `docs/backlog/I333-bluetooth-adapter-state-not-observed.md` — set `status: fixed`.

---

### Task 1: `StaleHandleException` value object

**Files:**
- Modify: `bluey/lib/src/shared/exceptions.dart` (append the new exception alongside the existing `BluetoothUnavailableException`, `BluetoothDisabledException`, `PermissionDeniedException`)
- Create: `bluey/test/connection/stale_handle_exception_test.dart`

- [ ] **Step 1.1: Write the failing tests**

Create `bluey/test/connection/stale_handle_exception_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    show BluetoothState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaleHandleException', () {
    test('extends BlueyException', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.off,
        instanceType: 'Server',
      );

      expect(exception, isA<BlueyException>());
    });

    test('carries triggeringState and instanceType', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.unauthorized,
        instanceType: 'Connection',
      );

      expect(exception.triggeringState, equals(BluetoothState.unauthorized));
      expect(exception.instanceType, equals('Connection'));
    });

    test('message identifies the instance type and triggering state', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.off,
        instanceType: 'Server',
      );

      expect(exception.message, contains('Server'));
      expect(exception.message, contains('off'));
    });

    test('action guides the caller to construct fresh', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.off,
        instanceType: 'Connection',
      );

      expect(exception.action, contains('fresh'));
    });
  });
}
```

- [ ] **Step 1.2: Run test to verify it fails**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/connection/stale_handle_exception_test.dart`
Expected: FAIL with "StaleHandleException isn't defined".

- [ ] **Step 1.3: Add the exception class**

Modify `bluey/lib/src/shared/exceptions.dart`. After the existing `PermissionDeniedException` block (around line 46), add:

```dart
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
///   await server!.addService(...);
/// }
/// ```
///
/// [triggeringState] is the adapter state that caused invalidation.
/// It does **not** reflect the adapter's current state, which may have
/// returned to [BluetoothState.on] since invalidation.
class StaleHandleException extends BlueyException {
  /// The adapter state that caused this instance to be invalidated.
  final BluetoothState triggeringState;

  /// The instance type that was invalidated, e.g. `'Server'`,
  /// `'Connection'`, `'Scanner'`. Used for diagnostics.
  final String instanceType;

  StaleHandleException({
    required this.triggeringState,
    required this.instanceType,
  }) : super(
          '$instanceType was invalidated by adapter transition to '
          '${triggeringState.name}; the instance is dead even if the '
          'adapter has since returned to BluetoothState.on.',
          action:
              'Construct a fresh $instanceType from Bluey rather than '
              'reusing this one.',
        );
}
```

Note: `BluetoothState` is exported from `package:bluey/bluey.dart` (via the platform-interface re-export). If the import is missing in `exceptions.dart`, add at the top:

```dart
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    show BluetoothState;
```

- [ ] **Step 1.4: Run test to verify it passes**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/connection/stale_handle_exception_test.dart`
Expected: PASS — all 4 tests green.

- [ ] **Step 1.5: Workspace verification**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 1.6: Commit**

```bash
git add bluey/lib/src/shared/exceptions.dart bluey/test/connection/stale_handle_exception_test.dart
git commit -m "$(cat <<'EOF'
I333: add StaleHandleException value object

Thrown when a Server/Connection/Scanner is used after being
invalidated by an adapter-state transition. Carries the triggering
state and instance type for diagnostics. Subsequent commits add the
invalidation primitive that throws it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Factory pre-checks on `Bluey.server()`, `Bluey.connect()`, `Bluey.scanner()`

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Create: `bluey/test/bluey/factory_state_check_test.dart`

Add a `_requireAdapterOn()` helper to `Bluey` and call it at the top of each factory. Helper maps current state (using the cached `_currentState` to stay synchronous) to a typed exception.

- [ ] **Step 2.1: Write the failing tests**

Create directory + file `bluey/test/bluey/factory_state_check_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Bluey.server() factory pre-checks adapter state', () {
    test('throws BluetoothDisabledException when state is off', () {
      fakePlatform.setState(platform.BluetoothState.off);

      expect(() => bluey.server(), throwsA(isA<BluetoothDisabledException>()));
    });

    test('throws PermissionDeniedException when state is unauthorized', () {
      fakePlatform.setState(platform.BluetoothState.unauthorized);

      expect(
        () => bluey.server(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('throws BluetoothUnavailableException when state is unsupported', () {
      fakePlatform.setState(platform.BluetoothState.unsupported);

      expect(
        () => bluey.server(),
        throwsA(isA<BluetoothUnavailableException>()),
      );
    });

    test('throws BluetoothUnavailableException when state is unknown', () {
      fakePlatform.setState(platform.BluetoothState.unknown);

      expect(
        () => bluey.server(),
        throwsA(isA<BluetoothUnavailableException>()),
      );
    });

    test('returns a Server when state is on', () async {
      fakePlatform.setState(platform.BluetoothState.on);
      // Allow the state subscription to flush.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final server = bluey.server();
      expect(server, isNotNull);
    });
  });

  group('Bluey.scanner() factory pre-checks adapter state', () {
    test('throws BluetoothDisabledException when state is off', () {
      fakePlatform.setState(platform.BluetoothState.off);

      expect(() => bluey.scanner(), throwsA(isA<BluetoothDisabledException>()));
    });

    test('returns a Scanner when state is on', () async {
      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final scanner = bluey.scanner();
      expect(scanner, isNotNull);
    });
  });

  group('Bluey.connect() factory pre-checks adapter state', () {
    test('throws BluetoothDisabledException when state is off', () async {
      fakePlatform.setState(platform.BluetoothState.off);
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Test',
      );

      await expectLater(
        bluey.connect(device),
        throwsA(isA<BluetoothDisabledException>()),
      );
    });
  });
}
```

> Note: `FakeBlueyPlatform.setState(...)` must update the cached state *and* emit on `stateStream`. Verify the fake supports this; if not, extend it in Step 2.3 (the fake source is at `bluey/test/fakes/fake_platform.dart`).

- [ ] **Step 2.2: Run test to verify it fails**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/bluey/factory_state_check_test.dart`
Expected: most tests FAIL — the factories don't throw today.

- [ ] **Step 2.3: Verify `FakeBlueyPlatform.setState` exists and emits on `stateStream`**

Open `bluey/test/fakes/fake_platform.dart`. Find any existing state-setting method. The fake likely has either:

- A field `BluetoothState _state` with a setter that pushes onto `_stateController`, OR
- A method `setState(BluetoothState s)` already present.

If the method doesn't exist, add it:

```dart
/// Test seam — update the simulated adapter state and broadcast.
void setState(BluetoothState state) {
  _state = state;
  _stateController.add(state);
}
```

(Place near the existing `bool _state = BluetoothState.on;` field declaration / `stateStream` getter.)

- [ ] **Step 2.4: Add `_requireAdapterOn()` helper**

Modify `bluey/lib/src/bluey.dart`. Around line 293 (just after the existing `ensureReady` method — `ensureReady` is removed in Task 3, so for now leave it in place), add:

```dart
  /// Throws a state-mapped exception if the adapter is not currently
  /// in [BluetoothState.on]. Called by every factory method on this
  /// class before construction.
  ///
  /// Uses the cached [currentState] (not [state]) so the check is
  /// synchronous — the cached value is kept fresh by the live
  /// subscription to `_platform.stateStream` established in the
  /// constructor.
  void _requireAdapterOn(String operation) {
    switch (_currentState) {
      case BluetoothState.on:
        return;
      case BluetoothState.off:
        throw const BluetoothDisabledException();
      case BluetoothState.unauthorized:
        throw PermissionDeniedException(const ['Bluetooth']);
      case BluetoothState.unsupported:
      case BluetoothState.unknown:
        throw const BluetoothUnavailableException();
    }
  }
```

- [ ] **Step 2.5: Add pre-checks to `server()`, `connect()`, `scanner()`**

In the same file, at the top of each factory body, add `_requireAdapterOn('factoryName')`:

```dart
  Scanner scanner() {
    _requireAdapterOn('scanner');
    return BlueyScanner(_platform, _eventBus);
  }

  Future<Connection> connect(Device device, {Duration? timeout}) async {
    _requireAdapterOn('connect');
    // ... existing body
  }

  Server? server({Duration? lifecycleInterval = const Duration(seconds: 10)}) {
    _requireAdapterOn('server');
    if (!_platform.capabilities.canAdvertise) {
      return null;
    }
    // ... existing body
  }
```

(Inspect the existing factories and place the helper call as the very first statement. For `server()`, the `_requireAdapterOn` call must precede the `canAdvertise` check.)

- [ ] **Step 2.6: Run tests to verify they pass**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/bluey/factory_state_check_test.dart`
Expected: all tests PASS.

- [ ] **Step 2.7: Workspace verification**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!`

Also run the full bluey suite to check for fallout — tests that previously called factories against non-`on` `FakeBlueyPlatform` will now throw:

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test 2>&1 | tail -20`
Expected: most pass. If some fail, they are tests that need `fakePlatform.setState(BluetoothState.on)` in their `setUp` (the default for `FakeBlueyPlatform` is already `on`, so this should be rare — but the audit is mandatory).

If fallout is found, fix each test by ensuring `setState(BluetoothState.on)` is called in `setUp` (or that the default is `on`). Do not weaken the production code.

- [ ] **Step 2.8: Commit**

```bash
git add bluey/lib/src/bluey.dart \
        bluey/test/bluey/factory_state_check_test.dart \
        bluey/test/fakes/fake_platform.dart
git commit -m "$(cat <<'EOF'
I333: factory methods on Bluey pre-check adapter state

Bluey.server(), Bluey.connect(), and Bluey.scanner() each call
_requireAdapterOn() at entry and throw the typed state-mapped
exception (BluetoothDisabledException / PermissionDeniedException /
BluetoothUnavailableException) before any construction. Pairs with
the per-instance invalidation primitive that lands in subsequent
commits for mid-life state transitions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Remove `Bluey.ensureReady()` + migrate callers

**Files:**
- Modify: `bluey/lib/src/bluey.dart` — delete the `ensureReady` method.
- Modify: `bluey/test/bluey_test.dart` — delete the `ensureReady` test group.
- Audit: any other `ensureReady` callers (production code, example app).

- [ ] **Step 3.1: Audit all `ensureReady` call sites**

Run: `grep -rn "ensureReady" /Users/joel/git/neutrinographics/bluey --include="*.dart"`

Expected matches (as of plan-writing):
- `bluey/lib/src/bluey.dart` — the definition itself.
- `bluey/test/bluey_test.dart:367–407` — a test group covering `ensureReady`.

If the grep surfaces additional matches in production code or the example app, each needs migration:
- **Preamble to a factory call** → delete the `ensureReady` call; the factory now throws.
- **State-only probe** → replace with `bluey.currentState != BluetoothState.on` (sync) or `await bluey.state != BluetoothState.on` (async).

- [ ] **Step 3.2: Delete the `ensureReady` test group**

Open `bluey/test/bluey_test.dart`. Find `group('ensureReady', () {` (around line 367) and delete the entire group including the closing `});` (around line 410).

- [ ] **Step 3.3: Delete the `ensureReady` method**

In `bluey/lib/src/bluey.dart`, delete lines 271–293 (the doc comment and the method body of `ensureReady`).

- [ ] **Step 3.4: Verify the workspace compiles**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!` If any errors mention `ensureReady`, the audit in Step 3.1 missed a call site — fix it.

- [ ] **Step 3.5: Run the full bluey suite**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test`
Expected: all tests pass (the `ensureReady` group was deleted; other tests are unaffected).

- [ ] **Step 3.6: Commit**

```bash
git add bluey/lib/src/bluey.dart bluey/test/bluey_test.dart
git commit -m "$(cat <<'EOF'
I333: remove Bluey.ensureReady()

Redundant after factory pre-checks: each typed exception ensureReady
could throw is now thrown by the factory that actually constructs the
instance. Non-throwing state probes are served by bluey.currentState
(sync cached) and bluey.state (async fresh).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Invalidation primitive on `BlueyServer`

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`
- Modify: `bluey/test/bluey_server_test.dart` — add invalidation test group.

- [ ] **Step 4.1: Write the failing tests**

In `bluey/test/bluey_server_test.dart`, add a new `group('I333 — adapter-state invalidation', () { ... });` after an existing top-level group. The group's tests need to pin the fake to Android caps:

```dart
group('I333 — adapter-state invalidation', () {
  test('invalidates on stateStream emitting off', () async {
    final server = bluey.server()!;

    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(
      () => server.addService(
        HostedService(uuid: UUID.short(0x180D), characteristics: const []),
      ),
      throwsA(isA<StaleHandleException>()),
    );
  });

  test('invalidates on stateStream emitting unauthorized', () async {
    final server = bluey.server()!;

    fakePlatform.setState(platform.BluetoothState.unauthorized);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(
      () => server.startAdvertising(),
      throwsA(isA<StaleHandleException>()),
    );
  });

  test('does not invalidate on stateStream emitting on', () async {
    final server = bluey.server()!;

    fakePlatform.setState(platform.BluetoothState.on);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Should not throw — adding a service against a still-valid server
    // is the success path.
    await expectLater(
      server.addService(
        HostedService(uuid: UUID.short(0x180D), characteristics: const []),
      ),
      completes,
    );
  });

  test('stays invalidated after adapter returns to on', () async {
    final server = bluey.server()!;

    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    fakePlatform.setState(platform.BluetoothState.on);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // Even though the adapter is `on` again, the old server stays dead.
    expect(
      () => server.startAdvertising(),
      throwsA(isA<StaleHandleException>()),
    );
  });

  test('triggeringState reflects the state that caused invalidation', () async {
    final server = bluey.server()!;

    fakePlatform.setState(platform.BluetoothState.unauthorized);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    try {
      await server.startAdvertising();
      fail('expected StaleHandleException');
    } on StaleHandleException catch (e) {
      expect(e.triggeringState, equals(platform.BluetoothState.unauthorized));
      expect(e.instanceType, equals('Server'));
    }
  });

  test('connections stream closes on invalidation', () async {
    final server = bluey.server()!;
    final connectionsClosed = Completer<void>();

    server.connections.listen(
      (_) {},
      onDone: connectionsClosed.complete,
    );

    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(connectionsClosed.isCompleted, isTrue);
  });
});
```

Imports likely needed at the top of the test file (add only those missing): `import 'dart:async';`.

- [ ] **Step 4.2: Run tests to verify they fail**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/bluey_server_test.dart --name "I333"`
Expected: tests FAIL — `BlueyServer` has no invalidation primitive yet.

- [ ] **Step 4.3: Add the invalidation primitive to `BlueyServer`**

Open `bluey/lib/src/gatt_server/bluey_server.dart`. Find the constructor and class body.

Add fields to the class (near the other private fields):

```dart
  bool _invalidated = false;
  BluetoothState? _invalidationState;
  StreamSubscription<BluetoothState>? _stateSubscription;
```

(Import `dart:async` and `package:bluey_platform_interface/bluey_platform_interface.dart` show `BluetoothState` if not already imported.)

In the constructor body, after existing initialization, subscribe to stateStream:

```dart
    _stateSubscription = _platform.stateStream.listen((state) {
      if (state != BluetoothState.on) {
        _invalidate(state);
      }
    });
```

Add the `_invalidate` and `_ensureValid` methods to the class:

```dart
  /// Marks this server as terminal-failed. Idempotent — re-entry is a
  /// no-op. Cancels the state subscription, closes owned streams, and
  /// fails subsequent calls with [StaleHandleException].
  void _invalidate(BluetoothState triggeringState) {
    if (_invalidated) return;
    _invalidated = true;
    _invalidationState = triggeringState;
    _stateSubscription?.cancel();
    _stateSubscription = null;

    // Close every StreamController owned by this server. (Names below
    // are illustrative — match the actual field names in the class.)
    _connectionsController.close();
    _disconnectionsController.close();
    _peerConnectionsController.close();
    _readRequestsController.close();
    _writeRequestsController.close();

    // Clear cached state — connected clients are gone with the adapter.
    _connectedClients.clear();
    _identifiedPeerClientIds.clear();
  }

  /// Throws [StaleHandleException] if this server has been invalidated
  /// by a prior adapter-state transition.
  void _ensureValid() {
    if (_invalidated) {
      throw StaleHandleException(
        triggeringState: _invalidationState!,
        instanceType: 'Server',
      );
    }
  }
```

(Cross-reference the actual fields in `BlueyServer` — the existing constructor will have a `_connectionsController`, `_peerConnectionsController`, etc. Close every one you find that the server owns. Do not close ones owned by other classes.)

- [ ] **Step 4.4: Gate every public method with `_ensureValid()`**

Find every public method on `BlueyServer` (those that override the `Server` interface). At the top of each method body, add `_ensureValid();` as the first statement. Methods to gate:

- `addService(HostedService service)`
- `removeService(UUID uuid)`
- `startAdvertising({...})`
- `stopAdvertising()`
- `notifyCharacteristic(...)` / `notifyCharacteristicTo(...)` / `indicateCharacteristic(...)` / `indicateCharacteristicTo(...)`
- `respondToReadRequest(...)` / `respondToWriteRequest(...)`
- `disconnectClient(...)`
- `isClientConnected(String address)` (from I325)
- Any other public method on the `Server` interface.

Also gate every public **getter** that returns dynamic state (not the `serverId` constant):

- `connectedClients`
- `isAdvertising`

Don't gate stream getters (`connections`, `disconnections`, etc.) — those streams are already closed by `_invalidate`.

- [ ] **Step 4.5: Run tests to verify they pass**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/bluey_server_test.dart`
Expected: all tests pass, including the new I333 group.

- [ ] **Step 4.6: Workspace verification**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!`

Run the full bluey suite: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test`
Expected: all green.

- [ ] **Step 4.7: Commit**

```bash
git add bluey/lib/src/gatt_server/bluey_server.dart bluey/test/bluey_server_test.dart
git commit -m "$(cat <<'EOF'
I333: invalidate BlueyServer on non-on adapter state

BlueyServer subscribes to platform.stateStream at construction. On
any non-on emission, the server is terminal-failed: owned streams
close, caches clear, the subscription cancels, and every public
method throws StaleHandleException with the triggering state.
Invalidation is idempotent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Invalidation primitive on `BlueyConnection`

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`
- Modify: `bluey/test/connection/bluey_connection_state_gating_test.dart` — add invalidation tests next to the existing disconnect-gating tests.

Mirrors Task 4 for `BlueyConnection`. Same pattern: subscription at construction, idempotent `_invalidate`, `_ensureValid` at every public method.

- [ ] **Step 5.1: Write the failing tests**

In `bluey/test/connection/bluey_connection_state_gating_test.dart`, add a new group after the existing `BlueyConnection state gating (I002)` group:

```dart
group('I333 — adapter-state invalidation', () {
  test('invalidates on stateStream emitting off', () async {
    final ctx = await establishWithChar();

    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await expectLater(
      ctx.connection.maxWritePayload(withResponse: false),
      throwsA(isA<StaleHandleException>()),
    );
  });

  test('invalidates on stateStream emitting unauthorized', () async {
    final ctx = await establishWithChar();

    fakePlatform.setState(platform.BluetoothState.unauthorized);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await expectLater(
      ctx.char.read(),
      throwsA(isA<StaleHandleException>()),
    );
  });

  test('stays invalidated after adapter returns to on', () async {
    final ctx = await establishWithChar();

    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    fakePlatform.setState(platform.BluetoothState.on);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await expectLater(
      ctx.connection.services(),
      throwsA(isA<StaleHandleException>()),
    );
  });

  test('stateChanges stream closes on invalidation', () async {
    final ctx = await establishWithChar();
    final stateClosed = Completer<void>();

    ctx.connection.stateChanges.listen(
      (_) {},
      onDone: stateClosed.complete,
    );

    fakePlatform.setState(platform.BluetoothState.off);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(stateClosed.isCompleted, isTrue);
  });
});
```

- [ ] **Step 5.2: Run tests to verify they fail**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/connection/bluey_connection_state_gating_test.dart --name "I333"`
Expected: FAIL.

- [ ] **Step 5.3: Add invalidation primitive to `BlueyConnection`**

Open `bluey/lib/src/connection/bluey_connection.dart`.

Add fields (near other private fields):

```dart
  bool _invalidated = false;
  BluetoothState? _invalidationState;
  StreamSubscription<BluetoothState>? _stateSubscriptionForInvalidation;
```

(Distinct from any existing `_stateSubscription` for connection state — read the file to avoid name collision.)

In the constructor body:

```dart
    _stateSubscriptionForInvalidation = _platform.stateStream.listen((state) {
      if (state != BluetoothState.on) {
        _invalidate(state);
      }
    });
```

Add the methods:

```dart
  void _invalidate(BluetoothState triggeringState) {
    if (_invalidated) return;
    _invalidated = true;
    _invalidationState = triggeringState;
    _stateSubscriptionForInvalidation?.cancel();
    _stateSubscriptionForInvalidation = null;

    // Close owned streams. Match the actual controller field names in the file.
    _stateController.close();
    _servicesChangesController.close();
    _bondStateController.close();
    _phyController.close();

    // Clear cached state.
    _cachedServices = null;
  }

  void _ensureValid() {
    if (_invalidated) {
      throw StaleHandleException(
        triggeringState: _invalidationState!,
        instanceType: 'Connection',
      );
    }
  }
```

- [ ] **Step 5.4: Gate every public method on `BlueyConnection` with `_ensureValid()`**

Every public method that does platform work must call `_ensureValid()` first. The list (cross-reference the `Connection` abstract interface in `connection.dart`):

- `services({bool cache = false})`
- `hasService(UUID uuid)`
- `service(UUID uuid)` (synchronous, but still gate it)
- `readRssi()`
- `maxWritePayload({required bool withResponse})`
- `disconnect()` — gate but allow it to fail silently if already invalidated (an invalidated connection is effectively disconnected).
- Each method on the `_AndroidConnectionExtensionsImpl` class (the existing pattern from I325 already gates each one on a capability flag — also gate on `_ensureValid()` via the wrapped `_conn`).

For the Android-extension class, add at the top of each method:

```dart
  @override
  Mtu get mtu {
    _conn._ensureValid();
    // ... existing
  }
```

Apply consistently to `requestMtu`, `bond`, `bondState`, `bondStateChanges`, `txPhy`, `rxPhy`, `phyChanges`, `requestPhy`, `connectionParameters`, `requestConnectionParameters`, `removeBond`.

- [ ] **Step 5.5: Run tests to verify they pass**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/connection/bluey_connection_state_gating_test.dart`
Expected: PASS (including the new I333 group).

- [ ] **Step 5.6: Run the full bluey suite**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test`
Expected: all tests pass.

If any tests fail with `StaleHandleException` when not expected, the test is constructing a connection against a `FakeBlueyPlatform` whose state isn't `on`. Pin the state in `setUp` with `fakePlatform.setState(BluetoothState.on)`.

- [ ] **Step 5.7: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/bluey_connection_state_gating_test.dart
git commit -m "$(cat <<'EOF'
I333: invalidate BlueyConnection on non-on adapter state

Same pattern as BlueyServer (Task 4): subscription at construction,
idempotent _invalidate, _ensureValid at every public method on
both BlueyConnection and _AndroidConnectionExtensionsImpl. Owned
streams close (stateChanges, servicesChanges, bondStateChanges,
phyChanges) and the services cache clears. Calls on an invalidated
connection throw StaleHandleException(instanceType: 'Connection').

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Invalidation primitive on `BlueyScanner`

**Files:**
- Modify: `bluey/lib/src/discovery/bluey_scanner.dart`
- Modify or create: `bluey/test/discovery/bluey_scanner_invalidation_test.dart`

`BlueyScanner` is simpler — its only operation is `scan()`. Invalidation closes the active scan stream (if any) and makes subsequent `scan()` calls throw.

- [ ] **Step 6.1: Write the failing tests**

Create `bluey/test/discovery/bluey_scanner_invalidation_test.dart`:

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

  setUp(() {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Scanner adapter-state invalidation', () {
    test('subsequent scan() throws StaleHandleException after off', () async {
      final scanner = bluey.scanner();

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        () => scanner.scan(),
        throwsA(isA<StaleHandleException>()),
      );
    });

    test('active scan stream closes on invalidation', () async {
      final scanner = bluey.scanner();
      final scanClosed = Completer<void>();

      scanner.scan().listen(
        (_) {},
        onDone: scanClosed.complete,
      );

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(scanClosed.isCompleted, isTrue);
    });

    test('stays invalidated after adapter returns to on', () async {
      final scanner = bluey.scanner();

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        () => scanner.scan(),
        throwsA(isA<StaleHandleException>()),
      );
    });
  });
}
```

- [ ] **Step 6.2: Run to verify failure**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/discovery/bluey_scanner_invalidation_test.dart`
Expected: FAIL.

- [ ] **Step 6.3: Add invalidation primitive to `BlueyScanner`**

Open `bluey/lib/src/discovery/bluey_scanner.dart`. Read the class (it should be small — ~50 lines).

Add fields, constructor subscription, `_invalidate`, `_ensureValid`. Also track the active scan controller (if any) so it can be closed on invalidation.

Pattern (adapt to the actual structure in the file):

```dart
class BlueyScanner implements Scanner {
  final platform.BlueyPlatform _platform;
  final EventBus _eventBus;

  bool _invalidated = false;
  BluetoothState? _invalidationState;
  StreamSubscription<BluetoothState>? _stateSubscription;
  StreamController<ScanResult>? _activeScanController;

  BlueyScanner(this._platform, this._eventBus) {
    _stateSubscription = _platform.stateStream.listen((state) {
      if (state != BluetoothState.on) {
        _invalidate(state);
      }
    });
  }

  @override
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    _ensureValid();
    // ... existing scan logic, but route through a StreamController owned
    // by this scanner so it can be closed on invalidation.
    _activeScanController = StreamController<ScanResult>.broadcast();
    // ... wire up the existing platform.scan(...) listening into the controller.
    return _activeScanController!.stream;
  }

  void _invalidate(BluetoothState triggeringState) {
    if (_invalidated) return;
    _invalidated = true;
    _invalidationState = triggeringState;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _activeScanController?.close();
    _activeScanController = null;
  }

  void _ensureValid() {
    if (_invalidated) {
      throw StaleHandleException(
        triggeringState: _invalidationState!,
        instanceType: 'Scanner',
      );
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _activeScanController?.close();
    // ... existing dispose logic
  }
}
```

> Note: read the existing `scan()` implementation carefully. The current implementation may use `_platform.scan(...).pipe(...)` or similar; adapt to route through an owned `StreamController` only if the current shape doesn't already let you close the stream cleanly on invalidation. If the existing shape closes naturally (e.g. the underlying `_platform.scan(...)` stream terminates when the platform stops), simpler approach: cancel the subscription to `_platform.scan(...)` inside `_invalidate`.

- [ ] **Step 6.4: Run tests to verify they pass**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/discovery/bluey_scanner_invalidation_test.dart`
Expected: PASS.

- [ ] **Step 6.5: Workspace verification**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!`

Run full bluey suite: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test`
Expected: all green.

- [ ] **Step 6.6: Commit**

```bash
git add bluey/lib/src/discovery/bluey_scanner.dart \
        bluey/test/discovery/bluey_scanner_invalidation_test.dart
git commit -m "$(cat <<'EOF'
I333: invalidate BlueyScanner on non-on adapter state

Scanner subscribes to platform.stateStream at construction. On any
non-on emission, the active scan stream closes and subsequent scan()
calls throw StaleHandleException(instanceType: 'Scanner').

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Translate `DeadObjectException` → `bluetooth-unavailable` on Android

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`

- [ ] **Step 7.1: Read existing translation table**

Open `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`. Find the function that translates `Throwable` to `FlutterError`. Typical pattern:

```kotlin
fun translateError(e: Throwable): FlutterError {
    return when (e) {
        is BlueyAndroidError.DeviceNotConnected -> FlutterError("gatt-disconnected", ...)
        is BlueyAndroidError.NoQueueForConnection -> FlutterError("gatt-disconnected", ...)
        // ...
        else -> FlutterError("bluey-unknown", e.message ?: "Unknown error", null)
    }
}
```

- [ ] **Step 7.2: Add a `DeadObjectException` arm**

Add `import android.os.DeadObjectException` at the top of the file if not already present.

In the `when` block, before the catch-all `else`, add:

```kotlin
        is DeadObjectException -> FlutterError(
            "bluetooth-unavailable",
            "Bluetooth adapter is unavailable: ${e.message ?: "remote object is dead"}",
            null
        )
```

The `bluetooth-unavailable` Pigeon code already exists and translates Dart-side to `BluetoothUnavailableException` via `withErrorTranslation`. Verify by grepping:

```bash
grep -n "bluetooth-unavailable" /Users/joel/git/neutrinographics/bluey/bluey_platform_interface/lib/src/exceptions.dart \
                                /Users/joel/git/neutrinographics/bluey/bluey/lib/src/shared/error_translation.dart
```

If it doesn't exist, add the case to the Dart-side translator (which maps platform error codes to typed exceptions). Look at the existing `gatt-disconnected` → `GattOperationDisconnectedException` translation as a reference.

- [ ] **Step 7.3: Run Android tests**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test`
Expected: all pass.

There may not be a direct unit test for `DeadObjectException` translation (it's hard to simulate without a real Binder). Acceptable to verify by code inspection + the existing translation table tests.

- [ ] **Step 7.4: Workspace verification**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7.5: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt
# If error_translation.dart was modified, add it too.
git commit -m "$(cat <<'EOF'
I333: translate Android DeadObjectException to bluetooth-unavailable

Backstop for the race where a GATT op is in flight when the adapter
dies (the per-instance invalidation primitive may not have fired
yet). Surfaces to Dart as BluetoothUnavailableException via the
existing translation chain.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: iOS state pre-check at GATT op entry

**Files:**
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift`
- Modify: `bluey_ios/ios/Classes/PeripheralManagerImpl.swift`

Each GATT op handler checks `centralManager.state != .poweredOn` (or `peripheralManager.state != .poweredOn`) at the top and short-circuits with `BlueyError.notReady.toClientPigeonError()`.

- [ ] **Step 8.1: Audit the GATT op handlers**

Run: `grep -n "func.*completion: @escaping" /Users/joel/git/neutrinographics/bluey/bluey_ios/ios/Classes/CentralManagerImpl.swift`

Expected ~7 functions matching: `connect`, `disconnect`, `discoverServices`, `readCharacteristic`, `writeCharacteristic`, `setNotification`, `readDescriptor`, `writeDescriptor`, `readRssi`.

Also: `getMaximumWriteLength` which is synchronous and throws (from I325).

- [ ] **Step 8.2: Add a `requireReady()` helper**

In `CentralManagerImpl.swift`, near the top of the class, add:

```swift
    /// Throws `BlueyError.notReady.toClientPigeonError()` (Pigeon code
    /// `bluetooth-unavailable`) if the central manager is not powered on.
    /// Use as the first call in every GATT operation handler.
    private func requireReady() throws {
        guard centralManager.state == .poweredOn else {
            throw BlueyError.notReady.toClientPigeonError()
        }
    }
```

- [ ] **Step 8.3: Gate every GATT op handler**

For each async function (using completion handlers), add at the top:

```swift
    func readCharacteristic(deviceId: String, ..., completion: @escaping (Result<..., Error>) -> Void) {
        guard centralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toClientPigeonError()))
            return
        }
        // ... existing logic
    }
```

For synchronous throwing functions:

```swift
    func getMaximumWriteLength(deviceId: String, withResponse: Bool) throws -> Int64 {
        try requireReady()
        // ... existing logic
    }
```

Apply to: every public function on `CentralManagerImpl` that does CoreBluetooth work. Methods that don't touch CoreBluetooth (e.g. pure state queries on internal Swift maps) don't need the gate.

- [ ] **Step 8.4: Mirror on `PeripheralManagerImpl.swift`**

Same pattern: add `requireReady()` helper, gate every GATT op handler.

- [ ] **Step 8.5: Verify Pigeon error code**

The `BlueyError.notReady.toClientPigeonError()` exists in `bluey_ios/ios/Classes/BlueyError.swift`. Verify it maps to the `bluetooth-unavailable` Pigeon code (mirror of Android's translation):

```bash
grep -n "notReady\|bluetooth-unavailable" /Users/joel/git/neutrinographics/bluey/bluey_ios/ios/Classes/BlueyError.swift
```

If `notReady` doesn't map to `bluetooth-unavailable`, add the case to `toClientPigeonError()` so the iOS path mirrors Android end-to-end.

- [ ] **Step 8.6: Workspace verification**

Run: `cd /Users/joel/git/neutrinographics/bluey && flutter analyze`
Expected: `No issues found!`

Run the iOS package tests:

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_ios && flutter test
```

Expected: all pass (most iOS unit tests don't exercise CoreBluetooth — they're Pigeon contract tests).

- [ ] **Step 8.7: Commit**

```bash
git add bluey_ios/ios/Classes/CentralManagerImpl.swift \
        bluey_ios/ios/Classes/PeripheralManagerImpl.swift
# If BlueyError.swift was modified for the notReady → bluetooth-unavailable
# mapping, include it.
git commit -m "$(cat <<'EOF'
I333: iOS GATT op handlers pre-check state, fail with notReady

Each public op on CentralManagerImpl and PeripheralManagerImpl
checks centralManager.state / peripheralManager.state at the top
and short-circuits with BlueyError.notReady.toClientPigeonError().
Closes the symmetric race window to Android's DeadObjectException
translation (Task 7) — iOS calls against a .poweredOff manager
silently no-op, so the pre-check is necessary to surface a typed
BluetoothUnavailableException Dart-side.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Integration test — full adapter cycle scenarios

**Files:**
- Create: `bluey/test/connection/adapter_state_invalidation_test.dart`

End-to-end scenarios exercising all three instance types through a single adapter cycle.

- [ ] **Step 9.1: Write the integration tests**

Create `bluey/test/connection/adapter_state_invalidation_test.dart`:

```dart
import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  Device deviceFor(String address) => Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: address,
        name: 'Test',
      );

  setUp(() {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
    fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Full adapter-cycle scenarios', () {
    test('Server: alive → off → stale → fresh after on', () async {
      final firstServer = bluey.server()!;
      await firstServer.addService(
        HostedService(uuid: UUID.short(0x180D), characteristics: const []),
      );

      // Adapter cycles off.
      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Old server is dead.
      expect(
        () => firstServer.startAdvertising(),
        throwsA(isA<StaleHandleException>()),
      );

      // Adapter comes back on.
      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Old server stays dead.
      expect(
        () => firstServer.startAdvertising(),
        throwsA(isA<StaleHandleException>()),
      );

      // Fresh server works.
      final secondServer = bluey.server()!;
      await expectLater(
        secondServer.addService(
          HostedService(uuid: UUID.short(0x180D), characteristics: const []),
        ),
        completes,
      );
    });

    test('Connection: alive → off → stale → fresh after on', () async {
      final firstConnection = await bluey.connect(deviceFor(TestDeviceIds.device1));

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await expectLater(
        firstConnection.services(),
        throwsA(isA<StaleHandleException>()),
      );

      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await expectLater(
        firstConnection.services(),
        throwsA(isA<StaleHandleException>()),
      );

      final secondConnection = await bluey.connect(deviceFor(TestDeviceIds.device1));
      await expectLater(secondConnection.services(), completes);
    });

    test('Scanner: alive → off → stale → fresh after on', () async {
      final firstScanner = bluey.scanner();

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        () => firstScanner.scan(),
        throwsA(isA<StaleHandleException>()),
      );

      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        () => firstScanner.scan(),
        throwsA(isA<StaleHandleException>()),
      );

      final secondScanner = bluey.scanner();
      // scan() returns a stream, not a Future — just verify it can be called.
      final stream = secondScanner.scan();
      expect(stream, isA<Stream<ScanResult>>());
    });
  });
}
```

- [ ] **Step 9.2: Run integration tests**

Run: `cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test test/connection/adapter_state_invalidation_test.dart`
Expected: all 3 tests pass.

- [ ] **Step 9.3: Run the entire workspace**

```bash
cd /Users/joel/git/neutrinographics/bluey && flutter analyze
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey_platform_interface && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test
cd /Users/joel/git/neutrinographics/bluey/bluey/example && flutter test
```

Expected: all green across all packages.

- [ ] **Step 9.4: Commit**

```bash
git add bluey/test/connection/adapter_state_invalidation_test.dart
git commit -m "$(cat <<'EOF'
I333: integration tests for full adapter-cycle scenarios

For each of Server, Connection, Scanner: assert alive → off → stale
→ stays stale even after on → fresh instance from Bluey works.
Verifies the end-to-end consumer pattern (catch StaleHandleException,
re-construct).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Mark I333 fixed in backlog

**Files:**
- Modify: `docs/backlog/I333-bluetooth-adapter-state-not-observed.md`

- [ ] **Step 10.1: Update frontmatter and add resolution section**

Open `docs/backlog/I333-bluetooth-adapter-state-not-observed.md`. Change `status: open` to `status: fixed`. After the frontmatter, before the existing "What's already in place" section, insert:

```markdown
## Resolution (2026-05-06)

Landed on branch `feature/i333-adapter-state-invalidation` per:
- Spec: `docs/superpowers/specs/2026-05-06-adapter-state-invalidation-design.md`
- Plan: `docs/superpowers/plans/2026-05-06-adapter-state-invalidation.md`

Five coordinated changes:

- **`StaleHandleException`** value object in `bluey/lib/src/shared/exceptions.dart`. Carries `triggeringState` and `instanceType` for diagnostics.
- **Factory pre-checks** on `Bluey.server()` / `Bluey.connect()` / `Bluey.scanner()`. Each calls `_requireAdapterOn(...)` and throws the state-mapped exception (`BluetoothDisabledException` / `PermissionDeniedException` / `BluetoothUnavailableException`) synchronously before any construction.
- **Removed `Bluey.ensureReady()`** — redundant once factories pre-check. Non-throwing probes (`currentState`, `state`) still available.
- **Per-instance invalidation** on `BlueyServer`, `BlueyConnection`, and `BlueyScanner`. Each subscribes to `_platform.stateStream` at construction; on non-`on` emission, the instance is terminal-failed (streams close, caches clear, subscription cancels, in-flight ops fail) and subsequent calls throw `StaleHandleException`.
- **Race backstop**: Android's `DeadObjectException` and iOS's `.poweredOff` op-entry pre-checks both surface as `bluetooth-unavailable` → `BluetoothUnavailableException` Dart-side. Covers the rare race where an op crosses the Pigeon boundary before A's invalidation fires.

Consumer migration:
- Replace `bluey.ensureReady()` calls with the factory call itself (the factory now throws the same typed exception).
- Catch `StaleHandleException` and construct fresh from `Bluey` to recover.
- For UI that needs to react to adapter cycles, subscribe to `bluey.stateStream`.

No follow-ups filed — the scope here is intentionally narrow (no session manager, no auto-reinit; see spec).
```

- [ ] **Step 10.2: Workspace verification one more time**

```bash
cd /Users/joel/git/neutrinographics/bluey && flutter analyze
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test
```

Expected: clean, all green.

- [ ] **Step 10.3: Commit**

```bash
git add docs/backlog/I333-bluetooth-adapter-state-not-observed.md
git commit -m "$(cat <<'EOF'
I333: mark resolved in backlog

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist

After implementation, verify before declaring done:

- [ ] `Bluey.ensureReady` is no longer a member of `Bluey` (greppable absence; production callers all migrated).
- [ ] `Bluey.server()`, `Bluey.connect()`, `Bluey.scanner()` each throw a state-mapped exception synchronously when the cached state is not `on`.
- [ ] `BlueyServer`, `BlueyConnection`, `BlueyScanner` each subscribe to `_platform.stateStream` and invalidate on non-`on` emissions.
- [ ] `_invalidate` is idempotent (a guard `if (_invalidated) return;` is present in each of the three implementations).
- [ ] `StaleHandleException.triggeringState` carries the state that caused invalidation, not the current state.
- [ ] `StaleHandleException` is exported from `package:bluey/bluey.dart`.
- [ ] Owned streams on each instance close on invalidation (verifiable via `onDone:` listener pattern in tests).
- [ ] Android `DeadObjectException` translates to `bluetooth-unavailable` → `BluetoothUnavailableException`.
- [ ] iOS GATT op handlers each check `state == .poweredOn` and short-circuit with `BlueyError.notReady` when not.
- [ ] Workspace `flutter analyze` is clean.
- [ ] All package test suites pass.
- [ ] I333 frontmatter `status: fixed`; resolution notes present.
- [ ] All commits use the standard `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` footer.
