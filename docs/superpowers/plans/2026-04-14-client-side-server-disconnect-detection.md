# Client-Side Server Disconnect Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect when a BLE server goes away by switching heartbeat writes from write-without-response to write-with-response, and disconnecting the client when writes fail.

**Architecture:** Extract lifecycle logic from `BlueyConnection` into `LifecycleClient` and from `BlueyServer` into `LifecycleServer` (pure refactor). Then change the heartbeat characteristic to write-with-response and add failure tracking to `LifecycleClient`. Add `maxFailedHeartbeats` parameter to `Bluey.connect()`.

**Tech Stack:** Dart/Flutter, fake_async for timer testing, FakeBlueyPlatform for integration testing.

**Spec:** `docs/superpowers/specs/2026-04-14-client-side-server-disconnect-detection-design.md`

---

## File Structure

**New files:**
- `bluey/lib/src/connection/lifecycle_client.dart` — Client-side heartbeat sending, failure tracking, disconnect detection
- `bluey/lib/src/gatt_server/lifecycle_server.dart` — Server-side heartbeat monitoring, control service management
- `bluey/test/connection/lifecycle_client_test.dart` — Unit tests for LifecycleClient
- `bluey/test/gatt_server/lifecycle_server_test.dart` — Unit tests for LifecycleServer

**Modified files:**
- `bluey/lib/src/lifecycle.dart` — Change heartbeat characteristic from `canWriteWithoutResponse` to `canWrite`
- `bluey/lib/src/connection/bluey_connection.dart` — Replace inline lifecycle code with `LifecycleClient` composition
- `bluey/lib/src/gatt_server/bluey_server.dart` — Replace inline lifecycle code with `LifecycleServer` composition
- `bluey/lib/src/bluey.dart` — Add `maxFailedHeartbeats` parameter to `connect()`
- `bluey/test/lifecycle_test.dart` — Update existing tests (heartbeat writes now use `withResponse: true`)
- `bluey/test/fakes/fake_platform.dart` — Add ability to simulate write failures for testing

---

### Task 1: Extract LifecycleServer from BlueyServer

Pure refactor. Move server-side lifecycle logic (heartbeat timers, control service setup, control request interception) into a dedicated class. Existing tests validate no behavior change.

**Files:**
- Create: `bluey/lib/src/gatt_server/lifecycle_server.dart`
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`

- [ ] **Step 1: Write the LifecycleServer class**

Create `bluey/lib/src/gatt_server/lifecycle_server.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../lifecycle.dart' as lifecycle;

/// Server-side lifecycle management.
///
/// Handles the control service (heartbeat monitoring, interval reads) and
/// detects client disconnection via heartbeat timeouts. Internal to the
/// GATT Server bounded context.
class LifecycleServer {
  final Duration? _interval;
  final void Function(String clientId) onClientTimedOut;

  bool _controlServiceAdded = false;
  final Map<String, Timer> _heartbeatTimers = {};

  LifecycleServer({
    required Duration? interval,
    required this.onClientTimedOut,
  }) : _interval = interval;

  /// Whether lifecycle management is enabled.
  bool get isEnabled => _interval != null;

  /// Adds the control service to the platform if lifecycle is enabled
  /// and it hasn't been added yet.
  Future<void> addControlServiceIfNeeded(platform.BlueyPlatform platform) async {
    if (_interval == null || _controlServiceAdded) return;
    await platform.addService(lifecycle.buildControlService());
    _controlServiceAdded = true;
  }

