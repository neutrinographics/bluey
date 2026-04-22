# Activity-Aware Liveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a pure-domain `LivenessMonitor` that treats any successful GATT op or incoming notification as evidence the peer is alive, eliminating false-positive disconnects when user bursts starve the heartbeat. Apply symmetrically on the server so non-heartbeat requests also reset the per-client liveness timer.

**Architecture:** New `LivenessMonitor` owns all liveness policy (activity timestamps, failure counting, in-flight probe tracking). `LifecycleClient` becomes a thin GATT-mechanism wrapper that delegates decisions to the monitor. `BlueyConnection` notifies the monitor on successful ops and incoming notifications via a renamed `_runGattOp` helper plus an `onActivity` callback threaded through `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor`. `LifecycleServer` gains a `recordActivity(clientId)` entry point that `BlueyServer` calls on non-control-service requests.

**Tech Stack:** Dart, Flutter, flutter_bloc (unaffected), fake_async (tests), mocktail (existing tests).

**Spec:** `docs/superpowers/specs/2026-04-22-activity-aware-liveness-design.md`

---

## File map

### New files

```
bluey/lib/src/connection/liveness_monitor.dart                    (Task 1)
bluey/test/connection/liveness_monitor_test.dart                  (Task 1)
```

### Modified files

```
bluey/lib/src/connection/lifecycle_client.dart                    (Task 2)
bluey/test/connection/lifecycle_client_test.dart                  (Task 2)

bluey/lib/src/connection/bluey_connection.dart                    (Tasks 3, 4, 5)
bluey/test/connection/bluey_connection_activity_test.dart         (NEW — Tasks 4, 5)

bluey/lib/src/gatt_server/lifecycle_server.dart                   (Task 6)
bluey/test/gatt_server/lifecycle_server_test.dart                 (Task 6)

bluey/lib/src/gatt_server/bluey_server.dart                       (Task 7)
bluey/test/bluey_server_test.dart                                 (Task 7)

bluey_android/ANDROID_BLE_NOTES.md                                (Task 8)
```

---

## Task 1: `LivenessMonitor` domain class

**Files:**
- Create: `bluey/lib/src/connection/liveness_monitor.dart`
- Create: `bluey/test/connection/liveness_monitor_test.dart`

Pure domain state machine. No async, no GATT, no platform dependencies. Fully testable with injected clock.

- [ ] **Step 1: Write the failing test file**

Create `bluey/test/connection/liveness_monitor_test.dart`:

```dart
import 'package:bluey/src/connection/liveness_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime fakeNow;
  LivenessMonitor buildMonitor({
    int maxFailedProbes = 1,
    Duration activityWindow = const Duration(seconds: 5),
  }) {
    fakeNow = DateTime.utc(2026, 1, 1);
    return LivenessMonitor(
      maxFailedProbes: maxFailedProbes,
      activityWindow: activityWindow,
      now: () => fakeNow,
    );
  }

  void advance(Duration d) => fakeNow = fakeNow.add(d);

  group('LivenessMonitor', () {
    test('shouldSendProbe is true initially (no activity yet)', () {
      final m = buildMonitor();
      expect(m.shouldSendProbe(), isTrue);
    });

    test('recordActivity then shouldSendProbe within window returns false', () {
      final m = buildMonitor();
      m.recordActivity();
      advance(const Duration(seconds: 3));
      expect(m.shouldSendProbe(), isFalse);
    });

    test('recordActivity then shouldSendProbe after window returns true', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 5));
      expect(m.shouldSendProbe(), isTrue);
    });

    test('markProbeInFlight prevents shouldSendProbe from firing again', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      expect(m.shouldSendProbe(), isFalse);
    });

    test('recordProbeSuccess clears in-flight flag and refreshes activity', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.markProbeInFlight();
      m.recordProbeSuccess();
      advance(const Duration(seconds: 3));
      // In-flight cleared AND activity refreshed.
      expect(m.shouldSendProbe(), isFalse);
      advance(const Duration(seconds: 3));
      expect(m.shouldSendProbe(), isTrue);
    });

    test('recordProbeFailure increments counter and releases in-flight', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      final tripped = m.recordProbeFailure();
      expect(tripped, isFalse, reason: '1 failure < threshold 3');
      // In-flight cleared → next tick can probe.
      expect(m.shouldSendProbe(), isTrue);
    });

    test('recordProbeFailure returns true when threshold is reached', () {
      final m = buildMonitor(maxFailedProbes: 2);
      m.markProbeInFlight();
      expect(m.recordProbeFailure(), isFalse);
      m.markProbeInFlight();
      expect(m.recordProbeFailure(), isTrue);
    });

    test('recordActivity resets the failure counter', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=1
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=2
      m.recordActivity(); // should reset to 0
      m.markProbeInFlight();
      final tripped = m.recordProbeFailure(); // counter back to 1, not 3
      expect(tripped, isFalse);
    });

    test('recordActivity during in-flight probe does not release flag', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      m.recordActivity();
      // Activity recorded, counter reset — but in-flight flag still true.
      expect(m.shouldSendProbe(), isFalse);
      m.recordProbeSuccess();
      // Now the flag releases.
      expect(m.shouldSendProbe(), isFalse); // activity is recent
    });

    test('recordProbeSuccess on non-in-flight monitor is idempotent', () {
      final m = buildMonitor();
      // Calling success without a matching markProbeInFlight should be safe
      // (used when a non-dead-peer error fires — the client releases the flag
      // without penalty).
      expect(() => m.recordProbeSuccess(), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart
```

Expected: compilation failure — `bluey/src/connection/liveness_monitor.dart` not found.

- [ ] **Step 3: Implement `LivenessMonitor`**

Create `bluey/lib/src/connection/liveness_monitor.dart`:

```dart
/// Tracks whether a peer is still alive, based on a stream of
/// observable events.
///
/// Pure domain — no GATT, no async, no platform dependencies. The
/// monitor is queried every tick by [LifecycleClient] to decide
/// whether to send a new probe; between ticks it receives events
/// when user ops complete, notifications arrive, or probes finish.
///
/// Invariants:
/// - At most one probe is "in flight" at any time.
/// - Failure counter is monotonically non-decreasing until reset.
/// - Any activity (user op success or probe ack) resets the counter.
class LivenessMonitor {
  /// Consecutive probe failures that trip peer-unreachable. Activity
  /// clears the counter before it reaches the threshold, so a trip
  /// only fires during genuine idle periods.
  final int maxFailedProbes;

  /// Minimum time since last activity before the monitor will ask
  /// for a probe. Typically equals the probe tick interval so at most
  /// one probe is dispatched per idle window.
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
  /// incoming notification, or a completed probe. Resets the failure
  /// counter and refreshes the activity timestamp.
  void recordActivity() {
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Tick-time decision: should we send a probe this tick? False if
  /// a probe is already pending, or activity is recent within the
  /// window.
  bool shouldSendProbe() {
    if (_probeInFlight) return false;
    final last = _lastActivityAt;
    if (last == null) return true;
    return _now().difference(last) >= activityWindow;
  }

  /// Called just before dispatching a probe write. Prevents parallel
  /// probes — next tick will skip via [shouldSendProbe].
  void markProbeInFlight() {
    _probeInFlight = true;
  }

  /// Probe write completed and peer acknowledged. Equivalent to
  /// [recordActivity] plus releasing the in-flight flag.
  ///
  /// Also safe to call when no probe was in flight (used when a
  /// non-dead-peer error fires during the probe write — releases
  /// the flag without counting a failure).
  void recordProbeSuccess() {
    _probeInFlight = false;
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Probe write failed with a dead-peer signal (caller determines
  /// what counts as dead-peer). Returns true if the failure threshold
  /// is now reached — caller should tear down the connection.
  bool recordProbeFailure() {
    _probeInFlight = false;
    _consecutiveFailures++;
    return _consecutiveFailures >= maxFailedProbes;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey && flutter test test/connection/liveness_monitor_test.dart
```

Expected: 10/10 tests pass.

- [ ] **Step 5: `flutter analyze` clean**

```bash
flutter analyze bluey/lib/src/connection/liveness_monitor.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/liveness_monitor.dart \
        bluey/test/connection/liveness_monitor_test.dart
git commit -m "feat(bluey): add LivenessMonitor domain class"
```

---

## Task 2: Refactor `LifecycleClient` to delegate to `LivenessMonitor`

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Modify: `bluey/test/connection/lifecycle_client_test.dart`

Counter logic moves out of `LifecycleClient` into the monitor. Public API (`start`, `stop`, `isRunning`, `sendDisconnectCommand`, constructor signature) is unchanged. One new public method: `recordActivity()`.

- [ ] **Step 1: Add one new test for recordActivity**

Append to `bluey/test/connection/lifecycle_client_test.dart` (inside the existing `group('LifecycleClient', ...)` block, at the end):

```dart
test('recordActivity resets the failure counter', () {
  fakeAsync((async) {
    var unreachableFired = false;
    late LifecycleClient client;
    late List<RemoteService> services;
    late FakeBlueyPlatform fakePlatform;

    _setUpConnectedClient(
      maxFailedHeartbeats: 2,
      onServerUnreachable: () => unreachableFired = true,
    ).then((setup) {
      client = setup.client;
      services = setup.services;
      fakePlatform = setup.fakePlatform;
    });
    async.flushMicrotasks();

    client.start(allServices: services);
    async.flushMicrotasks();

    // First heartbeat succeeds in the initial send. Now cause
    // timeouts and have activity rescue the connection.
    fakePlatform.simulateWriteTimeout = true;

    // Failure 1 — below threshold.
    async.elapse(const Duration(seconds: 5));
    async.flushMicrotasks();
    expect(unreachableFired, isFalse);

    // User op success → recordActivity resets the counter.
    client.recordActivity();

    // Two more timeouts would trip IF the counter had persisted —
    // but it was reset, so only reaches 2 (= threshold) after both.
    async.elapse(const Duration(seconds: 5));
    async.flushMicrotasks();
    expect(unreachableFired, isFalse, reason: 'counter was reset');

    async.elapse(const Duration(seconds: 5));
    async.flushMicrotasks();
    expect(unreachableFired, isTrue, reason: 'second post-reset failure trips');

    fakePlatform.simulateWriteTimeout = false;
  });
});

test('recordActivity within probe interval skips next probe send', () {
  fakeAsync((async) {
    late LifecycleClient client;
    late List<RemoteService> services;
    late FakeBlueyPlatform fakePlatform;

    _setUpConnectedClient(
      onServerUnreachable: () {},
    ).then((setup) {
      client = setup.client;
      services = setup.services;
      fakePlatform = setup.fakePlatform;
    });
    async.flushMicrotasks();

    client.start(allServices: services);
    async.flushMicrotasks();

    // After start, clear baseline heartbeat writes.
    fakePlatform.writeCharacteristicCalls.clear();

    // Record activity, then let the tick fire. The tick should skip.
    client.recordActivity();
    async.elapse(const Duration(seconds: 5));
    async.flushMicrotasks();

    final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
      (c) => c.characteristicUuid == lifecycle.heartbeatCharUuid,
    );
    expect(heartbeatWrites, isEmpty,
        reason: 'recent activity should cause probe tick to skip');

    client.stop();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: the two new tests fail — `recordActivity` method doesn't exist on `LifecycleClient`.

- [ ] **Step 3: Replace `LifecycleClient` implementation**

Replace the entire body of `bluey/lib/src/connection/lifecycle_client.dart` with:

```dart
import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;

import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import 'liveness_monitor.dart';