  /// Handles a write request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleWriteRequest(
    platform.PlatformWriteRequest req,
    platform.BlueyPlatform platform,
  ) {
    if (!lifecycle.isControlServiceCharacteristic(req.characteristicUuid)) {
      return false;
    }

    // Auto-respond if the platform requires it
    if (req.responseNeeded) {
      platform.respondToWriteRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
      );
    }

    final clientId = req.centralId;

    if (req.value.isNotEmpty && req.value[0] == lifecycle.disconnectValue[0]) {
      // Client is disconnecting cleanly
      _cancelTimer(clientId);
      onClientTimedOut(clientId);
    } else {
      // Heartbeat — reset the timer
      _resetTimer(clientId);
    }

    return true;
  }

  /// Handles a read request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleReadRequest(
    platform.PlatformReadRequest req,
    platform.BlueyPlatform platform,
  ) {
    if (!lifecycle.isControlServiceCharacteristic(req.characteristicUuid)) {
      return false;
    }

    final interval = _interval ?? lifecycle.defaultLifecycleInterval;
    platform.respondToReadRequest(
      req.requestId,
      platform.PlatformGattStatus.success,
      lifecycle.encodeInterval(interval),
    );

    return true;
  }

  /// Cancels the heartbeat timer for a specific client.
  void cancelTimer(String clientId) {
    _cancelTimer(clientId);
  }

  /// Cancels all heartbeat timers and cleans up.
  void dispose() {
    for (final timer in _heartbeatTimers.values) {
      timer.cancel();
    }
    _heartbeatTimers.clear();
  }

  void _resetTimer(String clientId) {
    final interval = _interval;
    if (interval == null) return;

    _heartbeatTimers[clientId]?.cancel();
    _heartbeatTimers[clientId] = Timer(interval, () {
      _heartbeatTimers.remove(clientId);
      onClientTimedOut(clientId);
    });
  }

  void _cancelTimer(String clientId) {
    _heartbeatTimers[clientId]?.cancel();
    _heartbeatTimers.remove(clientId);
  }
}
```

- [ ] **Step 2: Update BlueyServer to compose LifecycleServer**

Replace the inline lifecycle logic in `bluey/lib/src/gatt_server/bluey_server.dart`. Remove:
- `_controlServiceAdded` field
- `_heartbeatTimers` field
- `_addControlServiceIfNeeded()` method
- `_resetHeartbeatTimer()` method
- `_handleHeartbeatTimeout()` method
- `_handleControlWrite()` method
- `_handleControlRead()` method
- Heartbeat timer cleanup from `_handleClientDisconnected()` and `dispose()`

Add a `_lifecycle` field and delegate to it:

In the constructor, create the lifecycle server:
```dart
late final LifecycleServer _lifecycle;

BlueyServer(
  this._platform,
  this._eventBus, {
  Duration? lifecycleInterval = lifecycle.defaultLifecycleInterval,
}) : _lifecycleInterval = lifecycleInterval {
  _lifecycle = LifecycleServer(
    interval: lifecycleInterval,
    onClientTimedOut: _handleClientDisconnected,
  );
  // ... rest of constructor unchanged, but replace inline checks:
```

In the platform request listeners:
```dart
_platformReadRequestsSub = _platform.readRequests.listen((req) {
  if (!_lifecycle.handleReadRequest(req, _platform)) {
    _filteredReadRequestsController.add(req);
  }
});

_platformWriteRequestsSub = _platform.writeRequests.listen((req) {
  if (!_lifecycle.handleWriteRequest(req, _platform)) {
    _filteredWriteRequestsController.add(req);
  }
});
```

In `startAdvertising`, replace `_addControlServiceIfNeeded()` with:
```dart
await _lifecycle.addControlServiceIfNeeded(_platform);
```

In `_handleClientDisconnected`, remove the heartbeat timer lines and replace with:
```dart
_lifecycle.cancelTimer(clientId);
```

In `dispose`, replace the heartbeat timer cleanup with:
```dart
_lifecycle.dispose();
```

Remove the `_lifecycleInterval` field since `LifecycleServer` now owns it. But keep the constructor parameter — pass it through. Actually, `_handleControlWrite` used `_trackClientIfNeeded`. Move that call: `LifecycleServer.handleWriteRequest` doesn't call `_trackClientIfNeeded` — `BlueyServer` needs to do that before delegating. Update the write listener:

```dart
_platformWriteRequestsSub = _platform.writeRequests.listen((req) {
  if (lifecycle.isControlServiceCharacteristic(req.characteristicUuid)) {
    _trackClientIfNeeded(req.centralId);
  }
  if (!_lifecycle.handleWriteRequest(req, _platform)) {
    _filteredWriteRequestsController.add(req);
  }
});
```

- [ ] **Step 3: Run existing tests to verify no behavior change**

Run: `cd bluey && flutter test test/lifecycle_test.dart`
Expected: All 8 tests pass.

Run: `cd bluey && flutter test test/bluey_server_test.dart`
Expected: All tests pass.

Run: `cd bluey && flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/gatt_server/lifecycle_server.dart bluey/lib/src/gatt_server/bluey_server.dart
git commit -m "refactor: extract LifecycleServer from BlueyServer"
```

---

### Task 2: Extract LifecycleClient from BlueyConnection

Pure refactor. Move client-side lifecycle logic (heartbeat timer, control service filtering, disconnect command) into a dedicated class. Existing tests validate no behavior change.

**Files:**
- Create: `bluey/lib/src/connection/lifecycle_client.dart`
- Modify: `bluey/lib/src/connection/bluey_connection.dart`

- [ ] **Step 1: Write the LifecycleClient class**

Create `bluey/lib/src/connection/lifecycle_client.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import '../lifecycle.dart' as lifecycle;
import '../gatt_client/gatt.dart';

/// A function that writes to a characteristic.
typedef WriteCharacteristicFn = Future<void> Function(
  String characteristicUuid,
  Uint8List value,
  bool withResponse,
);

/// A function that reads from a characteristic.
typedef ReadCharacteristicFn = Future<Uint8List> Function(
  String characteristicUuid,
);

/// Client-side lifecycle management.
///
/// Discovers the server's control service, sends periodic heartbeats,
/// and detects server disconnection via write failures. Internal to the
/// Connection bounded context.
class LifecycleClient {
  final int maxFailedHeartbeats;
  final void Function() onServerUnreachable;

  Timer? _heartbeatTimer;
  String? _heartbeatCharUuid;
  WriteCharacteristicFn? _writeFn;
  int _consecutiveFailures = 0;

  LifecycleClient({
    this.maxFailedHeartbeats = 1,
    required this.onServerUnreachable,
  });

  /// Whether the lifecycle heartbeat is currently running.
  bool get isRunning => _heartbeatTimer != null;

  /// Starts the heartbeat if the server hosts the control service.
  ///
  /// [allServices] is the full list of discovered services (including the
  /// control service). [writeFn] and [readFn] are used to communicate with
  /// the server's control service characteristics.
  void start({
    required List<RemoteService> allServices,
    required WriteCharacteristicFn writeFn,
    required ReadCharacteristicFn readFn,
  }) {
    if (_heartbeatTimer != null) return;

    final controlService = allServices
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (controlService == null) return;

    final heartbeatChar = controlService.characteristics
        .where(
          (c) => c.uuid.toString().toLowerCase() == lifecycle.heartbeatCharUuid,
        )
        .firstOrNull;
    if (heartbeatChar == null) return;

    _heartbeatCharUuid = heartbeatChar.uuid.toString();
    _writeFn = writeFn;

    // Send the first heartbeat immediately so the server (especially iOS,
    // which has no connection callback) learns about this client as soon as
    // possible — before the interval read round-trip.
    _sendHeartbeat();

    // Find the interval characteristic and read the server's interval
    final intervalChar = controlService.characteristics
        .where(
          (c) => c.uuid.toString().toLowerCase() == lifecycle.intervalCharUuid,
        )
        .firstOrNull;

    if (intervalChar != null) {
      readFn(intervalChar.uuid.toString()).then((bytes) {
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
    final writeFn = _writeFn;
    if (charUuid == null || writeFn == null) return;

    try {
      await writeFn(charUuid, lifecycle.disconnectValue, false);
    } catch (_) {
      // Best effort — connection may already be lost
    }
  }

  /// Stops the heartbeat and cleans up.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatCharUuid = null;
    _writeFn = null;
    _consecutiveFailures = 0;
  }

  /// Returns true if the given UUID is the control service.
  static bool isControlService(String uuid) {
    return lifecycle.isControlService(uuid);
  }

  /// Filters the control service from a list of services.
  static List<T> filterControlServices<T extends RemoteService>(
    List<T> services,
  ) {
    return services
        .where((s) => !lifecycle.isControlService(s.uuid.toString()))
        .toList();
  }

  Duration get _defaultHeartbeatInterval => Duration(
    milliseconds: lifecycle.defaultLifecycleInterval.inMilliseconds ~/ 2,
  );

  void _beginHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      _sendHeartbeat();
    });
    _sendHeartbeat();
  }

  void _sendHeartbeat() {
    final charUuid = _heartbeatCharUuid;
    final writeFn = _writeFn;
    if (charUuid == null || writeFn == null) return;

    writeFn(charUuid, lifecycle.heartbeatValue, false).then((_) {
      _consecutiveFailures = 0;
    }).catchError((_) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxFailedHeartbeats) {
        stop();
        onServerUnreachable();
      }
    });
  }
}
```

Note: The `withResponse` parameter in `_sendHeartbeat` is `false` for now — this matches the current behavior exactly. Task 4 will change it to `true`.

- [ ] **Step 2: Update BlueyConnection to compose LifecycleClient**

In `bluey/lib/src/connection/bluey_connection.dart`, remove:
- `Timer? _heartbeatTimer;` field
- `String? _heartbeatCharUuid;` field
- `_startHeartbeatIfNeeded()` method
- `_beginHeartbeat()` method
- `_sendHeartbeat()` method
- `_sendDisconnectCommand()` method
- Heartbeat cleanup from `_cleanup()`

Add `LifecycleClient` field and use it:

```dart
import 'lifecycle_client.dart';
```

Add field (after `_cachedServices`):
```dart
late final LifecycleClient _lifecycle;
```

In the constructor, after the existing subscription setup:
```dart
_lifecycle = LifecycleClient(
  onServerUnreachable: _handleServerUnreachable,
);
```

Add the server-unreachable handler:
```dart
void _handleServerUnreachable() {
  _state = ConnectionState.disconnected;
  _stateController.add(_state);
  _cleanup();
}
```

Update `service()`:
```dart
if (LifecycleClient.isControlService(uuid.toString())) {
  throw ServiceNotFoundException(uuid);
}
```

Update `services()`:
```dart
// Start lifecycle heartbeat if the server hosts the control service
_lifecycle.start(
  allServices: allServices,
  writeFn: (charUuid, value, withResponse) =>
      _platform.writeCharacteristic(_connectionId, charUuid, value, withResponse),
  readFn: (charUuid) =>
      _platform.readCharacteristic(_connectionId, charUuid),
);