/// Client-side lifecycle management.
///
/// Owns the GATT write mechanism (Timer.periodic + heartbeat char write).
/// Delegates all liveness policy decisions to an internal [LivenessMonitor]:
/// when to send a probe, when failures count, when to tear down.
///
/// Internal to the Connection bounded context.
class LifecycleClient {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final int _maxFailedHeartbeats;
  final void Function() onServerUnreachable;

  late LivenessMonitor _monitor;
  Timer? _probeTimer;
  String? _heartbeatCharUuid;

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

  /// Also exposed for [BlueyConnection] tests to inspect: public for
  /// consistency with the rest of the Connection bounded context.
  int get maxFailedHeartbeats => _maxFailedHeartbeats;

  /// Whether the heartbeat timer is currently running.
  bool get isRunning => _probeTimer != null;

  /// Forwarded from [BlueyConnection] on any successful GATT op or
  /// incoming notification. Treats the peer as demonstrably alive.
  /// No-op if the lifecycle isn't running.
  void recordActivity() => _monitor.recordActivity();

  /// Starts the heartbeat if the server hosts the control service.
  ///
  /// [allServices] is the full list of discovered services. If the
  /// control service or its heartbeat characteristic is absent, the
  /// method returns silently without starting heartbeats.
  void start({required List<RemoteService> allServices}) {
    if (_heartbeatCharUuid != null) return;

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) return;

    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    dev.log('heartbeat started: char=$_heartbeatCharUuid', name: 'bluey.lifecycle');

    // Send the first heartbeat immediately so the server (especially
    // iOS, which has no connection callback) learns about this client
    // as soon as possible — before the interval read round-trip.
    _sendProbe();

    // Find the interval characteristic and read the server's interval.
    final intervalChar = controlService.characteristics
        .where(
          (c) =>
              c.uuid.toString().toLowerCase() == lifecycle.intervalCharUuid,
        )
        .firstOrNull;

    if (intervalChar != null) {
      _platform
          .readCharacteristic(_connectionId, intervalChar.uuid.toString())
          .then((bytes) {
        final serverInterval = lifecycle.decodeInterval(bytes);
        final heartbeatInterval = Duration(
          milliseconds: serverInterval.inMilliseconds ~/ 2,
        );
        _beginHeartbeat(heartbeatInterval);
      }).catchError((_) {
        _beginHeartbeat(_defaultHeartbeatInterval);
      });
    } else {
      _beginHeartbeat(_defaultHeartbeatInterval);
    }
  }

  /// Sends a disconnect command to the server's control service.
  Future<void> sendDisconnectCommand() async {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    try {
      await _platform.writeCharacteristic(
        _connectionId,
        charUuid,
        lifecycle.disconnectValue,
        true,
      );
    } catch (_) {
      // Best effort — connection may already be lost
    }
  }

  /// Stops the heartbeat timer and clears the char reference.
  ///
  /// Monitor retains state until the next call to [start] →
  /// [_beginHeartbeat], which recreates it with the chosen interval.
  /// In practice [LifecycleClient] is per-connection — a new
  /// connection = new instance — so this edge case rarely matters.
  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatCharUuid = null;
  }

  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    dev.log('heartbeat interval set: ${interval.inMilliseconds}ms', name: 'bluey.lifecycle');
    // Reinitialise monitor so its activity window matches the server's
    // chosen interval.
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
          _connectionId,
          charUuid,
          lifecycle.heartbeatValue,
          true,
        )
        .then((_) => _monitor.recordProbeSuccess())
        .catchError((Object error) {
      if (!_isDeadPeerSignal(error)) {
        // Not a dead-peer signal — release the in-flight flag without
        // counting. recordProbeSuccess is the cleanest way to release
        // AND refresh activity (the error at least proved the queue
        // ran the op).
        _monitor.recordProbeSuccess();
        return;
      }
      final tripped = _monitor.recordProbeFailure();
      dev.log(
        'heartbeat failed (counted): ${error.runtimeType}',
        name: 'bluey.lifecycle',
        level: 900, // WARNING
      );
      if (tripped) {
        dev.log(
          'heartbeat threshold reached — invoking onServerUnreachable',
          name: 'bluey.lifecycle',
          level: 1000, // SEVERE
        );
        stop();
        onServerUnreachable();
      }
    });
  }

  /// Whether [error] is evidence that the peer is no longer reachable.
  /// See spec "Test isolation" and earlier lifecycle fixes for the
  /// full list of dead-peer signals.
  bool _isDeadPeerSignal(Object error) {
    if (error is platform.GattOperationTimeoutException) return true;
    if (error is platform.GattOperationDisconnectedException) return true;
    if (error is platform.GattOperationStatusFailedException) return true;
    if (error is PlatformException &&
        (error.code == 'notFound' || error.code == 'notConnected')) {
      return true;
    }
    return false;
  }
}
```

- [ ] **Step 4: Run all LifecycleClient tests**

```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: all existing tests + the two new tests pass.

- [ ] **Step 5: Run the full `bluey` suite to catch regressions**

```bash
cd bluey && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: `flutter analyze` clean**

```bash
flutter analyze bluey/
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart \
        bluey/test/connection/lifecycle_client_test.dart
git commit -m "refactor(bluey): LifecycleClient delegates policy to LivenessMonitor"
```

---

## Task 3: Rename `_translateGattPlatformError` → `_runGattOp`

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`

Pure rename. No behavior change. Sets up the next task cleanly.

- [ ] **Step 1: Rename the private helper and all call sites**

In `bluey/lib/src/connection/bluey_connection.dart`, do a text replace:
- `_translateGattPlatformError` → `_runGattOp` (occurs ~9 times: 1 definition + 8 call sites)

Also update the helper's docstring (if any) to match the new name. The method currently says "Catches the internal platform-interface exceptions" — expand to mention it now also records activity (which happens in Task 4).

The helper's definition currently starts at around line 29. Update its docstring:

```dart
/// Runs a GATT op through the error-translation pipeline. Catches
/// internal platform-interface exceptions and rethrows them as the
/// user-facing [BlueyException] sealed hierarchy:
///
///   * [platform.GattOperationTimeoutException] → [GattTimeoutException]
///   * [platform.GattOperationDisconnectedException] →
///     [DisconnectedException] with [DisconnectReason.linkLoss]
///   * [platform.GattOperationStatusFailedException] →
///     [GattOperationFailedException] carrying the native status
///
/// The platform-interface types stay internal: only [LifecycleClient]
/// (an internal collaborator) catches them directly. Public callers
/// see only [BlueyException] subtypes, so they can pattern-match
/// exhaustively.
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on platform.GattOperationTimeoutException {
    throw GattTimeoutException(operation);
  } on platform.GattOperationDisconnectedException {
    throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
  } on platform.GattOperationStatusFailedException catch (e) {
    throw GattOperationFailedException(operation, e.status);
  }
}
```

- [ ] **Step 2: Run the full `bluey` suite**

```bash
cd bluey && flutter test
```

Expected: all existing tests pass (no behavior change).

- [ ] **Step 3: `flutter analyze` clean**

```bash
flutter analyze bluey/
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart
git commit -m "refactor(bluey): rename _translateGattPlatformError → _runGattOp"
```

---