// Filter the control service from the public result
_cachedServices = LifecycleClient.filterControlServices(allServices);
```

Update `hasService()`:
```dart
if (LifecycleClient.isControlService(uuid.toString())) return false;
```

Update `disconnect()` — replace `_sendDisconnectCommand()`:
```dart
await _lifecycle.sendDisconnectCommand();
```

Update `_cleanup()` — replace heartbeat timer lines:
```dart
_lifecycle.stop();
```

- [ ] **Step 3: Run existing tests to verify no behavior change**

Run: `cd bluey && flutter test`
Expected: All tests pass (424+ tests).

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart bluey/lib/src/connection/bluey_connection.dart
git commit -m "refactor: extract LifecycleClient from BlueyConnection"
```

---

### Task 3: Add maxFailedHeartbeats parameter to connect()

Thread the configuration from the public API to the lifecycle client.

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Modify: `bluey/lib/src/connection/bluey_connection.dart`

- [ ] **Step 1: Add parameter to BlueyConnection constructor**

In `bluey/lib/src/connection/bluey_connection.dart`, add `maxFailedHeartbeats` to the constructor:

```dart
BlueyConnection({
  required platform.BlueyPlatform platformInstance,
  required String connectionId,
  required this.deviceId,
  int maxFailedHeartbeats = 1,
}) : _platform = platformInstance,
     _connectionId = connectionId {
```

And update the `_lifecycle` initialization:
```dart
_lifecycle = LifecycleClient(
  maxFailedHeartbeats: maxFailedHeartbeats,
  onServerUnreachable: _handleServerUnreachable,
);
```

- [ ] **Step 2: Add parameter to Bluey.connect()**

In `bluey/lib/src/bluey.dart`, update the `connect` method signature:

```dart
Future<Connection> connect(
  Device device, {
  Duration? timeout,
  int maxFailedHeartbeats = 1,
}) async {
```

And pass it through to `BlueyConnection`:

```dart
return BlueyConnection(
  platformInstance: _platform,
  connectionId: connectionId,
  deviceId: device.id,
  maxFailedHeartbeats: maxFailedHeartbeats,
);
```

- [ ] **Step 3: Run existing tests**

Run: `cd bluey && flutter test`
Expected: All tests pass (default value preserves existing behavior).

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/bluey.dart bluey/lib/src/connection/bluey_connection.dart
git commit -m "feat: add maxFailedHeartbeats parameter to connect()"
```

---

### Task 4: Change heartbeat characteristic to write-with-response

Update the control service definition and the heartbeat write call.

**Files:**
- Modify: `bluey/lib/src/lifecycle.dart`
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Modify: `bluey/test/lifecycle_test.dart`

- [ ] **Step 1: Update the control service characteristic definition**

In `bluey/lib/src/lifecycle.dart`, change the heartbeat characteristic properties in `buildControlService()`:

```dart
PlatformLocalCharacteristic(
  uuid: _heartbeatCharUuidString,
  properties: const PlatformCharacteristicProperties(
    canRead: false,
    canWrite: true,
    canWriteWithoutResponse: false,
    canNotify: false,
    canIndicate: false,
  ),
  permissions: const [
    PlatformGattPermission.write,
  ],
  descriptors: const [],
),
```

Update the doc comment on `heartbeatCharUuid`:
```dart
/// UUID of the heartbeat characteristic (write-with-response).
final heartbeatCharUuid = _heartbeatCharUuidString;
```

- [ ] **Step 2: Switch heartbeat write to use withResponse: true**

In `bluey/lib/src/connection/lifecycle_client.dart`, in `_sendHeartbeat()`, change the `withResponse` parameter:

```dart
writeFn(charUuid, lifecycle.heartbeatValue, true).then((_) {
```

- [ ] **Step 3: Update existing lifecycle tests for responseNeeded**

In `bluey/test/lifecycle_test.dart`, update all `simulateWriteRequest` calls for heartbeat writes to use `responseNeeded: true` (since write-with-response requires a response):

In the test `'filters heartbeat writes from public writeRequests'` (around line 109):
```dart
await fakePlatform.simulateWriteRequest(
  centralId: _clientId1,
  characteristicUuid: _heartbeatCharUuid,
  value: Uint8List.fromList([0x01]),
  responseNeeded: true,
);
```

In the test `'heartbeat timeout fires disconnect after client opts into lifecycle'` (around line 152):
```dart
fakePlatform.simulateWriteRequest(
  centralId: _clientId1,
  characteristicUuid: _heartbeatCharUuid,
  value: Uint8List.fromList([0x01]),
  responseNeeded: true,
);
```

In the test `'heartbeat resets timer'` (around line 189):
```dart
fakePlatform.simulateWriteRequest(
  centralId: _clientId1,
  characteristicUuid: _heartbeatCharUuid,
  value: Uint8List.fromList([0x01]),
  responseNeeded: true,
);
```

The disconnect command tests keep `responseNeeded: false` — the disconnect command still uses write-without-response since we don't care about the response when leaving.

- [ ] **Step 4: Run tests**

Run: `cd bluey && flutter test test/lifecycle_test.dart`
Expected: All tests pass.

Run: `cd bluey && flutter test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/lifecycle.dart bluey/lib/src/connection/lifecycle_client.dart bluey/test/lifecycle_test.dart
git commit -m "feat: switch heartbeat to write-with-response for server liveness detection"
```

---

### Task 5: Add write failure simulation to FakeBlueyPlatform

Enable testing of heartbeat failure → disconnect flow.

**Files:**
- Modify: `bluey/test/fakes/fake_platform.dart`

- [ ] **Step 1: Add write failure simulation**

In `bluey/test/fakes/fake_platform.dart`, add a field to control write failures:

```dart
/// When true, writeCharacteristic calls will throw to simulate a dead server.
bool simulateWriteFailure = false;
```

Update the `writeCharacteristic` method to check the flag:

```dart
@override
Future<void> writeCharacteristic(
  String deviceId,
  String characteristicUuid,
  Uint8List value,
  bool withResponse,
) async {
  if (simulateWriteFailure) {
    throw Exception('Write failed: server unreachable');
  }

  final connection = _connections[deviceId];
  if (connection == null) {
    throw Exception('Not connected to device: $deviceId');
  }

  connection.peripheral.characteristicValues[characteristicUuid] = value;
}
```

- [ ] **Step 2: Run existing tests to verify no regression**

Run: `cd bluey && flutter test`
Expected: All tests pass (default `simulateWriteFailure = false` preserves existing behavior).

- [ ] **Step 3: Commit**

```bash
git add bluey/test/fakes/fake_platform.dart
git commit -m "test: add write failure simulation to FakeBlueyPlatform"
```

---

### Task 6: Test and verify client-side disconnect detection

Write tests for the new failure-tracking behavior in LifecycleClient, then verify end-to-end.

**Files:**
- Create: `bluey/test/connection/lifecycle_client_test.dart`

- [ ] **Step 1: Write failing test — single heartbeat failure triggers disconnect**

Create `bluey/test/connection/lifecycle_client_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    BlueyPlatform.instance = fakePlatform;
  });

  group('LifecycleClient disconnect detection', () {
    test('disconnects when heartbeat write fails with default maxFailedHeartbeats', () {
      fakeAsync((async) {
        final bluey = Bluey();

        fakePlatform.addFakeDevice(TestDeviceIds.device1);

        // Connect and discover services (which starts heartbeat)
        late Connection connection;
        bluey.connect(Device(
          id: UUID(TestDeviceIds.device1),
          name: 'Test',
          address: TestDeviceIds.device1,
        )).then((c) => connection = c);
        async.elapse(Duration.zero);

        connection.services();
        async.elapse(Duration.zero);

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        // Simulate server going away
        fakePlatform.simulateWriteFailure = true;

        // Advance past the heartbeat interval (default 5s = half of 10s lifecycle)
        async.elapse(const Duration(seconds: 6));

        expect(states, contains(ConnectionState.disconnected));

        bluey.dispose();
      });
    });

    test('does not disconnect when maxFailedHeartbeats allows retries', () {
      fakeAsync((async) {
        final bluey = Bluey();

        fakePlatform.addFakeDevice(TestDeviceIds.device1);

        late Connection connection;
        bluey.connect(
          Device(
            id: UUID(TestDeviceIds.device1),
            name: 'Test',
            address: TestDeviceIds.device1,
          ),
          maxFailedHeartbeats: 3,
        ).then((c) => connection = c);
        async.elapse(Duration.zero);

        connection.services();
        async.elapse(Duration.zero);

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        // Simulate server going away
        fakePlatform.simulateWriteFailure = true;

        // One heartbeat interval — only 1 failure, threshold is 3
        async.elapse(const Duration(seconds: 6));
        expect(states, isNot(contains(ConnectionState.disconnected)));

        // Second failure
        async.elapse(const Duration(seconds: 5));
        expect(states, isNot(contains(ConnectionState.disconnected)));

        // Third failure — should now disconnect
        async.elapse(const Duration(seconds: 5));
        expect(states, contains(ConnectionState.disconnected));

        bluey.dispose();
      });
    });

    test('resets failure count on successful heartbeat', () {
      fakeAsync((async) {
        final bluey = Bluey();

        fakePlatform.addFakeDevice(TestDeviceIds.device1);

        late Connection connection;
        bluey.connect(
          Device(
            id: UUID(TestDeviceIds.device1),
            name: 'Test',
            address: TestDeviceIds.device1,
          ),
          maxFailedHeartbeats: 3,
        ).then((c) => connection = c);
        async.elapse(Duration.zero);

        connection.services();
        async.elapse(Duration.zero);

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        // Fail twice
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 6));
        async.elapse(const Duration(seconds: 5));

        // Server comes back — reset the count
        fakePlatform.simulateWriteFailure = false;
        async.elapse(const Duration(seconds: 5));

        // Fail twice more — should NOT disconnect (count was reset)
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 5));
        expect(states, isNot(contains(ConnectionState.disconnected)));

        // Third consecutive failure — NOW disconnect
        async.elapse(const Duration(seconds: 5));
        expect(states, contains(ConnectionState.disconnected));

        bluey.dispose();
      });
    });
  });
}
```

- [ ] **Step 2: Run tests**

Run: `cd bluey && flutter test test/connection/lifecycle_client_test.dart`
Expected: All 3 tests PASS. The failure counting logic (Task 2) and write-with-response (Task 4) are already in place; these tests verify the end-to-end disconnect detection flow.

Note: If the test infrastructure needs adjustments (e.g., `addFakeDevice` doesn't set up the control service in discovered services), fix the test setup to match how `FakeBlueyPlatform` works.

- [ ] **Step 4: Run full test suite**

Run: `cd bluey && flutter test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/test/connection/lifecycle_client_test.dart
git commit -m "test: add client-side disconnect detection tests"
```

---

### Task 7: Write LifecycleServer unit tests

Extract server-side lifecycle tests into a focused unit test file for the new class.

**Files:**
- Create: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Write LifecycleServer unit tests**

Create `bluey/test/gatt_server/lifecycle_server_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/src/gatt_server/lifecycle_server.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