## Task 4: Add `onSuccess` callback to `_runGattOp` + wire `BlueyConnection`'s own methods

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`
- Create: `bluey/test/connection/bluey_connection_activity_test.dart`

Adds the activity hook to the success path. Wires it from `BlueyConnection`'s own method call sites (`services`, `requestMtu`, `readRssi`). `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor` call sites get wired in Task 5.

- [ ] **Step 1: Write the failing test**

Create `bluey/test/connection/bluey_connection_activity_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Verifies that successful GATT ops on the connection record
/// activity on the lifecycle client. Task 4 covers connection-level
/// methods (services, requestMtu, readRssi); Task 5 adds tests for
/// remote characteristic / descriptor ops via direct construction.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyConnection activity — own methods', () {
    test('requestMtu success causes the next heartbeat tick to skip', () {
      fakeAsync((async) {
        fakePlatform.simulateBlueyServer(
          address: TestDeviceIds.device1,
          serverId: ServerId.generate(),
        );

        final bluey = Bluey();
        late Connection conn;
        bluey
            .connect(Device(
              id: UUID('00000000-0000-0000-0000-aabbccddee01'),
              address: TestDeviceIds.device1,
              name: 'Test Device',
            ))
            .then((c) => conn = c);
        async.flushMicrotasks();

        // Let the initial heartbeat + interval read settle so the
        // periodic timer is up with a known activity baseline.
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        // Baseline: clear prior heartbeats.
        fakePlatform.writeCharacteristicCalls.clear();

        // requestMtu — records activity on success.
        conn.requestMtu(247);
        async.flushMicrotasks();

        // Advance through one full tick interval (5s default).
        // With activity recorded just now, the tick's shouldSendProbe
        // should return false.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (c) => c.characteristicUuid == lifecycle.heartbeatCharUuid,
        );
        expect(heartbeatWrites, isEmpty,
            reason: 'tick within activity window should skip');

        conn.disconnect();
        bluey.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
```

- [ ] **Step 2: Verify red**

```bash
cd bluey && flutter test test/connection/bluey_connection_activity_test.dart
```

Expected: the test fails — no activity hook yet; heartbeat DOES fire in the window.

- [ ] **Step 3: Add `onSuccess` parameter to `_runGattOp`**

In `bluey/lib/src/connection/bluey_connection.dart`, update the helper:

```dart
/// Runs a GATT op through the error-translation pipeline, then fires
/// [onSuccess] if the op returned without throwing. Used by every
/// public GATT op on [BlueyConnection] / [BlueyRemoteCharacteristic]
/// / [BlueyRemoteDescriptor] so activity signals flow uniformly into
/// [LifecycleClient.recordActivity].
///
/// Catches internal platform-interface exceptions and rethrows them
/// as the user-facing [BlueyException] sealed hierarchy:
///
///   * [platform.GattOperationTimeoutException] → [GattTimeoutException]
///   * [platform.GattOperationDisconnectedException] →
///     [DisconnectedException] with [DisconnectReason.linkLoss]
///   * [platform.GattOperationStatusFailedException] →
///     [GattOperationFailedException] carrying the native status
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body, {
  void Function()? onSuccess,
}) async {
  try {
    final result = await body();
    onSuccess?.call();
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

- [ ] **Step 4: Wire the three call sites on `BlueyConnection` itself**

Find the call sites at lines ~244 (`services`), ~295 (`requestMtu`), ~327 (`readRssi`). Add `onSuccess: () => _lifecycle?.recordActivity()` to each.

Example for `services()`:

```dart
final platformServices = await _runGattOp(
  deviceId,
  'discoverServices',
  () => _platform.discoverServices(_connectionId),
  onSuccess: () => _lifecycle?.recordActivity(),
);
```

Same for `requestMtu`:

```dart
final negotiatedMtu = await _runGattOp(
  deviceId,
  'requestMtu',
  () => _platform.requestMtu(_connectionId, requestedMtu),
  onSuccess: () => _lifecycle?.recordActivity(),
);
```

And `readRssi`:

```dart
final rssi = await _runGattOp(
  deviceId,
  'readRssi',
  () => _platform.readRssi(_connectionId),
  onSuccess: () => _lifecycle?.recordActivity(),
);
```

Leave the `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor` call sites unchanged for now — Task 5 threads the callback through them.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd bluey && flutter test test/connection/bluey_connection_activity_test.dart
cd bluey && flutter test  # full suite
```

Expected: the new activity test passes; all existing tests still pass.

- [ ] **Step 6: `flutter analyze` clean**

```bash
flutter analyze bluey/
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/bluey_connection_activity_test.dart
git commit -m "feat(bluey): _runGattOp fires onSuccess to record lifecycle activity"
```

---

## Task 5: Thread `onActivity` through `BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor`

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart`
- Modify: `bluey/test/connection/bluey_connection_activity_test.dart`

`BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor` don't have direct access to the owning `BlueyConnection`'s `_lifecycle`. Pass a `VoidCallback? onActivity` via their constructors; `BlueyConnection._mapCharacteristic` / `_mapDescriptor` supply it.

- [ ] **Step 1: Add activity tests for characteristic + descriptor ops (direct-construction style)**

Append to `bluey/test/connection/bluey_connection_activity_test.dart`, inside `void main()`, AFTER the existing `group('BlueyConnection activity — own methods', …)` group. These tests construct `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor` directly with an injected `onActivity` callback — simpler and faster than going through the full `Bluey.connect()` + peer-upgrade path. They reuse the file-level `setUp` that initialises `fakePlatform`.

```dart
group('BlueyRemoteCharacteristic activity hook', () {
  test('write fires onActivity on success', () async {
  final activityEvents = <void>[];

  fakePlatform.simulatePeripheral(
    id: TestDeviceIds.device1,
    name: 'Test',
    services: [
      TestServiceBuilder(TestUuids.customService)
          .withWritable(TestUuids.customChar1)
          .build(),
    ],
  );
  await fakePlatform.connect(
    TestDeviceIds.device1,
    const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
  );

  final char = BlueyRemoteCharacteristic(
    platform: fakePlatform,
    connectionId: TestDeviceIds.device1,
    deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
    uuid: UUID(TestUuids.customChar1),
    properties: const CharacteristicProperties(
      canRead: false,
      canWrite: true,
      canWriteWithoutResponse: false,
      canNotify: false,
      canIndicate: false,
    ),
    descriptors: const [],
    onActivity: () => activityEvents.add(null),
  );

  await char.write(Uint8List.fromList([0x42]));
  expect(activityEvents, hasLength(1),
      reason: 'successful write must fire onActivity');
});

test('BlueyRemoteCharacteristic.read fires onActivity on success', () async {
  final activityEvents = <void>[];

  fakePlatform.simulatePeripheral(
    id: TestDeviceIds.device1,
    name: 'Test',
    services: [
      TestServiceBuilder(TestUuids.customService)
          .withReadable(TestUuids.customChar1, value: Uint8List.fromList([0x77]))
          .build(),
    ],
  );
  await fakePlatform.connect(
    TestDeviceIds.device1,
    const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
  );

  final char = BlueyRemoteCharacteristic(
    platform: fakePlatform,
    connectionId: TestDeviceIds.device1,
    deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
    uuid: UUID(TestUuids.customChar1),
    properties: const CharacteristicProperties(
      canRead: true,
      canWrite: false,
      canWriteWithoutResponse: false,
      canNotify: false,
      canIndicate: false,
    ),
    descriptors: const [],
    onActivity: () => activityEvents.add(null),
  );

  await char.read();
  expect(activityEvents, hasLength(1));
});

test('BlueyRemoteCharacteristic.write failure does NOT fire onActivity', () async {
  final activityEvents = <void>[];

  fakePlatform.simulatePeripheral(
    id: TestDeviceIds.device1,
    name: 'Test',
    services: [
      TestServiceBuilder(TestUuids.customService)
          .withWritable(TestUuids.customChar1)
          .build(),
    ],
  );
  await fakePlatform.connect(
    TestDeviceIds.device1,
    const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
  );
  fakePlatform.simulateWriteTimeout = true;

  final char = BlueyRemoteCharacteristic(
    platform: fakePlatform,
    connectionId: TestDeviceIds.device1,
    deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
    uuid: UUID(TestUuids.customChar1),
    properties: const CharacteristicProperties(
      canRead: false,
      canWrite: true,
      canWriteWithoutResponse: false,
      canNotify: false,
      canIndicate: false,
    ),
    descriptors: const [],
    onActivity: () => activityEvents.add(null),
  );

  await expectLater(
    () => char.write(Uint8List.fromList([0x42])),
    throwsA(isA<GattTimeoutException>()),
  );
  expect(activityEvents, isEmpty);

  fakePlatform.simulateWriteTimeout = false;
});
}); // end group('BlueyRemoteCharacteristic activity hook')
```

Add the import at the top of the file:

```dart
import 'dart:typed_data';
```

Verify that `BlueyRemoteCharacteristic` is exported from `bluey` (or import it directly from its source file — `package:bluey/src/connection/bluey_connection.dart`).

Check `FakeBlueyPlatform` for the `withReadable(uuid, value:)` helper — if it doesn't exist, use `withWritable` but set the initial value via `characteristicValues` on the `simulatePeripheral` call. Adapt to match the existing helpers in `bluey/test/fakes/test_helpers.dart`.

- [ ] **Step 2: Verify red**

```bash
cd bluey && flutter test test/connection/bluey_connection_activity_test.dart
```

Expected: the new characteristic test fails — user writes don't currently record activity.

- [ ] **Step 3: Add `onActivity` parameter to `BlueyRemoteCharacteristic`**

In `bluey/lib/src/connection/bluey_connection.dart`, update `BlueyRemoteCharacteristic`'s fields + constructor (around line 666):

```dart
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final UUID _deviceId;
  final void Function()? _onActivity;
  @override
  final UUID uuid;
  @override
  final CharacteristicProperties properties;
  @override
  final List<RemoteDescriptor> descriptors;

  StreamSubscription? _notificationSubscription;
  StreamController<Uint8List>? _notificationController;

  BlueyRemoteCharacteristic({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
    required this.properties,
    required this.descriptors,
    void Function()? onActivity,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId,
       _onActivity = onActivity;
```

- [ ] **Step 4: Wire `onSuccess: _onActivity` into every `_runGattOp` call in `BlueyRemoteCharacteristic`**

Locate every `_runGattOp(` call within `BlueyRemoteCharacteristic`'s methods (`read`, `write`, `_onFirstListen`, `_onLastCancel`). For each, add the named argument:

```dart
final value = await _runGattOp(
  _deviceId,
  'readCharacteristic',
  () => _platform.readCharacteristic(_connectionId, uuid.toString()),
  onSuccess: _onActivity,
);
```

```dart
await _runGattOp(
  _deviceId,
  'writeCharacteristic',
  () => _platform.writeCharacteristic(
    _connectionId, uuid.toString(), value, withResponse,
  ),
  onSuccess: _onActivity,
);
```

```dart
// In _onFirstListen, for setNotification(true):
_runGattOp(
  _deviceId,
  'setNotification',
  () => _platform.setNotification(_connectionId, uuid.toString(), true),
  onSuccess: _onActivity,
).catchError(...);

// In _onLastCancel, for setNotification(false):
_runGattOp(
  _deviceId,
  'setNotification',
  () => _platform.setNotification(_connectionId, uuid.toString(), false),
  onSuccess: _onActivity,
).catchError(...);
```

- [ ] **Step 5: Add activity hook to the notification stream listener**

Also in `_onFirstListen`, inside the existing `.listen(...)` body:

```dart
_notificationSubscription = _platform
    .notificationStream(_connectionId)
    .where(
      (n) =>
          n.characteristicUuid.toLowerCase() ==
          uuid.toString().toLowerCase(),
    )
    .listen(
      (notification) {
        _onActivity?.call();  // NEW
        _notificationController?.add(notification.value);
      },
      onError: (error) {
        _notificationController?.addError(error);
      },
    );
```

- [ ] **Step 6: Add `onActivity` parameter to `BlueyRemoteDescriptor`**

Locate `BlueyRemoteDescriptor` (around line 839). Same treatment:

```dart
class BlueyRemoteDescriptor implements RemoteDescriptor {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final UUID _deviceId;
  final void Function()? _onActivity;
  @override
  final UUID uuid;

  BlueyRemoteDescriptor({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required UUID deviceId,
    required this.uuid,
    void Function()? onActivity,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceId = deviceId,
       _onActivity = onActivity;
```

Update `BlueyRemoteDescriptor`'s `read()` and `write()` calls to `_runGattOp` with `onSuccess: _onActivity`:

```dart
@override
Future<Uint8List> read() {
  return _runGattOp(
    _deviceId,
    'readDescriptor',
    () => _platform.readDescriptor(_connectionId, uuid.toString()),
    onSuccess: _onActivity,
  );
}

@override
Future<void> write(Uint8List value) {
  return _runGattOp(
    _deviceId,
    'writeDescriptor',
    () => _platform.writeDescriptor(_connectionId, uuid.toString(), value),
    onSuccess: _onActivity,
  );
}
```

- [ ] **Step 7: Pass `onActivity` from `BlueyConnection._mapCharacteristic` and `_mapDescriptor`**

Update `_mapCharacteristic` (around line 585):

```dart
BlueyRemoteCharacteristic _mapCharacteristic(
  platform.PlatformCharacteristic pc,
) {
  void onActivity() => _lifecycle?.recordActivity();
  return BlueyRemoteCharacteristic(
    platform: _platform,
    connectionId: _connectionId,
    deviceId: deviceId,
    uuid: UUID(pc.uuid),
    properties: CharacteristicProperties(
      canRead: pc.properties.canRead,
      canWrite: pc.properties.canWrite,
      canWriteWithoutResponse: pc.properties.canWriteWithoutResponse,
      canNotify: pc.properties.canNotify,
      canIndicate: pc.properties.canIndicate,
    ),
    descriptors: pc.descriptors
        .map((pd) => _mapDescriptor(pd, onActivity))
        .toList(),
    onActivity: onActivity,
  );
}
```

Update `_mapDescriptor` signature to accept the callback:

```dart
BlueyRemoteDescriptor _mapDescriptor(
  platform.PlatformDescriptor pd,
  void Function()? onActivity,
) {
  return BlueyRemoteDescriptor(
    platform: _platform,
    connectionId: _connectionId,
    deviceId: deviceId,
    uuid: UUID(pd.uuid),
    onActivity: onActivity,
  );
}
```

- [ ] **Step 8: Run tests**

```bash
cd bluey && flutter test test/connection/bluey_connection_activity_test.dart
cd bluey && flutter test  # full suite
```

Expected: both activity tests pass; all existing tests still pass.

- [ ] **Step 9: `flutter analyze` clean**

```bash
flutter analyze bluey/
```

Expected: No issues found.

- [ ] **Step 10: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/bluey_connection_activity_test.dart
git commit -m "feat(bluey): thread onActivity through remote characteristics/descriptors"
```

---

## Task 6: `LifecycleServer.recordActivity` method

**Files:**
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart`
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart`

New public method to allow `BlueyServer` to treat any incoming request (not just control-service writes) as a liveness signal.

- [ ] **Step 1: Write the failing test**

Append to `bluey/test/gatt_server/lifecycle_server_test.dart` (inside the existing `group('LifecycleServer', ...)` block):

```dart
test('recordActivity resets the per-client timer', () {
  fakeAsync((async) {
    final events = <String>[];
    final server = LifecycleServer(
      platformApi: FakeBlueyPlatform(),
      interval: const Duration(seconds: 10),
      serverId: ServerId.generate(),
      onClientGone: (id) => events.add('gone:$id'),
    );

    const clientId = 'test-client';

    // Prime the server by receiving a heartbeat from the client.
    server.handleWriteRequest(platform.PlatformWriteRequest(
      requestId: 1,
      centralId: clientId,
      characteristicUuid: lifecycle.heartbeatCharUuid,
      value: lifecycle.heartbeatValue,
      responseNeeded: false,
    ));

    // Advance 9s — just under the timeout.
    async.elapse(const Duration(seconds: 9));
    expect(events, isEmpty);

    // Record activity (simulates a non-control-service write arriving).
    server.recordActivity(clientId);

    // Advance another 9s — total 18s since first heartbeat, but only
    // 9s since recordActivity, so still within the window.
    async.elapse(const Duration(seconds: 9));
    expect(events, isEmpty, reason: 'recordActivity should reset the timer');

    // Another 2s → past the timer from recordActivity → should fire.
    async.elapse(const Duration(seconds: 2));
    expect(events, equals(['gone:$clientId']));

    server.dispose();
  });
});

test('recordActivity is a no-op when lifecycle is disabled (null interval)', () {
  final server = LifecycleServer(
    platformApi: FakeBlueyPlatform(),
    interval: null,
    serverId: ServerId.generate(),
    onClientGone: (_) => fail('no client should expire'),
  );

  // Calling recordActivity when lifecycle is disabled should be safe
  // and do nothing.
  expect(() => server.recordActivity('client'), returnsNormally);

  server.dispose();
});
```

Imports at the top of the file, if missing:

```dart
import 'package:bluey/src/gatt_server/lifecycle_server.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/peer/server_id.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
```

- [ ] **Step 2: Verify red**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart
```

Expected: `recordActivity` method doesn't exist on `LifecycleServer` — compile error.

- [ ] **Step 3: Add the method**

In `bluey/lib/src/gatt_server/lifecycle_server.dart`, add after `cancelTimer`:

```dart
/// Treats any incoming activity from [clientId] as liveness evidence.
/// Resets the per-client timer without requiring a write to the
/// control-service characteristic. Called by [BlueyServer] on every
/// request from a client that isn't already routed through
/// [handleWriteRequest] or [handleReadRequest].
///
/// No-op if lifecycle is disabled (interval is null) — matches the
/// existing `_resetTimer` behaviour.
void recordActivity(String clientId) {
  if (_interval == null) return;
  _resetTimer(clientId);
}
```

- [ ] **Step 4: Run tests**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart
cd bluey && flutter test  # full suite
```

Expected: both new tests pass; all existing tests still pass.

- [ ] **Step 5: `flutter analyze` clean**

```bash
flutter analyze bluey/
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/gatt_server/lifecycle_server.dart \
        bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "feat(bluey): LifecycleServer.recordActivity resets per-client timer"
```

---

## Task 7: `BlueyServer` wires `recordActivity` on request fallthrough

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`
- Modify: `bluey/test/bluey_server_test.dart`

When a client writes to a non-control-service characteristic, the request falls through the lifecycle server's `handleWriteRequest` — that path must notify the lifecycle of activity.

- [ ] **Step 1: Inspect existing test patterns**

Read `bluey/test/bluey_server_test.dart` to identify the existing patterns for:
- Constructing a `BlueyServer` with a lifecycle interval
- Registering a user-defined hosted service
- Feeding simulated platform write requests via `FakeBlueyPlatform`
- Observing disconnection events (look for `disconnections`, `onClientGone`, or similar)

The test below uses `server.disconnections` (a `Stream<String>` emitting `clientId` when the lifecycle fires `onClientGone`). If the project's API differs, use the actual observable.

- [ ] **Step 2: Write the failing test**

Append to the appropriate `group('BlueyServer', ...)` in `bluey/test/bluey_server_test.dart`:

```dart
test('incoming write to a non-control-service char resets client liveness timer', () {
  fakeAsync((async) {
    final fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;

    late BlueyServer server;
    Bluey().server(lifecycleInterval: const Duration(seconds: 10))
        .then((s) => server = s);
    async.flushMicrotasks();

    final userServiceUuid = UUID(TestUuids.customService);
    final userCharUuid = UUID(TestUuids.customChar1);

    server.addService(HostedService(
      uuid: userServiceUuid,
      isPrimary: true,
      characteristics: [
        HostedCharacteristic(
          uuid: userCharUuid,
          properties: const CharacteristicProperties(canWrite: true),
          permissions: const [GattPermission.write],
          descriptors: const [],
        ),
      ],
    ));
    async.flushMicrotasks();

    final disconnections = <String>[];
    server.disconnections.listen(disconnections.add);

    // Prime: send a heartbeat from clientId to register the client.
    fakePlatform.simulateWriteRequest(
      centralId: 'client-1',
      characteristicUuid: lifecycle.heartbeatCharUuid,
      value: lifecycle.heartbeatValue,
      responseNeeded: false,
    );
    async.flushMicrotasks();

    // Advance 9s — under the 10s timeout.
    async.elapse(const Duration(seconds: 9));
    expect(disconnections, isEmpty);

    // Send a write to the user service — should reset the timer even
    // though it's not a control-service write.
    fakePlatform.simulateWriteRequest(
      centralId: 'client-1',
      characteristicUuid: userCharUuid.toString(),
      value: Uint8List.fromList([0x99]),
      responseNeeded: true,
    );
    async.flushMicrotasks();

    // Advance another 9s — total 18s since the heartbeat, but only
    // 9s since the user write — still within window.
    async.elapse(const Duration(seconds: 9));
    expect(disconnections, isEmpty,
        reason: 'non-control-service write should reset the liveness timer');

    // 2s more → past the timer from the user write → should fire.
    async.elapse(const Duration(seconds: 2));
    expect(disconnections, equals(['client-1']));

    server.dispose();
  });
});
```

Imports (add if missing):

```dart
import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart' as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_platform.dart';
import 'fakes/test_helpers.dart';
```

If the `server.disconnections` API doesn't match the existing BlueyServer surface:
- Search `bluey/lib/src/gatt_server/bluey_server.dart` for the method that exposes client disconnections (likely a `Stream<String>`). Use that method name in the test.
- If no such stream exists, use the `onClientGone` callback via constructor injection of `LifecycleServer` as a smaller refactor.

If `FakeBlueyPlatform.simulateWriteRequest` doesn't accept `centralId` as a parameter (check its signature), adjust per the fake's actual API — the point is to inject a write request as if from a specific client.

- [ ] **Step 2: Verify red**

```bash
cd bluey && flutter test test/bluey_server_test.dart
```

Expected: the new test fails — user writes don't currently reset the lifecycle timer.

- [ ] **Step 3: Modify `BlueyServer` read/write listeners**

Open `bluey/lib/src/gatt_server/bluey_server.dart`. Find the `_writeRequestSubscription` and `_readRequestSubscription` listeners (search for `_observeWriteRequests` and `_observeReadRequests`). Add a `_lifecycle.recordActivity(clientId)` call on the fallthrough path — after the `handleWriteRequest` / `handleReadRequest` check returns false.

Example shape:

```dart
_writeRequestSubscription = _platform.writeRequests.listen((request) async {
  if (_lifecycle.handleWriteRequest(request)) return;
  _lifecycle.recordActivity(request.centralId);  // NEW
  // ... existing user handler dispatch ...
});

_readRequestSubscription = _platform.readRequests.listen((request) async {
  if (_lifecycle.handleReadRequest(request)) return;
  _lifecycle.recordActivity(request.centralId);  // NEW
  // ... existing user handler dispatch ...
});
```

(Adapt variable names to the actual code — `_platform.writeRequests` may be something else. Inspect.)

- [ ] **Step 4: Run tests**

```bash
cd bluey && flutter test test/bluey_server_test.dart
cd bluey && flutter test  # full suite
```

Expected: the new test passes; existing tests still pass.

- [ ] **Step 5: `flutter analyze` clean**

```bash
flutter analyze bluey/
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/gatt_server/bluey_server.dart \
        bluey/test/bluey_server_test.dart
git commit -m "feat(bluey): BlueyServer records client activity on non-control requests"
```

---

## Task 8: Documentation update

**Files:**
- Modify: `bluey_android/ANDROID_BLE_NOTES.md`

Short note explaining the new activity-aware liveness behaviour. No behavior changes — just docs.

- [ ] **Step 1: Append a section**

At the end of `bluey_android/ANDROID_BLE_NOTES.md`, add:

```markdown
## Activity-Aware Liveness (2026-04-22)

`LifecycleClient` no longer sends a heartbeat on every interval tick if it has recently observed other activity on the connection. Any successful GATT op (read, write, discoverServices, requestMtu, readRssi, setNotification) or incoming notification counts as activity and:

1. Resets the consecutive-failure counter.
2. Refreshes the activity-window timestamp so the next tick's `shouldSendProbe` check returns false.

Symmetric change on the server: `LifecycleServer` accepts any incoming request from a client (not just heartbeat writes) as liveness evidence via `recordActivity(clientId)`. `BlueyServer` calls this on the fallthrough path of its read/write listeners.

The heartbeat write still fires as a fallback when the connection is genuinely idle. The control service, heartbeat characteristic, and wire protocol are unchanged.

Motivation: burst workloads (e.g. the example app's stress-test suite) were starving the heartbeat into a queue-wait timeout, tripping `onServerUnreachable` mid-burst even though every preceding write had succeeded. Treating user-op success as activity prevents this false positive.

Implementation reference: `bluey/lib/src/connection/liveness_monitor.dart` owns the state machine; `LifecycleClient` delegates all policy decisions to it.
```

- [ ] **Step 2: Commit**

```bash
git add bluey_android/ANDROID_BLE_NOTES.md
git commit -m "docs(bluey_android): document activity-aware liveness"
```

---

## Self-review

After completing the plan writing, verified against the spec:

| Spec section | Plan task(s) | Coverage |
|---|---|---|
| `LivenessMonitor` (new class, pure domain) | Task 1 | ✓ |
| `LifecycleClient` refactor to delegate to monitor | Task 2 | ✓ |
| `_translateGattPlatformError` → `_runGattOp` rename | Task 3 | ✓ |
| `_runGattOp` records activity on success | Task 4 | ✓ |
| `BlueyRemoteCharacteristic.onActivity` callback + notification hook | Task 5 | ✓ |
| `BlueyRemoteDescriptor.onActivity` callback | Task 5 | ✓ |
| `BlueyConnection._mapCharacteristic`/`_mapDescriptor` pass callback | Task 5 | ✓ |
| `LifecycleServer.recordActivity(clientId)` | Task 6 | ✓ |
| `BlueyServer` wires recordActivity on fallthrough | Task 7 | ✓ |
| Docs update | Task 8 | ✓ |
| Tests for `LivenessMonitor` (10 transitions) | Task 1 | ✓ |
| Tests for `LifecycleClient` with recordActivity | Task 2 | ✓ |
| Tests for `BlueyConnection` activity hook (own ops + char ops) | Tasks 4, 5 | ✓ |
| Tests for `LifecycleServer.recordActivity` | Task 6 | ✓ |
| Test for `BlueyServer` fallthrough activity | Task 7 | ✓ |

No gaps identified. No placeholders. Consistent naming (`onActivity` callback, `recordActivity` method, `_runGattOp` helper) across tasks.

## Out-of-scope (per spec)

- Protocol changes (UUIDs, opcodes, services) — unchanged.
- Tuning defaults (`maxFailedHeartbeats = 1`, `defaultLifecycleInterval = 10s`) — unchanged.
- Extracting a `PassiveLivenessMonitor` on the server — kept inline.
- MTU-related diagnostic improvements — separate spec.
- Structured-logging framework — separate spec.