const _heartbeatCharUuid = 'b1e70002-0000-1000-8000-00805f9b34fb';
const _intervalCharUuid = 'b1e70003-0000-1000-8000-00805f9b34fb';
const _clientId = '00000000-0000-0000-0000-000000000001';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    BlueyPlatform.instance = fakePlatform;
  });

  group('LifecycleServer', () {
    test('handleWriteRequest returns false for non-control characteristics', () {
      final timedOut = <String>[];
      final server = LifecycleServer(
        interval: const Duration(seconds: 5),
        onClientTimedOut: timedOut.add,
      );

      final req = PlatformWriteRequest(
        requestId: 1,
        centralId: _clientId,
        characteristicUuid: '12345678-1234-1234-1234-123456789abc',
        value: Uint8List.fromList([0x01]),
        offset: 0,
        responseNeeded: false,
      );

      expect(server.handleWriteRequest(req, fakePlatform), isFalse);
      server.dispose();
    });

    test('handleWriteRequest returns true and resets timer for heartbeat', () {
      fakeAsync((async) {
        final timedOut = <String>[];
        final server = LifecycleServer(
          interval: const Duration(seconds: 5),
          onClientTimedOut: timedOut.add,
        );

        final req = PlatformWriteRequest(
          requestId: 1,
          centralId: _clientId,
          characteristicUuid: _heartbeatCharUuid,
          value: Uint8List.fromList([0x01]),
          offset: 0,
          responseNeeded: false,
        );

        expect(server.handleWriteRequest(req, fakePlatform), isTrue);

        // Wait less than timeout
        async.elapse(const Duration(seconds: 3));
        expect(timedOut, isEmpty);

        // Wait for full timeout
        async.elapse(const Duration(seconds: 2));
        expect(timedOut, contains(_clientId));

        server.dispose();
      });
    });

    test('disconnect command triggers immediate client timeout callback', () {
      final timedOut = <String>[];
      final server = LifecycleServer(
        interval: const Duration(seconds: 5),
        onClientTimedOut: timedOut.add,
      );

      final req = PlatformWriteRequest(
        requestId: 1,
        centralId: _clientId,
        characteristicUuid: _heartbeatCharUuid,
        value: Uint8List.fromList([0x00]),
        offset: 0,
        responseNeeded: false,
      );

      server.handleWriteRequest(req, fakePlatform);
      expect(timedOut, contains(_clientId));

      server.dispose();
    });

    test('handleReadRequest responds with encoded interval', () {
      final timedOut = <String>[];
      final server = LifecycleServer(
        interval: const Duration(seconds: 15),
        onClientTimedOut: timedOut.add,
      );

      final req = PlatformReadRequest(
        requestId: 1,
        centralId: _clientId,
        characteristicUuid: _intervalCharUuid,
        offset: 0,
      );

      expect(server.handleReadRequest(req, fakePlatform), isTrue);

      server.dispose();
    });

    test('dispose cancels all timers without firing callbacks', () {
      fakeAsync((async) {
        final timedOut = <String>[];
        final server = LifecycleServer(
          interval: const Duration(seconds: 5),
          onClientTimedOut: timedOut.add,
        );

        // Start a timer via heartbeat
        final req = PlatformWriteRequest(
          requestId: 1,
          centralId: _clientId,
          characteristicUuid: _heartbeatCharUuid,
          value: Uint8List.fromList([0x01]),
          offset: 0,
          responseNeeded: false,
        );
        server.handleWriteRequest(req, fakePlatform);

        server.dispose();

        // Advancing past timeout should not fire callback
        async.elapse(const Duration(seconds: 10));
        expect(timedOut, isEmpty);
      });
    });
  });
}
```

- [ ] **Step 2: Run tests**

Run: `cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart`
Expected: All 5 tests pass.

- [ ] **Step 3: Commit**

```bash
git add bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "test: add LifecycleServer unit tests"
```
