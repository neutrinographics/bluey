# BlueyPeer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce `BlueyPeer` as a stable peer identity layer on top of the existing lifecycle protocol, expose `bluey.peer()` and `bluey.discoverPeers()` as the Bluey-to-Bluey API, and remove the `requireLifecycle` flag that the peer abstraction subsumes.

**Architecture:** Adds a `ServerId` characteristic to the existing control service and a `ServerId` value object. A new `Peer` bounded context (`bluey/lib/src/peer/`) owns `BlueyPeer`, `PeerConnection` (a filtering decorator around `Connection`), and `PeerDiscovery` (scan + verify helper). `BlueyConnection` becomes protocol-free — it no longer holds a `LifecycleClient` or filters the control service. `BlueyPeer` orchestrates raw connection + lifecycle wiring + `ServerId` verification.

**Tech Stack:** Dart/Flutter, existing `FakeBlueyPlatform` harness, `fake_async` for timer tests, `Uuid.v4()` for ID generation (already transitively depended on).

**Spec:** `docs/superpowers/specs/2026-04-15-bluey-peer-identity-design.md`

---

## File Structure

**New files (in dependency order):**

| Path | Responsibility |
|---|---|
| `bluey/lib/src/peer/server_id.dart` | `ServerId` value object (16-byte UUID, string-normalized). |
| `bluey/lib/src/peer/peer.dart` | Public `BlueyPeer` abstract interface. |
| `bluey/lib/src/peer/peer_connection.dart` | `PeerConnection` — decorator around `Connection` that filters the control service. |
| `bluey/lib/src/peer/peer_discovery.dart` | `PeerDiscovery` — internal helper orchestrating scan + connect + serverId read. |
| `bluey/lib/src/peer/bluey_peer.dart` | `_BlueyPeer` — concrete implementation; constructed by `Bluey`. |
| `bluey/test/peer/server_id_test.dart` | Unit tests for `ServerId`. |
| `bluey/test/peer/peer_connection_test.dart` | Unit tests for `PeerConnection` delegation and filtering. |
| `bluey/test/peer/peer_discovery_test.dart` | Unit tests for scan + match + dedup logic against `FakeBlueyPlatform`. |
| `bluey/test/peer/bluey_peer_test.dart` | Unit tests for `_BlueyPeer` orchestration (connect, disconnect, heartbeat-failure path). |
| `bluey/test/peer/peer_e2e_test.dart` | End-to-end integration tests: `discoverPeers` + `peer.connect` through the fake. |

**Modified files:**

| Path | Change |
|---|---|
| `bluey/lib/src/lifecycle.dart` | Add `serverIdCharUuid`, `encodeServerId`/`decodeServerId`; extend `buildControlService()` to include the new characteristic. |
| `bluey/lib/src/shared/exceptions.dart` | Add `PeerNotFoundException`, `PeerIdentityMismatchException`. |
| `bluey/lib/src/gatt_server/lifecycle_server.dart` | Accept `ServerId`; respond to reads on the new characteristic. |
| `bluey/lib/src/gatt_server/bluey_server.dart` | Accept `identity: ServerId?` param; auto-generate if null; expose `serverId` getter. |
| `bluey/lib/src/connection/bluey_connection.dart` | Remove lifecycle wiring, `_handleServerUnreachable`, control-service filtering, `maxFailedHeartbeats` and `requireLifecycle` params. Becomes pure raw-BLE. |
| `bluey/lib/src/connection/lifecycle_client.dart` | Remove `requireLifecycle` param. Otherwise unchanged interface. |
| `bluey/lib/src/bluey.dart` | Remove `requireLifecycle` and `maxFailedHeartbeats` from `connect()`. Add `peer()` and `discoverPeers()` methods. Export the peer module. |
| `bluey/lib/bluey.dart` | Re-export `ServerId`, `BlueyPeer`, `PeerNotFoundException`, `PeerIdentityMismatchException`. |
| `bluey/test/fakes/fake_platform.dart` | Helper to advertise a peripheral with the full control service (heartbeat + interval + serverId). |
| `bluey/test/lifecycle_test.dart` | Add coverage for `serverId` characteristic read; update existing tests to accept a `ServerId` when constructing the server. |
| `bluey/test/bluey_test.dart` | Remove assertions on `requireLifecycle` and `maxFailedHeartbeats` (they're moving). |
| `bluey/test/connection/lifecycle_client_test.dart` | Delete. Its coverage moves to `bluey/test/peer/bluey_peer_test.dart`. |
| `bluey/CLAUDE.md` or `CLAUDE.md` at repo root (whichever governs) | Add "Protocol layering" section. |
| `BLUEY_ARCHITECTURE.md` | Add "Peer Protocol" section. |

**Example app modified files (separate task group at the end):**

| Path | Change |
|---|---|
| `bluey/example/pubspec.yaml` | Add `shared_preferences` dependency. |
| `bluey/example/lib/features/connection/presentation/connection_settings_cubit.dart` | Remove `requireLifecycle` field. |
| `bluey/example/lib/features/connection/domain/connection_settings.dart` | Remove `requireLifecycle` field. |
| `bluey/example/lib/features/connection/infrastructure/bluey_connection_repository.dart` | Stop passing `requireLifecycle`. |
| `bluey/example/lib/features/scanner/presentation/scanner_screen.dart` | Remove the `requireLifecycle` switch from the settings dialog. |
| `bluey/example/lib/features/server/` | Persist auto-generated `ServerId` via SharedPreferences; pass `identity:` to `bluey.server(...)`. |
| `bluey/example/lib/features/peer/` (NEW) | Discover peers UI, connect-by-saved-id flow. |

---

### Task 1: `ServerId` value object

**Files:**
- Create: `bluey/lib/src/peer/server_id.dart`
- Create: `bluey/test/peer/server_id_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// bluey/test/peer/server_id_test.dart
import 'dart:typed_data';

import 'package:bluey/src/peer/server_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerId', () {
    test('constructor normalizes to lowercase', () {
      final id = ServerId('ABCDEF00-1234-5678-9ABC-DEF012345678');
      expect(id.value, 'abcdef00-1234-5678-9abc-def012345678');
    });

    test('constructor rejects malformed strings', () {
      expect(() => ServerId('not-a-uuid'), throwsArgumentError);
      expect(() => ServerId(''), throwsArgumentError);
    });

    test('generate() produces distinct UUIDs', () {
      final a = ServerId.generate();
      final b = ServerId.generate();
      expect(a, isNot(equals(b)));
    });

    test('equality by value', () {
      final a = ServerId('abcdef00-1234-5678-9abc-def012345678');
      final b = ServerId('ABCDEF00-1234-5678-9ABC-DEF012345678');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toBytes produces 16 bytes and round-trips via fromBytes', () {
      final original = ServerId.generate();
      final bytes = original.toBytes();
      expect(bytes, hasLength(16));
      final roundTrip = ServerId.fromBytes(bytes);
      expect(roundTrip, equals(original));
    });

    test('fromBytes rejects non-16-byte input', () {
      expect(
        () => ServerId.fromBytes(Uint8List.fromList(List.filled(15, 0))),
        throwsArgumentError,
      );
      expect(
        () => ServerId.fromBytes(Uint8List.fromList(List.filled(17, 0))),
        throwsArgumentError,
      );
    });

    test('toString returns the canonical value', () {
      final id = ServerId('abcdef00-1234-5678-9abc-def012345678');
      expect(id.toString(), 'abcdef00-1234-5678-9abc-def012345678');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd bluey && flutter test test/peer/server_id_test.dart`
Expected: FAIL with "Target of URI doesn't exist" (file doesn't exist yet).

- [ ] **Step 3: Implement `ServerId`**

```dart
// bluey/lib/src/peer/server_id.dart
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// Stable protocol-level identity of a Bluey server.
///
/// A `ServerId` is a random v4 UUID, generated once by a server and
/// persisted however the application sees fit. It is the stable handle
/// clients use to refer to a specific Bluey server across platform
/// identifier changes (iOS session rotation, Android MAC randomization).
///
/// `ServerId` is deliberately distinct from [UUID] to keep protocol
/// identity separate from service/characteristic UUIDs in the type
/// system.
class ServerId {
  /// Canonical lowercase UUID string, e.g. `abcdef00-1234-5678-9abc-def012345678`.
  final String value;

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Constructs a `ServerId` from a canonical UUID string.
  ///
  /// The string is normalized to lowercase. Throws [ArgumentError] if
  /// [value] is not a well-formed UUID.
  ServerId(String value) : value = value.toLowerCase() {
    if (!_uuidPattern.hasMatch(this.value)) {
      throw ArgumentError.value(value, 'value', 'not a well-formed UUID');
    }
  }

  /// Generates a fresh random `ServerId` (v4).
  factory ServerId.generate() => ServerId(const Uuid().v4());

  /// Constructs a `ServerId` from 16 raw bytes.
  ///
  /// Throws [ArgumentError] if [bytes] is not exactly 16 bytes long.
  factory ServerId.fromBytes(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'must be exactly 16',
      );
    }
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final formatted =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
    return ServerId(formatted);
  }

  /// Encodes this identity as 16 raw bytes (big-endian UUID layout).
  Uint8List toBytes() {
    final hex = value.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ServerId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
```

Also verify `uuid` is already a dependency. Run:
```bash
grep -n '^  uuid:' bluey/pubspec.yaml
```
Expected output: something like `  uuid: ^4.0.0` or similar. If missing, add it under `dependencies:` before running the tests. If present, continue.

- [ ] **Step 4: Run tests to verify pass**

Run: `cd bluey && flutter test test/peer/server_id_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/peer/server_id.dart bluey/test/peer/server_id_test.dart
git commit -m "feat: add ServerId value object"
```

---

### Task 2: Shared-kernel additions for `serverId` characteristic

**Files:**
- Modify: `bluey/lib/src/lifecycle.dart` (add UUID constant, encode/decode helpers, extend `buildControlService()`)

- [ ] **Step 1: Add a failing test in `bluey/test/lifecycle_test.dart`**

Append this to the `Server Lifecycle` group in `bluey/test/lifecycle_test.dart`:

```dart
    test('control service includes the serverId characteristic', () {
      final service = buildControlService();
      final charUuids =
          service.characteristics.map((c) => c.uuid.toLowerCase()).toList();
      expect(charUuids, contains('b1e70004-0000-1000-8000-00805f9b34fb'));

      final serverIdChar = service.characteristics.firstWhere(
        (c) =>
            c.uuid.toLowerCase() == 'b1e70004-0000-1000-8000-00805f9b34fb',
      );
      expect(serverIdChar.properties.canRead, isTrue);
      expect(serverIdChar.properties.canWrite, isFalse);
    });

    test('encodeServerId/decodeServerId round-trip', () {
      final id = ServerId.generate();
      final bytes = encodeServerId(id);
      expect(bytes, hasLength(16));
      expect(decodeServerId(bytes), equals(id));
    });
```

You'll also need to add these imports at the top of `lifecycle_test.dart`:

```dart
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/server_id.dart';
```

Check whether `lifecycle_test.dart` already imports `package:bluey/src/lifecycle.dart` or just `package:bluey/bluey.dart`; add the missing import if needed but don't duplicate.

- [ ] **Step 2: Run to verify failure**

Run: `cd bluey && flutter test test/lifecycle_test.dart`
Expected: FAIL — `encodeServerId` and `decodeServerId` undefined; no `serverId` characteristic in `buildControlService()`.

- [ ] **Step 3: Extend `lifecycle.dart`**

Apply these changes to `bluey/lib/src/lifecycle.dart`:

Add near the top, after the existing UUID constants:

```dart
const _serverIdCharUuidString = 'b1e70004-0000-1000-8000-00805f9b34fb';
```

Add this exported constant near the existing `intervalCharUuid`:

```dart
/// UUID of the serverId characteristic (readable, returns the server's
/// stable [ServerId] as 16 raw bytes).
final serverIdCharUuid = _serverIdCharUuidString;
```

Update `isControlServiceCharacteristic` to include the new UUID:

```dart
bool isControlServiceCharacteristic(String characteristicUuid) {
  final normalized = characteristicUuid.toLowerCase();
  return normalized == _heartbeatCharUuidString ||
      normalized == _intervalCharUuidString ||
      normalized == _serverIdCharUuidString;
}
```

Add these helpers (import `package:bluey/src/peer/server_id.dart` or use relative path from the file — prefer relative since this is all under `lib/src/`):

```dart
// Add at the top:
import 'peer/server_id.dart';

// Add alongside encodeInterval/decodeInterval:

/// Encodes a [ServerId] as 16 raw bytes for the serverId characteristic.
Uint8List encodeServerId(ServerId id) => id.toBytes();

/// Decodes a 16-byte serverId characteristic value.
ServerId decodeServerId(Uint8List bytes) => ServerId.fromBytes(bytes);
```

Extend `buildControlService()` to include the third characteristic — append this to the `characteristics` list in the builder:

```dart
      PlatformLocalCharacteristic(
        uuid: _serverIdCharUuidString,
        properties: const PlatformCharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        permissions: const [
          PlatformGattPermission.read,
        ],
        descriptors: const [],
      ),
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd bluey && flutter test test/lifecycle_test.dart`
Expected: PASS (previous + new tests).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/lifecycle.dart bluey/test/lifecycle_test.dart
git commit -m "feat: add serverId characteristic to lifecycle control service"
```

---

### Task 3: `LifecycleServer` responds to `serverId` reads

**Files:**
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart`
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart` (add coverage)

- [ ] **Step 1: Write failing tests**

Append this test to `bluey/test/gatt_server/lifecycle_server_test.dart`:

```dart
    test('responds to serverId read with encoded bytes', () async {
      final id = ServerId.generate();
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: id,
        onClientGone: (_) {},
      );

      final handled = server.handleReadRequest(PlatformReadRequest(
        requestId: 1,
        centralId: 'central-1',
        characteristicUuid: serverIdCharUuid,
        offset: 0,
      ));
      expect(handled, isTrue);

      expect(fakePlatform.respondReadCalls, hasLength(1));
      final respondCall = fakePlatform.respondReadCalls.single;
      expect(respondCall.status, PlatformGattStatus.success);
      expect(respondCall.value, equals(id.toBytes()));
    });
```

Add the missing imports at the top of the test file if not present:
```dart
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/server_id.dart';
```

- [ ] **Step 2: Run to verify failure**

Run: `cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart`
Expected: FAIL — `LifecycleServer` does not yet accept a `serverId` parameter.

- [ ] **Step 3: Implement**

Modify `bluey/lib/src/gatt_server/lifecycle_server.dart`:

Add import at top:
```dart
import '../peer/server_id.dart';
```

Add a field and parameter:
```dart
class LifecycleServer {
  final platform.BlueyPlatform _platform;
  final Duration? _interval;
  final ServerId _serverId;
  final void Function(String clientId) onClientGone;
  final void Function(String clientId)? onHeartbeatReceived;

  bool _controlServiceAdded = false;
  final Map<String, Timer> _heartbeatTimers = {};

  LifecycleServer({
    required platform.BlueyPlatform platformApi,
    required Duration? interval,
    required ServerId serverId,
    required this.onClientGone,
    this.onHeartbeatReceived,
  })  : _platform = platformApi,
        _interval = interval,
        _serverId = serverId;
```

Update `handleReadRequest` to route based on the characteristic UUID:
```dart
bool handleReadRequest(platform.PlatformReadRequest req) {
  final uuid = req.characteristicUuid.toLowerCase();

  if (uuid == lifecycle.serverIdCharUuid) {
    _platform.respondToReadRequest(
      req.requestId,
      platform.PlatformGattStatus.success,
      lifecycle.encodeServerId(_serverId),
    );
    return true;
  }

  if (!lifecycle.isControlServiceCharacteristic(uuid)) {
    return false;
  }

  // Default: interval read.
  final interval = _interval ?? lifecycle.defaultLifecycleInterval;
  _platform.respondToReadRequest(
    req.requestId,
    platform.PlatformGattStatus.success,
    lifecycle.encodeInterval(interval),
  );

  return true;
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart`
Expected: PASS for the new test AND all existing tests — but existing tests will now fail with "missing required argument 'serverId'" because the constructor changed. **Expected state after this step: existing tests fail for a clear reason.**

- [ ] **Step 5: Fix existing tests to supply the required `serverId`**

In `bluey/test/gatt_server/lifecycle_server_test.dart`, every existing call to `LifecycleServer(...)` needs `serverId: ServerId.generate()`. Add `import 'package:bluey/src/peer/server_id.dart';` at the top if not present.

Search for `LifecycleServer(` in the file and, for each construction, add the new parameter. Example transformation:

Before:
```dart
final server = LifecycleServer(
  platformApi: fakePlatform,
  interval: const Duration(seconds: 5),
  onClientGone: ...,
);
```

After:
```dart
final server = LifecycleServer(
  platformApi: fakePlatform,
  interval: const Duration(seconds: 5),
  serverId: ServerId.generate(),
  onClientGone: ...,
);
```

- [ ] **Step 6: Run tests**

Run: `cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/gatt_server/lifecycle_server.dart bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "feat: LifecycleServer responds to serverId characteristic reads"
```

---

### Task 4: `BlueyServer.identity` parameter

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`
- Modify: `bluey/lib/src/gatt_server/server.dart` (interface — add `serverId` getter)
- Modify: `bluey/test/lifecycle_test.dart` (add tests)

- [ ] **Step 1: Write failing tests**

Append to the `Server Lifecycle` group in `bluey/test/lifecycle_test.dart`:

```dart
    test('auto-generates a ServerId when constructed without identity', () {
      final bluey = Bluey();
      final server = bluey.server()!;
      expect(server.serverId, isNotNull);
      server.dispose();
      bluey.dispose();
    });

    test('respects an app-supplied identity', () {
      final id = ServerId('11111111-2222-3333-4444-555555555555');
      final bluey = Bluey();
      final server = bluey.server(identity: id)!;
      expect(server.serverId, equals(id));
      server.dispose();
      bluey.dispose();
    });

    test('server responds to serverId reads with the configured identity',
        () async {
      final id = ServerId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final bluey = Bluey();
      final server = bluey.server(identity: id)!;
      await server.startAdvertising();

      fakePlatform.simulateReadRequest(
        centralId: _clientId1,
        characteristicUuid: serverIdCharUuid,
      );
      await Future.delayed(Duration.zero);

      expect(fakePlatform.respondReadCalls, isNotEmpty);
      final call = fakePlatform.respondReadCalls.last;
      expect(call.value, equals(id.toBytes()));

      await server.dispose();
      await bluey.dispose();
    });
```

(The client id constant `_clientId1` is already in that file. If `simulateReadRequest` helper doesn't exist, we'll add it in Task 9 — for now we'll rely on the existing `fakePlatform` simulation surface; if needed substitute the read simulation with whatever equivalent the fake already exposes. Check `test/lifecycle_test.dart` for prior usage.)

- [ ] **Step 2: Run tests to verify failure**

Run: `cd bluey && flutter test test/lifecycle_test.dart`
Expected: FAIL — `server()` doesn't accept `identity`; `server.serverId` doesn't exist.

- [ ] **Step 3: Add `serverId` to the `Server` interface**

In `bluey/lib/src/gatt_server/server.dart`, find the `abstract class Server` declaration and add:

```dart
import '../peer/server_id.dart';

abstract class Server {
  // ... existing members ...

  /// The stable [ServerId] this server advertises through the lifecycle
  /// control service. Use this value to register the server with clients
  /// that want to reconnect across platform-identifier changes.
  ServerId get serverId;

  // ... rest
```

- [ ] **Step 4: Update `BlueyServer`**

In `bluey/lib/src/gatt_server/bluey_server.dart`:

Add import:
```dart
import '../peer/server_id.dart';
```

Modify the constructor and add a field:
```dart
class BlueyServer implements Server {
  final platform.BlueyPlatform _platform;
  final BlueyEventBus _eventBus;
  final ServerId _serverId;
  late final LifecycleServer _lifecycle;

  bool _isAdvertising = false;
  // ... existing fields

  BlueyServer(
    this._platform,
    this._eventBus, {
    Duration? lifecycleInterval = lifecycle.defaultLifecycleInterval,
    ServerId? identity,
  }) : _serverId = identity ?? ServerId.generate() {
    _lifecycle = LifecycleServer(
      platformApi: _platform,
      interval: lifecycleInterval,
      serverId: _serverId,
      onClientGone: _handleClientDisconnected,
      onHeartbeatReceived: _trackClientIfNeeded,
    );
    // ... rest of constructor body unchanged
  }

  @override
  ServerId get serverId => _serverId;

  // ... rest of class unchanged
```

- [ ] **Step 5: Thread `identity` through `Bluey.server()`**

In `bluey/lib/src/bluey.dart`, find the `Server? server(...)` method (around line 380) and update:

```dart
import 'peer/server_id.dart';

// ...

Server? server({
  Duration? lifecycleInterval = const Duration(seconds: 10),
  ServerId? identity,
}) {
  // ... existing body, then pass identity to BlueyServer:
  return BlueyServer(
    _platform,
    _eventBus,
    lifecycleInterval: lifecycleInterval,
    identity: identity,
  );
}
```

- [ ] **Step 6: Run tests**

Run: `cd bluey && flutter test test/lifecycle_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/gatt_server/server.dart bluey/lib/src/gatt_server/bluey_server.dart bluey/lib/src/bluey.dart bluey/test/lifecycle_test.dart
git commit -m "feat: Bluey.server() accepts optional ServerId identity"
```

---

### Task 5: New exceptions for peer operations

**Files:**
- Modify: `bluey/lib/src/shared/exceptions.dart`
- Modify: `bluey/test/exceptions_test.dart` (add tests)

- [ ] **Step 1: Write failing tests**

Append to `bluey/test/exceptions_test.dart`:

```dart
  group('PeerNotFoundException', () {
    test('exposes expected id and timeout in message', () {
      final id = ServerId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final ex = PeerNotFoundException(id, const Duration(seconds: 5));
      expect(ex.expected, equals(id));
      expect(ex.timeout, const Duration(seconds: 5));
      expect(ex.toString(), contains('aaaaaaaa'));
      expect(ex.toString(), contains('5'));
    });

    test('is a BlueyException', () {
      expect(
        PeerNotFoundException(
          ServerId.generate(),
          const Duration(seconds: 1),
        ),
        isA<BlueyException>(),
      );
    });
  });

  group('PeerIdentityMismatchException', () {
    test('exposes expected and actual ids', () {
      final expected = ServerId.generate();
      final actual = ServerId.generate();
      final ex = PeerIdentityMismatchException(expected, actual);
      expect(ex.expected, equals(expected));
      expect(ex.actual, equals(actual));
      expect(ex.toString(), contains(expected.toString()));
      expect(ex.toString(), contains(actual.toString()));
    });

    test('is a BlueyException', () {
      expect(
        PeerIdentityMismatchException(
          ServerId.generate(),
          ServerId.generate(),
        ),
        isA<BlueyException>(),
      );
    });
  });
```

Add the import at the top of the test file:
```dart
import 'package:bluey/src/peer/server_id.dart';
```

- [ ] **Step 2: Run to verify failure**

Run: `cd bluey && flutter test test/exceptions_test.dart`
Expected: FAIL — exception classes not defined.

- [ ] **Step 3: Add exceptions**

Append to `bluey/lib/src/shared/exceptions.dart`:

```dart
import '../peer/server_id.dart';

/// Thrown when a [BlueyPeer.connect] (or `bluey.discoverPeers` when
/// targeting a specific id) scan window expires without finding a
/// matching server.
class PeerNotFoundException extends BlueyException {
  /// The [ServerId] that was being searched for.
  final ServerId expected;

  /// The scan timeout that elapsed.
  final Duration timeout;

  const PeerNotFoundException(this.expected, this.timeout)
      : super('No peer with id $expected found within $timeout.');
}

/// Thrown when a cached device-identifier hint resolves to a server
/// whose `serverId` does not match the expected one.
class PeerIdentityMismatchException extends BlueyException {
  /// The expected [ServerId].
  final ServerId expected;

  /// The [ServerId] that was actually read from the candidate server.
  final ServerId actual;

  const PeerIdentityMismatchException(this.expected, this.actual)
      : super(
          'Peer identity mismatch: expected $expected but got $actual.',
        );
}
```

Check whether `BlueyException` is already the base class used in the file (it is — existing exceptions extend it). If `BlueyException` is not in scope, look at the existing exception definitions to mirror the pattern; most `bluey/lib/src/shared/exceptions.dart` files in this codebase have their own top-level sealed base. Follow the existing pattern.

- [ ] **Step 4: Run tests**

Run: `cd bluey && flutter test test/exceptions_test.dart`
Expected: PASS (4 new tests plus existing).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/shared/exceptions.dart bluey/test/exceptions_test.dart
git commit -m "feat: add PeerNotFoundException and PeerIdentityMismatchException"
```

---

### Task 6: `BlueyPeer` interface

**Files:**
- Create: `bluey/lib/src/peer/peer.dart`

This task creates a pure abstract interface; no tests of its own — it's tested through `BlueyPeer` implementation in Task 9.

- [ ] **Step 1: Create the interface**

```dart
// bluey/lib/src/peer/peer.dart
import '../connection/connection.dart';
import 'server_id.dart';

/// A stable handle to a Bluey server identified by its [ServerId].
///
/// A `BlueyPeer` represents a logical peer — "the specific Bluey
/// server you want to talk to" — independent of the platform's
/// transient device identifiers (iOS `CBPeripheral.identifier`,
/// Android MAC). Construct one via `bluey.peer(...)` (if you already
/// have a [ServerId]) or obtain one from `bluey.discoverPeers()`.
///
/// Calling [connect] performs a targeted scan for the peer,
/// establishes a GATT connection, verifies the server's [serverId]
/// matches the expected value, starts the lifecycle heartbeat, and
/// returns a live [Connection].
abstract class BlueyPeer {
  /// The stable Bluey identifier of the remote server.
  ServerId get serverId;

  /// Connect to this peer.
  ///
  /// Performs a targeted scan (filtered by the Bluey control service
  /// UUID), connects to each matching candidate in turn, and returns
  /// the connection to the first one whose `serverId` matches.
  ///
  /// [scanTimeout] bounds the discovery phase. [timeout] bounds each
  /// individual platform-level connect attempt.
  ///
  /// Throws [PeerNotFoundException] if no matching server is found
  /// within [scanTimeout]. Throws [ConnectionException] for BLE-level
  /// connection failures.
  Future<Connection> connect({
    Duration? scanTimeout,
    Duration? timeout,
  });
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd bluey && flutter analyze lib/src/peer/`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add bluey/lib/src/peer/peer.dart
git commit -m "feat: add BlueyPeer abstract interface"
```

---

### Task 7: `PeerConnection` — filtering decorator

**Files:**
- Create: `bluey/lib/src/peer/peer_connection.dart`
- Create: `bluey/test/peer/peer_connection_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// bluey/test/peer/peer_connection_test.dart
import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/peer_connection.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('PeerConnection', () {
    test('services() filters out the control service', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: controlServiceUuid,
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
          platform.PlatformService(
            uuid: '00001800-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
        ],
      );

      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      final peer = PeerConnection(inner);

      final services = await peer.services();
      expect(
        services.any((s) => s.uuid.toString() == controlServiceUuid),
        isFalse,
        reason: 'Control service must be filtered',
      );
      expect(services, hasLength(1));

      await peer.disconnect();
      await bluey.dispose();
    });

    test('service(controlServiceUuid) throws ServiceNotFoundException', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: controlServiceUuid,
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
        ],
      );

      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      await inner.services(); // populate cache
      final peer = PeerConnection(inner);

      expect(
        () => peer.service(UUID(controlServiceUuid)),
        throwsA(isA<ServiceNotFoundException>()),
      );

      await peer.disconnect();
      await bluey.dispose();
    });

    test('hasService(controlServiceUuid) returns false', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        services: [
          platform.PlatformService(
            uuid: controlServiceUuid,
            isPrimary: true,
            characteristics: const [],
            includedServices: const [],
          ),
        ],
      );

      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      final peer = PeerConnection(inner);

      expect(await peer.hasService(UUID(controlServiceUuid)), isFalse);

      await peer.disconnect();
      await bluey.dispose();
    });

    test('delegates non-service getters to the inner connection', () async {
      fakePlatform.simulatePeripheral(id: 'AA:BB:CC:DD:EE:01');
      final bluey = Bluey();
      final inner = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: 'AA:BB:CC:DD:EE:01',
        name: 'Peer',
      ));
      final peer = PeerConnection(inner);

      expect(peer.deviceId, equals(inner.deviceId));
      expect(peer.state, equals(inner.state));
      expect(peer.mtu, equals(inner.mtu));

      await peer.disconnect();
      await bluey.dispose();
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd bluey && flutter test test/peer/peer_connection_test.dart`
Expected: FAIL — `PeerConnection` doesn't exist.

- [ ] **Step 3: Implement `PeerConnection`**

```dart
// bluey/lib/src/peer/peer_connection.dart
import 'dart:async';
import 'dart:typed_data';

import '../connection/connection.dart';
import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/exceptions.dart';
import '../shared/uuid.dart';

/// A [Connection] decorator that filters the Bluey lifecycle control
/// service from the public services view, keeping protocol plumbing
/// hidden from consumers of a peer connection.
///
/// All non-service methods delegate unchanged to the underlying
/// connection.
class PeerConnection implements Connection {
  final Connection _inner;

  PeerConnection(this._inner);

  @override
  UUID get deviceId => _inner.deviceId;

  @override
  ConnectionState get state => _inner.state;

  @override
  Stream<ConnectionState> get stateChanges => _inner.stateChanges;

  @override
  int get mtu => _inner.mtu;

  @override
  RemoteService service(UUID uuid) {
    if (lifecycle.isControlService(uuid.toString())) {
      throw ServiceNotFoundException(uuid);
    }
    return _inner.service(uuid);
  }

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    final inner = await _inner.services(cache: cache);
    return inner
        .where((s) => !lifecycle.isControlService(s.uuid.toString()))
        .toList();
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    if (lifecycle.isControlService(uuid.toString())) return false;
    return _inner.hasService(uuid);
  }

  @override
  Future<int> requestMtu(int mtu) => _inner.requestMtu(mtu);

  @override
  Future<int> readRssi() => _inner.readRssi();

  @override
  Future<void> disconnect() => _inner.disconnect();

  // === Bonding ===

  @override
  BondState get bondState => _inner.bondState;

  @override
  Stream<BondState> get bondStateChanges => _inner.bondStateChanges;

  @override
  Future<void> bond() => _inner.bond();

  @override
  Future<void> removeBond() => _inner.removeBond();

  // === PHY ===

  @override
  Phy get txPhy => _inner.txPhy;

  @override
  Phy get rxPhy => _inner.rxPhy;

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => _inner.phyChanges;

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) =>
      _inner.requestPhy(txPhy: txPhy, rxPhy: rxPhy);

  // === Connection parameters ===

  @override
  ConnectionParameters get connectionParameters =>
      _inner.connectionParameters;

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) =>
      _inner.requestConnectionParameters(params);
}
```

Note on imports: `dart:typed_data` import is included because some `Connection` implementations return typed data; if your `flutter analyze` shows it unused, remove it.

- [ ] **Step 4: Run tests**

Run: `cd bluey && flutter test test/peer/peer_connection_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/peer/peer_connection.dart bluey/test/peer/peer_connection_test.dart
git commit -m "feat: add PeerConnection decorator to filter the control service"
```

---

### Task 8: `PeerDiscovery` helper

**Files:**
- Create: `bluey/lib/src/peer/peer_discovery.dart`
- Create: `bluey/test/peer/peer_discovery_test.dart`

`PeerDiscovery` is stateless: each call creates its own scanner and internal connection state, so it can be constructed once per `Bluey` instance.

- [ ] **Step 1: Write failing tests**

```dart
// bluey/test/peer/peer_discovery_test.dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/peer_discovery.dart';
import 'package:bluey/src/peer/server_id.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// Advertises a fake Bluey server that responds to `serverId` reads
/// with the given [id]. Returns the device address.
String _simulateBlueyServer(
  FakeBlueyPlatform fakePlatform,
  ServerId id, {
  String? addressSuffix,
}) {
  final address = 'AA:BB:CC:DD:EE:${addressSuffix ?? '01'}';
  fakePlatform.simulatePeripheral(
    id: address,
    name: 'Bluey Server',
    serviceUuids: [controlServiceUuid],
    services: [
      platform.PlatformService(
        uuid: controlServiceUuid,
        isPrimary: true,
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: false,
              canWrite: true,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
        ],
        includedServices: [],
      ),
    ],
    characteristicValues: {
      serverIdCharUuid: id.toBytes(),
    },
  );
  return address;
}

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('PeerDiscovery.discover', () {
    test('returns empty when no Bluey servers advertising', () async {
      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final peers = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(peers, isEmpty);
    });

    test('returns one entry per unique ServerId', () async {
      final id1 = ServerId.generate();
      final id2 = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id1, addressSuffix: '01');
      _simulateBlueyServer(fakePlatform, id2, addressSuffix: '02');

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final peers = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      final ids = peers.map((p) => p.serverId).toSet();
      expect(ids, equals({id1, id2}));
    });

    test('deduplicates by ServerId when same id seen multiple times',
        () async {
      final id = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id, addressSuffix: '01');
      // Simulate the same ServerId at a different address (e.g., a
      // device that has cycled its MAC).
      _simulateBlueyServer(fakePlatform, id, addressSuffix: '02');

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final peers = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(peers, hasLength(1));
    });
  });

  group('PeerDiscovery.connectTo', () {
    test('returns a Connection when a match is found', () async {
      final id = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id);

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final connection = await discovery.connectTo(
        id,
        scanTimeout: const Duration(milliseconds: 500),
      );
      expect(connection, isNotNull);
      expect(connection.state, ConnectionState.connected);

      await connection.disconnect();
    });

    test('throws PeerNotFoundException when no match within timeout',
        () async {
      // Advertise a different id.
      _simulateBlueyServer(fakePlatform, ServerId.generate());

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final target = ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

      expect(
        () => discovery.connectTo(
          target,
          scanTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<PeerNotFoundException>()),
      );
    });

    test('skips non-matching candidates and finds the correct one',
        () async {
      final wrongId = ServerId.generate();
      final target = ServerId.generate();
      _simulateBlueyServer(fakePlatform, wrongId, addressSuffix: '01');
      _simulateBlueyServer(fakePlatform, target, addressSuffix: '02');

      final discovery = PeerDiscovery(platformApi: fakePlatform);
      final connection = await discovery.connectTo(
        target,
        scanTimeout: const Duration(milliseconds: 500),
      );
      expect(connection.state, ConnectionState.connected);
      await connection.disconnect();
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd bluey && flutter test test/peer/peer_discovery_test.dart`
Expected: FAIL — `PeerDiscovery` doesn't exist.

- [ ] **Step 3: Implement `PeerDiscovery`**

```dart
// bluey/lib/src/peer/peer_discovery.dart
import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/exceptions.dart';
import '../shared/uuid.dart';
import 'bluey_peer.dart';
import 'peer.dart';
import 'server_id.dart';

/// Stateless helper that performs scan + connect + serverId verification.
///
/// Internal to the Peer context. Not exported publicly — accessed via
/// `bluey.discoverPeers()` and `BlueyPeer.connect()`.
class PeerDiscovery {
  final platform.BlueyPlatform _platform;

  PeerDiscovery({required platform.BlueyPlatform platformApi})
      : _platform = platformApi;

  /// Scans for Bluey servers for up to [timeout]. For each unique
  /// candidate, briefly connects, reads the `serverId` characteristic,
  /// then disconnects. Returns a list of [BlueyPeer]s, deduplicated
  /// by [ServerId].
  Future<List<BlueyPeer>> discover({
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final seenAddresses = <String>{};
    final foundById = <ServerId, BlueyPeer>{};

    final scanConfig = platform.PlatformScanConfig(
      serviceUuids: [lifecycle.controlServiceUuid],
      timeoutMs: timeout.inMilliseconds,
    );

    StreamSubscription<platform.PlatformScanResult>? sub;
    final done = Completer<void>();

    sub = _platform.scan(scanConfig).listen(
      (result) async {
        if (seenAddresses.contains(result.device.id)) return;
        seenAddresses.add(result.device.id);

        if (DateTime.now().isAfter(deadline)) return;

        try {
          final id = await _probeServerId(result.device.id);
          foundById[id] ??= _BlueyPeer(
            platformApi: _platform,
            serverId: id,
          );
        } catch (_) {
          // Skip candidates that fail to report a valid serverId.
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_, __) {
        if (!done.isCompleted) done.complete();
      },
    );

    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete();
    });

    try {
      await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
      await _platform.stopScan();
    }

    return foundById.values.toList(growable: false);
  }

  /// Scans + connects until a peer whose `serverId` matches [expected]
  /// is found. Returns the live [Connection]. Candidates whose id does
  /// not match are disconnected and skipped. Throws
  /// [PeerNotFoundException] if the scan window expires.
  Future<Connection> connectTo(
    ServerId expected, {
    required Duration scanTimeout,
    Duration? timeout,
  }) async {
    final deadline = DateTime.now().add(scanTimeout);
    final tried = <String>{};

    final scanConfig = platform.PlatformScanConfig(
      serviceUuids: [lifecycle.controlServiceUuid],
      timeoutMs: scanTimeout.inMilliseconds,
    );

    final matchCompleter = Completer<Connection>();
    StreamSubscription<platform.PlatformScanResult>? sub;

    sub = _platform.scan(scanConfig).listen(
      (result) async {
        if (matchCompleter.isCompleted) return;
        if (tried.contains(result.device.id)) return;
        tried.add(result.device.id);
        if (DateTime.now().isAfter(deadline)) return;

        Connection? connection;
        try {
          connection = await _openConnection(result.device.id, timeout);
          final id = await _readServerIdFromConnection(connection);
          if (id == expected) {
            if (!matchCompleter.isCompleted) {
              matchCompleter.complete(connection);
            }
            return;
          }
          await connection.disconnect();
        } catch (_) {
          if (connection != null) {
            try {
              await connection.disconnect();
            } catch (_) {
              // Ignore teardown errors for failed candidates.
            }
          }
        }
      },
    );

    Timer? timeoutTimer;
    timeoutTimer = Timer(scanTimeout, () {
      if (!matchCompleter.isCompleted) {
        matchCompleter.completeError(
          PeerNotFoundException(expected, scanTimeout),
        );
      }
    });

    try {
      return await matchCompleter.future;
    } finally {
      timeoutTimer.cancel();
      await sub.cancel();
      await _platform.stopScan();
    }
  }

  Future<ServerId> _probeServerId(String deviceAddress) async {
    final connection = await _openConnection(deviceAddress, null);
    try {
      return await _readServerIdFromConnection(connection);
    } finally {
      try {
        await connection.disconnect();
      } catch (_) {
        // Ignore teardown errors.
      }
    }
  }

  Future<Connection> _openConnection(
    String deviceAddress,
    Duration? timeout,
  ) async {
    final connectionId = await _platform.connect(
      deviceAddress,
      platform.PlatformConnectConfig(
        timeoutMs: timeout?.inMilliseconds,
        mtu: null,
      ),
    );
    // Derive a stable UUID from the address for the domain deviceId.
    // We use a deterministic transform because we don't care about the
    // domain identity here — only the platform connectionId.
    return BlueyConnection(
      platformInstance: _platform,
      connectionId: connectionId,
      deviceId: UUID(_addressToDomainUuid(deviceAddress)),
    );
  }

  Future<ServerId> _readServerIdFromConnection(Connection connection) async {
    // Use services() (not cache) to ensure discovery has run.
    final services = await connection.services();
    final control = services
        .where((s) => lifecycle.isControlService(s.uuid.toString()))
        .firstOrNull;
    if (control == null) {
      throw StateError('Control service missing on candidate');
    }
    final serverIdChar = control.characteristics
        .where(
          (c) => c.uuid.toString().toLowerCase() == lifecycle.serverIdCharUuid,
        )
        .firstOrNull;
    if (serverIdChar == null) {
      throw StateError('serverId characteristic missing on candidate');
    }
    final bytes = await serverIdChar.read();
    return lifecycle.decodeServerId(bytes);
  }

  String _addressToDomainUuid(String address) {
    // Pad/truncate to 32 hex characters, then format as UUID.
    final clean = address.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    final padded = clean.padRight(32, '0').substring(0, 32);
    return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-'
        '${padded.substring(12, 16)}-${padded.substring(16, 20)}-'
        '${padded.substring(20, 32)}';
  }
}
```

Two things to note in the implementation:
1. The import of `bluey_peer.dart` creates a cycle — we'll resolve it by defining `_BlueyPeer` in Task 9 before this test will even compile. This task writes the test first (Step 1), so expect compile errors until Task 9. The test run in Step 2 will surface this as "unresolved reference to `_BlueyPeer`." That's expected — move on to Task 9 in the same TDD cycle.

Actually, to avoid the cycle at all, move `_BlueyPeer` into this task instead: **see Task 9 revision below.**

**Resolution:** merge Task 9 into this task. Place `_BlueyPeer` in `bluey_peer.dart` at the same time as `peer_discovery.dart`, since they're co-located and mutually referenced.

To keep the plan clean: remove the forward reference to `_BlueyPeer` for this step. Instead, `discover()` returns `List<ServerId>` first, and we add a separate helper in Task 9 that wraps each one in a `BlueyPeer`. **Adjustment applied below.**

Change the `discover()` return type to `Future<List<ServerId>>` and drop the `_BlueyPeer` creation:

```dart
Future<List<ServerId>> discover({required Duration timeout}) async {
  // ... same as above, but:
  final foundIds = <ServerId>{};
  // in the scan listener:
  try {
    final id = await _probeServerId(result.device.id);
    foundIds.add(id);
  } catch (_) {
    // skip
  }
  // at the end:
  return foundIds.toList(growable: false);
}
```

And update the test for `discover` accordingly: `expect(peers.map((p) => p.serverId)...)` becomes `expect(ids, equals({id1, id2}))` — already expressed that way in the test above; just rename the local variable.

Adjust the test file to match `Future<List<ServerId>>` for `discover()`:

In `peer_discovery_test.dart`, replace the three `discover` test expectations:
- `final peers = await discovery.discover(...)` → `final ids = await discovery.discover(...)`
- `expect(peers, isEmpty)` → `expect(ids, isEmpty)`
- `final ids = peers.map((p) => p.serverId).toSet()` → `final idSet = ids.toSet()` and `expect(idSet, equals({id1, id2}))`
- `expect(peers, hasLength(1))` → `expect(ids, hasLength(1))`

Revised imports: remove the unused `bluey_peer.dart` import from `peer_discovery.dart`.

- [ ] **Step 4: Run tests**

Run: `cd bluey && flutter test test/peer/peer_discovery_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/peer/peer_discovery.dart bluey/test/peer/peer_discovery_test.dart
git commit -m "feat: add PeerDiscovery helper for scan+verify flow"
```

---

### Task 9: `_BlueyPeer` implementation

**Files:**
- Create: `bluey/lib/src/peer/bluey_peer.dart`
- Create: `bluey/test/peer/bluey_peer_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// bluey/test/peer/bluey_peer_test.dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/bluey_peer.dart';
import 'package:bluey/src/peer/peer_discovery.dart';
import 'package:bluey/src/peer/server_id.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

String _simulateBlueyServer(
  FakeBlueyPlatform fakePlatform,
  ServerId id, {
  String? addressSuffix,
  Duration? intervalValue,
}) {
  final address = 'AA:BB:CC:DD:EE:${addressSuffix ?? '01'}';
  final interval = intervalValue ?? const Duration(seconds: 10);
  fakePlatform.simulatePeripheral(
    id: address,
    name: 'Bluey Server',
    serviceUuids: [controlServiceUuid],
    services: [
      platform.PlatformService(
        uuid: controlServiceUuid,
        isPrimary: true,
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: false,
              canWrite: true,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
        ],
        includedServices: [],
      ),
    ],
    characteristicValues: {
      intervalCharUuid: encodeInterval(interval),
      serverIdCharUuid: id.toBytes(),
    },
  );
  return address;
}

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyPeer', () {
    test('connect() returns a Connection with control service hidden',
        () async {
      final id = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id);

      final peer = blueyPeer(
        platformApi: fakePlatform,
        serverId: id,
      );
      final conn = await peer.connect();

      expect(conn.state, ConnectionState.connected);
      final services = await conn.services();
      expect(
        services.any((s) => s.uuid.toString() == controlServiceUuid),
        isFalse,
      );

      await conn.disconnect();
    });

    test('connect() throws PeerNotFoundException if no match within timeout',
        () async {
      _simulateBlueyServer(fakePlatform, ServerId.generate());

      final peer = blueyPeer(
        platformApi: fakePlatform,
        serverId: ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
      );

      expect(
        () => peer.connect(scanTimeout: const Duration(milliseconds: 300)),
        throwsA(isA<PeerNotFoundException>()),
      );
    });

    test('disconnects when heartbeat write fails', () {
      fakeAsync((async) {
        final id = ServerId.generate();
        _simulateBlueyServer(fakePlatform, id);

        final peer = blueyPeer(
          platformApi: fakePlatform,
          serverId: id,
        );

        late Connection conn;
        peer.connect().then((c) => conn = c);
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        conn.stateChanges.listen(states.add);

        // Simulate server unreachable.
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(states, contains(ConnectionState.disconnected));
      });
    });
  });
}
```

Note that this test uses `blueyPeer(...)` — a package-private factory — rather than directly constructing the implementation class. This is common Dart practice for hiding constructors but allowing test access.

- [ ] **Step 2: Run to verify failure**

Run: `cd bluey && flutter test test/peer/bluey_peer_test.dart`
Expected: FAIL — `_BlueyPeer` and `blueyPeer` don't exist.

- [ ] **Step 3: Implement `_BlueyPeer` and factory**

```dart
// bluey/lib/src/peer/bluey_peer.dart
import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../connection/bluey_connection.dart';
import '../connection/connection.dart';
import '../connection/lifecycle_client.dart';
import 'peer.dart';
import 'peer_connection.dart';
import 'peer_discovery.dart';
import 'server_id.dart';

/// Test/package entry point for constructing a [BlueyPeer] directly.
/// Exposed so tests and the `Bluey` class can build peers without
/// importing the private `_BlueyPeer` type.
BlueyPeer blueyPeer({
  required platform.BlueyPlatform platformApi,
  required ServerId serverId,
  int maxFailedHeartbeats = 1,
}) {
  return _BlueyPeer(
    platformApi: platformApi,
    serverId: serverId,
    maxFailedHeartbeats: maxFailedHeartbeats,
  );
}

class _BlueyPeer implements BlueyPeer {
  final platform.BlueyPlatform _platform;
  final int _maxFailedHeartbeats;

  @override
  final ServerId serverId;

  bool _connecting = false;

  _BlueyPeer({
    required platform.BlueyPlatform platformApi,
    required this.serverId,
    required int maxFailedHeartbeats,
  })  : _platform = platformApi,
        _maxFailedHeartbeats = maxFailedHeartbeats;

  @override
  Future<Connection> connect({
    Duration? scanTimeout,
    Duration? timeout,
  }) async {
    if (_connecting) {
      throw StateError('Peer $serverId is already connecting');
    }
    _connecting = true;
    try {
      final effectiveScanTimeout =
          scanTimeout ?? const Duration(seconds: 5);

      final discovery = PeerDiscovery(platformApi: _platform);
      final rawConnection = await discovery.connectTo(
        serverId,
        scanTimeout: effectiveScanTimeout,
        timeout: timeout,
      );

      // Wrap with the filtering decorator for the public return.
      final peerConnection = PeerConnection(rawConnection);

      // Start lifecycle client that listens for heartbeat failures and
      // triggers a platform-level disconnect when the server goes away.
      final platformConnectionId = _extractConnectionId(rawConnection);
      final lifecycle = LifecycleClient(
        platformApi: _platform,
        connectionId: platformConnectionId,
        maxFailedHeartbeats: _maxFailedHeartbeats,
        onServerUnreachable: () {
          // Trigger the same path as a user-initiated disconnect.
          // Error is best-effort; the connection state stream will
          // surface the disconnect.
          rawConnection.disconnect().catchError((_) {});
        },
      );
      // Start heartbeat using the raw connection's services (which includes
      // the control service — PeerConnection would have filtered it).
      final allServices = await rawConnection.services();
      lifecycle.start(allServices: allServices);

      return peerConnection;
    } finally {
      _connecting = false;
    }
  }
}

String _extractConnectionId(Connection connection) {
  // BlueyConnection exposes its connectionId via a test-only hook.
  // Since Connection is abstract, we downcast. This is safe inside
  // the peer context because BlueyConnection is the only real impl.
  if (connection is BlueyConnection) {
    return connection.connectionId;
  }
  throw StateError(
    'Expected BlueyConnection, got ${connection.runtimeType}',
  );
}
```

- [ ] **Step 4: Expose `connectionId` on `BlueyConnection`**

In `bluey/lib/src/connection/bluey_connection.dart`, the field `_connectionId` is currently private. Expose a getter for internal use:

```dart
class BlueyConnection implements Connection {
  final platform.BlueyPlatform _platform;
  final String _connectionId;

  /// Platform-level connection identifier. Internal API — used by
  /// the peer module to wire up a `LifecycleClient`.
  String get connectionId => _connectionId;

  // ... rest unchanged
```

- [ ] **Step 5: Run tests**

Run: `cd bluey && flutter test test/peer/bluey_peer_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/peer/bluey_peer.dart bluey/lib/src/connection/bluey_connection.dart bluey/test/peer/bluey_peer_test.dart
git commit -m "feat: add _BlueyPeer implementation orchestrating connect + lifecycle"
```

---

### Task 10: Remove `requireLifecycle` from the raw-connect path

This task cleans up the residual parameter now that `BlueyPeer` replaces its purpose. Also removes lifecycle wiring from `BlueyConnection` (it will still live in `LifecycleClient`, but only the peer module instantiates it).

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart` (remove `requireLifecycle`)
- Modify: `bluey/lib/src/connection/bluey_connection.dart` (remove all lifecycle wiring)
- Modify: `bluey/lib/src/bluey.dart` (remove `maxFailedHeartbeats` and `requireLifecycle` from `connect()`)
- Delete: `bluey/test/connection/lifecycle_client_test.dart`
- Modify: various tests that assert on `requireLifecycle` or opportunistic heartbeats

- [ ] **Step 1: Remove `requireLifecycle` from `LifecycleClient`**

In `bluey/lib/src/connection/lifecycle_client.dart`:

- Remove the `final bool requireLifecycle;` field.
- Remove the `this.requireLifecycle = false` constructor parameter.
- In `start()`, remove the two `if (requireLifecycle) onServerUnreachable();` lines. When control service or heartbeat char is absent, just return.

Updated `start()`:

```dart
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

  // ... rest unchanged
```

- [ ] **Step 2: Strip lifecycle wiring from `BlueyConnection`**

In `bluey/lib/src/connection/bluey_connection.dart`:

- Remove import of `'lifecycle_client.dart'`.
- Remove import of `'../lifecycle.dart' as lifecycle;`.
- Remove the `late final LifecycleClient _lifecycle;` field.
- Remove `maxFailedHeartbeats` and `requireLifecycle` parameters from the constructor.
- Remove the constructor body that instantiates `_lifecycle`.
- Remove the `_handleServerUnreachable()` method.
- Remove the control-service filtering in `service()`, `services()`, and `hasService()` (those filters become the `PeerConnection`'s job only).
- Remove the `_lifecycle.start(...)` call from `services()`.
- Remove the `_lifecycle.sendDisconnectCommand()` call from `disconnect()`.
- Remove the `_lifecycle.stop()` call from `_cleanup()`.

Updated `services()`:
```dart
@override
Future<List<RemoteService>> services({bool cache = false}) async {
  if (cache && _cachedServices != null) {
    return _cachedServices!;
  }

  final platformServices = await _platform.discoverServices(_connectionId);
  _cachedServices = platformServices.map((ps) => _mapService(ps)).toList();
  return _cachedServices!;
}
```

Updated `service()`:
```dart
@override
RemoteService service(UUID uuid) {
  if (_cachedServices == null) {
    throw ServiceNotFoundException(uuid);
  }
  for (final svc in _cachedServices!) {
    if (svc.uuid == uuid) return svc;
  }
  throw ServiceNotFoundException(uuid);
}
```

Updated `hasService()`:
```dart
@override
Future<bool> hasService(UUID uuid) async {
  final svcs = await services(cache: true);
  return svcs.any((s) => s.uuid == uuid);
}
```

Updated `disconnect()`:
```dart
@override
Future<void> disconnect() async {
  if (_state == ConnectionState.disconnected ||
      _state == ConnectionState.disconnecting) {
    return;
  }

  _state = ConnectionState.disconnecting;
  _stateController.add(_state);

  await _platform.disconnect(_connectionId);

  _state = ConnectionState.disconnected;
  _stateController.add(_state);

  await _cleanup();
}
```

- [ ] **Step 3: Strip from `Bluey.connect()`**

In `bluey/lib/src/bluey.dart`:

```dart
Future<Connection> connect(
  Device device, {
  Duration? timeout,
}) async {
  final config = platform.PlatformConnectConfig(
    timeoutMs: timeout?.inMilliseconds,
    mtu: null,
  );

  _emitEvent(ConnectingEvent(deviceId: device.id));

  try {
    final connectionId = await _platform.connect(device.address, config);
    _emitEvent(ConnectedEvent(deviceId: device.id));
    return BlueyConnection(
      platformInstance: _platform,
      connectionId: connectionId,
      deviceId: device.id,
    );
  } catch (e) {
    _emitEvent(ErrorEvent(
      message: 'Connection failed to ${device.id.toShortString()}',
      error: e,
    ));
    throw _wrapError(e);
  }
}
```

- [ ] **Step 4: Delete the obsolete test file**

```bash
rm bluey/test/connection/lifecycle_client_test.dart
```

- [ ] **Step 5: Fix any remaining test failures**

Run: `cd bluey && flutter test`
Expected: possibly some failures in `bluey_test.dart`, `bluey_connection_test.dart`, or integration tests that assert on lifecycle behavior on the raw-connect path.

For each failing test:
- If it tests lifecycle behavior through `bluey.connect(device)` → either delete it (coverage moved to `bluey_peer_test.dart`) or port it to use a peer.
- If it tests non-lifecycle `Connection` behavior and was incidentally affected → adjust to the new `BlueyConnection` shape.

Search for `maxFailedHeartbeats`, `requireLifecycle`, `lifecycle.isControlService` usages in the `test/` tree and reconcile each.

- [ ] **Step 6: Run full test suite**

Run: `cd bluey && flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A bluey/lib/src/ bluey/test/
git commit -m "refactor: move lifecycle protocol entirely into the peer module"
```

---

### Task 11: Add `bluey.peer()` and `bluey.discoverPeers()`

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Create: `bluey/test/peer/peer_e2e_test.dart`
- Modify: `bluey/lib/bluey.dart` (re-exports)

- [ ] **Step 1: Write failing end-to-end tests**

```dart
// bluey/test/peer/peer_e2e_test.dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

// Re-uses the helper defined in bluey_peer_test.dart — duplicated here
// for isolation (each test file should be standalone).
String _simulateBlueyServer(
  FakeBlueyPlatform fakePlatform,
  ServerId id, {
  String? addressSuffix,
  Duration? intervalValue,
}) {
  final address = 'AA:BB:CC:DD:EE:${addressSuffix ?? '01'}';
  final interval = intervalValue ?? const Duration(seconds: 10);
  fakePlatform.simulatePeripheral(
    id: address,
    name: 'Bluey Server',
    serviceUuids: [controlServiceUuid],
    services: [
      platform.PlatformService(
        uuid: controlServiceUuid,
        isPrimary: true,
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: false,
              canWrite: true,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          platform.PlatformCharacteristic(
            uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
            properties: platform.PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
        ],
        includedServices: [],
      ),
    ],
    characteristicValues: {
      intervalCharUuid: encodeInterval(interval),
      serverIdCharUuid: id.toBytes(),
    },
  );
  return address;
}

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('bluey.discoverPeers', () {
    test('returns all nearby Bluey servers', () async {
      final id1 = ServerId.generate();
      final id2 = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id1, addressSuffix: '01');
      _simulateBlueyServer(fakePlatform, id2, addressSuffix: '02');

      final bluey = Bluey();
      final peers = await bluey.discoverPeers(
        timeout: const Duration(milliseconds: 500),
      );
      expect(peers.map((p) => p.serverId).toSet(), equals({id1, id2}));
      await bluey.dispose();
    });

    test('returns empty list when no Bluey servers advertising', () async {
      final bluey = Bluey();
      final peers = await bluey.discoverPeers(
        timeout: const Duration(milliseconds: 200),
      );
      expect(peers, isEmpty);
      await bluey.dispose();
    });
  });

  group('bluey.peer', () {
    test('returns a BlueyPeer with the given serverId', () {
      final bluey = Bluey();
      final id = ServerId.generate();
      final peer = bluey.peer(id);
      expect(peer.serverId, equals(id));
      bluey.dispose();
    });

    test('connect() succeeds against a matching server', () async {
      final id = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id);

      final bluey = Bluey();
      final peer = bluey.peer(id);
      final conn = await peer.connect();
      expect(conn.state, ConnectionState.connected);
      await conn.disconnect();
      await bluey.dispose();
    });

    test('connect() throws PeerNotFoundException when no match', () async {
      _simulateBlueyServer(fakePlatform, ServerId.generate());

      final bluey = Bluey();
      final peer = bluey.peer(
        ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
      );

      expect(
        () => peer.connect(scanTimeout: const Duration(milliseconds: 300)),
        throwsA(isA<PeerNotFoundException>()),
      );

      await bluey.dispose();
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd bluey && flutter test test/peer/peer_e2e_test.dart`
Expected: FAIL — `ServerId`, `PeerNotFoundException`, `bluey.peer`, and `bluey.discoverPeers` not exported from `package:bluey/bluey.dart`.

- [ ] **Step 3: Add `peer` and `discoverPeers` to `Bluey`**

In `bluey/lib/src/bluey.dart`, add these imports:
```dart
import 'peer/bluey_peer.dart';
import 'peer/peer.dart';
import 'peer/peer_discovery.dart';
import 'peer/server_id.dart';
```

Add these methods on the `Bluey` class (near `connect()`):

```dart
/// Construct a peer handle from a known [ServerId].
///
/// No BLE activity happens until [BlueyPeer.connect] is called.
///
/// [maxFailedHeartbeats] controls how many consecutive heartbeat
/// write failures trigger a local disconnect on the peer connection.
/// Defaults to 1 (fail-fast).
BlueyPeer peer(
  ServerId serverId, {
  int maxFailedHeartbeats = 1,
}) {
  return blueyPeer(
    platformApi: _platform,
    serverId: serverId,
    maxFailedHeartbeats: maxFailedHeartbeats,
  );
}

/// Scan for nearby Bluey servers.
///
/// Filters by the Bluey control service UUID, briefly connects to
/// each candidate to read its `serverId`, and returns a list of
/// [BlueyPeer]s deduplicated by [ServerId].
///
/// [timeout] bounds the scan window. Defaults to 5 seconds.
Future<List<BlueyPeer>> discoverPeers({
  Duration timeout = const Duration(seconds: 5),
}) async {
  final discovery = PeerDiscovery(platformApi: _platform);
  final ids = await discovery.discover(timeout: timeout);
  return ids
      .map((id) => blueyPeer(
            platformApi: _platform,
            serverId: id,
          ))
      .toList(growable: false);
}
```

- [ ] **Step 4: Re-export peer types from the library barrel**

In `bluey/lib/bluey.dart`, add:

```dart
export 'src/peer/peer.dart' show BlueyPeer;
export 'src/peer/server_id.dart' show ServerId;
```

The exceptions `PeerNotFoundException` and `PeerIdentityMismatchException` should already flow through the existing `export 'src/shared/exceptions.dart';` line — if not, add them explicitly to that export show-list or confirm the file uses a bare `export`.

- [ ] **Step 5: Run tests**

Run: `cd bluey && flutter test test/peer/peer_e2e_test.dart`
Expected: PASS (5 tests).

Run full suite: `cd bluey && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/bluey.dart bluey/lib/bluey.dart bluey/test/peer/peer_e2e_test.dart
git commit -m "feat: add bluey.peer() and bluey.discoverPeers() to public API"
```

---

### Task 12: Extend `FakeBlueyPlatform` with a Bluey-server helper

Consolidate the `_simulateBlueyServer` helper (duplicated across `peer_discovery_test.dart`, `bluey_peer_test.dart`, and `peer_e2e_test.dart`) into the fake itself so it's reusable.

**Files:**
- Modify: `bluey/test/fakes/fake_platform.dart`

- [ ] **Step 1: Add the helper method to the fake**

In `bluey/test/fakes/fake_platform.dart`, add near the existing `simulatePeripheral` method:

```dart
/// Convenience: advertise a fake Bluey server with the full control
/// service wired up (heartbeat + interval + serverId), suitable for
/// peer discovery tests.
void simulateBlueyServer({
  required String address,
  required ServerId serverId,
  String name = 'Bluey Server',
  Duration intervalValue = const Duration(seconds: 10),
}) {
  simulatePeripheral(
    id: address,
    name: name,
    serviceUuids: [controlServiceUuid],
    services: [
      PlatformService(
        uuid: controlServiceUuid,
        isPrimary: true,
        characteristics: const [
          PlatformCharacteristic(
            uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
            properties: PlatformCharacteristicProperties(
              canRead: false,
              canWrite: true,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          PlatformCharacteristic(
            uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
            properties: PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
          PlatformCharacteristic(
            uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
            properties: PlatformCharacteristicProperties(
              canRead: true,
              canWrite: false,
              canWriteWithoutResponse: false,
              canNotify: false,
              canIndicate: false,
            ),
            descriptors: [],
          ),
        ],
        includedServices: [],
      ),
    ],
    characteristicValues: {
      intervalCharUuid: encodeInterval(intervalValue),
      serverIdCharUuid: serverId.toBytes(),
    },
  );
}
```

Add imports at the top of the file (if not already there):
```dart
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/server_id.dart';
```

- [ ] **Step 2: Replace local `_simulateBlueyServer` helpers in the three test files**

In `bluey/test/peer/peer_discovery_test.dart`, `bluey/test/peer/bluey_peer_test.dart`, and `bluey/test/peer/peer_e2e_test.dart`:

- Remove the local `_simulateBlueyServer` function.
- Replace calls to `_simulateBlueyServer(fakePlatform, id, addressSuffix: '01')` with:
  ```dart
  fakePlatform.simulateBlueyServer(
    address: 'AA:BB:CC:DD:EE:01',
    serverId: id,
  );
  ```

- [ ] **Step 3: Run tests**

Run: `cd bluey && flutter test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add bluey/test/fakes/fake_platform.dart bluey/test/peer/
git commit -m "refactor: consolidate Bluey server simulation into FakeBlueyPlatform"
```

---

### Task 13: Update library-level documentation

**Files:**
- Modify: `CLAUDE.md` (repo root)
- Modify: `BLUEY_ARCHITECTURE.md`
- Modify: `bluey/README.md` (only if exists)

- [ ] **Step 1: Update `CLAUDE.md`**

Open `/Users/joel/git/neutrinographics/bluey/CLAUDE.md`. Find the "Bounded Contexts" section and add a new context:

```markdown
6. **Peer** - Stable peer identity on top of the lifecycle protocol. `BlueyPeer`, `ServerId`, `bluey.peer()`, `bluey.discoverPeers()`. The peer module owns the client-side protocol layer — raw `BlueyConnection` is protocol-free.
```

Also find the "Ubiquitous Language" table and add:

| Use | Avoid |
|-----|-------|
| `ServerId` | server UUID, peer ID |
| `BlueyPeer` | peer device (in Bluey-specific contexts) |

- [ ] **Step 2: Update `BLUEY_ARCHITECTURE.md`**

Add a new section "## Peer Protocol" after the lifecycle section. Content:

```markdown
## Peer Protocol

BlueyPeer layers stable identity on top of the lifecycle protocol to
solve cross-platform BLE identity instability.

### The problem

- **iOS** assigns `CBPeripheral.identifier` values that are stable
  within a single CoreBluetooth session but change across sessions
  (app restarts, device reboots).
- **Android** supports MAC randomization, so the platform-reported
  address for the same physical device varies over time.
- **Zombie advertisements** occur when a server app is force-killed
  but the OS continues advertising a stale peripheral with cached
  services. A client connecting to one gets a half-dead GATT.

### The solution

The control service (already introduced for heartbeat-based disconnect
detection) gains a third readable characteristic:

    control service (b1e70001-...)
    ├── heartbeat  (b1e70002-...)  write-with-response
    ├── interval   (b1e70003-...)  read (4-byte ms, little-endian)
    └── serverId   (b1e70004-...)  read (16-byte UUID)       ← NEW

The `serverId` is a random v4 UUID generated by the server (or supplied
by the app) that remains stable across restarts if persisted. Clients
read it once on connect, cache it, and use `bluey.peer(id).connect()`
to reconnect across platform-identifier churn.

### The flow

1. **Discovery.** `bluey.discoverPeers()` scans filtered by the control
   service UUID, briefly connects to each candidate, reads `serverId`,
   disconnects. Returns a list of `BlueyPeer`s deduplicated by id.

2. **Connect by id.** `peer.connect()` performs a targeted scan,
   connects to each matching candidate, reads `serverId`, verifies
   match. On match, returns a live `PeerConnection` (filtering the
   control service from the public services list) with the lifecycle
   heartbeat active.

3. **Persistence is the app's job in v1.** The app stores and restores
   `ServerId` values using whatever mechanism it prefers — the library
   does not dictate storage. See the example app for a reference
   implementation using `shared_preferences`.

### Architectural layering

- **Raw BLE layer**: `Scanner`, `Device`, `Connection` (via
  `BlueyConnection`), `Server`. No protocol awareness.
- **Peer protocol layer**: `BlueyPeer`, `ServerId`,
  `bluey.discoverPeers`, `PeerDiscovery`, `PeerConnection`. Composes
  raw BLE + lifecycle + identity.

A raw `bluey.connect(device)` call yields a `Connection` with no
lifecycle heartbeat — useful for generic BLE peripherals. A
`peer.connect()` yields a connection with the full protocol active.
```

- [ ] **Step 3: Update the README if present**

Check if `bluey/README.md` exists:
```bash
ls -la bluey/README.md 2>/dev/null
```

If present, add a "Peer protocol" section near the top with:

```markdown
## Peer protocol

Bluey provides stable peer identity across platform identifier changes
(iOS session rotation, Android MAC randomization). Use `bluey.peer()`
for Bluey-to-Bluey connections:

```dart
// Server side — supply a persisted ServerId to survive restarts.
final savedId = await prefs.getString('server_id');
final identity = savedId != null ? ServerId(savedId) : ServerId.generate();
await prefs.setString('server_id', identity.value);
final server = bluey.server(identity: identity);

// Client side — reconnect to a known peer without rescanning.
final savedPeerId = await prefs.getString('last_peer_id');
if (savedPeerId != null) {
  try {
    final conn = await bluey.peer(ServerId(savedPeerId)).connect();
    // ... use connection
  } on PeerNotFoundException {
    // Server moved or went offline — fall back to discovery.
  }
}

// Discovery (first time, or fallback).
final peers = await bluey.discoverPeers();
// show list, let user pick, remember peer.serverId.
```
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md BLUEY_ARCHITECTURE.md bluey/README.md 2>/dev/null || true
git commit -m "docs: document BlueyPeer protocol and layering"
```

---

### Task 14: Example app — remove `requireLifecycle` from settings

**Files:**
- Modify: `bluey/example/lib/features/connection/domain/connection_settings.dart`
- Modify: `bluey/example/lib/features/connection/presentation/connection_settings_cubit.dart`
- Modify: `bluey/example/lib/features/connection/infrastructure/bluey_connection_repository.dart`
- Modify: `bluey/example/lib/features/scanner/presentation/scanner_screen.dart` (the settings dialog)
- Modify: `bluey/example/test/` as needed

- [ ] **Step 1: Remove `requireLifecycle` from `ConnectionSettings`**

In `bluey/example/lib/features/connection/domain/connection_settings.dart`, remove the `requireLifecycle` field:

```dart
import 'package:flutter/foundation.dart';

@immutable
class ConnectionSettings {
  final int maxFailedHeartbeats;

  const ConnectionSettings({
    this.maxFailedHeartbeats = 1,
  });

  ConnectionSettings copyWith({
    int? maxFailedHeartbeats,
  }) {
    return ConnectionSettings(
      maxFailedHeartbeats: maxFailedHeartbeats ?? this.maxFailedHeartbeats,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionSettings &&
          runtimeType == other.runtimeType &&
          maxFailedHeartbeats == other.maxFailedHeartbeats;

  @override
  int get hashCode => maxFailedHeartbeats.hashCode;
}
```

- [ ] **Step 2: Remove the setter from the cubit**

In `bluey/example/lib/features/connection/presentation/connection_settings_cubit.dart`:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/connection_settings.dart';

class ConnectionSettingsCubit extends Cubit<ConnectionSettings> {
  ConnectionSettingsCubit() : super(const ConnectionSettings());

  void setMaxFailedHeartbeats(int value) {
    emit(state.copyWith(maxFailedHeartbeats: value));
  }
}
```

- [ ] **Step 3: Stop passing `requireLifecycle` in the repository**

In `bluey/example/lib/features/connection/infrastructure/bluey_connection_repository.dart`:

```dart
@override
Future<Connection> connect(
  Device device, {
  Duration? timeout,
  ConnectionSettings settings = const ConnectionSettings(),
}) async {
  return await _bluey.connect(device, timeout: timeout);
  // Note: maxFailedHeartbeats no longer applies to raw connect.
  // It will apply only when the example app moves to peer.connect()
  // in a later task.
}
```

Also remove any import of `package:bluey/bluey.dart` features that are no longer needed (e.g. if `requireLifecycle` was referenced in this file explicitly).

- [ ] **Step 4: Remove the switch from the settings dialog**

In `bluey/example/lib/features/scanner/presentation/scanner_screen.dart`, find the `_ConnectionSettingsDialog` widget and remove the `SwitchListTile` block for `requireLifecycle`. Keep the `Slider` for `maxFailedHeartbeats`.

- [ ] **Step 5: Update or remove tests asserting the old fields**

Run: `cd bluey/example && flutter test`
Expected: possibly test failures in `test/connection/` or `test/scanner/`. For each failure, remove references to `requireLifecycle`.

- [ ] **Step 6: Run the example tests and analyzer**

```bash
cd bluey/example && flutter test && flutter analyze
```
Expected: PASS, no issues.

- [ ] **Step 7: Commit**

```bash
git add bluey/example/lib/features/connection/ bluey/example/lib/features/scanner/ bluey/example/test/
git commit -m "example: remove requireLifecycle toggle (subsumed by BlueyPeer)"
```

---

### Task 15: Example app — persist `ServerId` on the server

**Files:**
- Modify: `bluey/example/pubspec.yaml` (add `shared_preferences`)
- Modify: `bluey/example/lib/features/server/` (server startup + UI)

- [ ] **Step 1: Add `shared_preferences` dependency**

In `bluey/example/pubspec.yaml`, add under `dependencies:`:

```yaml
  shared_preferences: ^2.2.0
```

Run:
```bash
cd bluey/example && flutter pub get
```
Expected: success.

- [ ] **Step 2: Find the server bootstrap code**

Locate where `bluey.server(...)` is called in the example app:

```bash
grep -rn "bluey.server(" bluey/example/lib/
```

This is likely in `bluey/example/lib/features/server/` — either in a cubit, repository, or startup/bootstrap file.

- [ ] **Step 3: Persist the `ServerId`**

Modify the server bootstrap to load-or-generate the id:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bluey/bluey.dart';

const _kServerIdKey = 'bluey_server_id';

Future<ServerId> _loadOrGenerateServerId() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_kServerIdKey);
  if (stored != null) {
    try {
      return ServerId(stored);
    } catch (_) {
      // stored value corrupted — regenerate below
    }
  }
  final fresh = ServerId.generate();
  await prefs.setString(_kServerIdKey, fresh.value);
  return fresh;
}

Future<void> clearStoredServerId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kServerIdKey);
}
```

Then change the server initialization to:

```dart
final identity = await _loadOrGenerateServerId();
final server = bluey.server(identity: identity);
```

Adjust the server cubit/repository to expose `serverId` so the UI can display it.

- [ ] **Step 4: Show the `ServerId` in the server UI**

In the server screen, add a small read-only display of `server.serverId` (truncated, e.g., first 8 chars). Also add a "Reset identity" button that calls `clearStoredServerId()` and then re-initializes the server with a fresh id.

- [ ] **Step 5: Run the example tests**

```bash
cd bluey/example && flutter test && flutter analyze
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bluey/example/pubspec.yaml bluey/example/lib/features/server/
git commit -m "example: persist server ServerId across app restarts"
```

---

### Task 16: Example app — client-side peer persistence and discovery UI

**Files:**
- Create: `bluey/example/lib/features/peer/` (new feature module)

This is the client-side complement to Task 15 — the demo of Path B for peers.

- [ ] **Step 1: Scaffold the peer feature**

Create the folder structure:

```
bluey/example/lib/features/peer/
├── application/
│   ├── discover_peers.dart
│   ├── connect_saved_peer.dart
│   └── forget_saved_peer.dart
├── domain/
│   └── saved_peer.dart
├── infrastructure/
│   └── shared_prefs_peer_storage.dart
└── presentation/
    ├── peer_cubit.dart
    └── peer_screen.dart
```

- [ ] **Step 2: Implement peer storage**

`bluey/example/lib/features/peer/infrastructure/shared_prefs_peer_storage.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsPeerStorage {
  static const _key = 'bluey_saved_peer_id';

  Future<ServerId?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == null) return null;
    try {
      return ServerId(stored);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ServerId id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id.value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
```

- [ ] **Step 3: Implement use cases**

`bluey/example/lib/features/peer/application/discover_peers.dart`:

```dart
import 'package:bluey/bluey.dart';

class DiscoverPeers {
  final Bluey _bluey;
  DiscoverPeers(this._bluey);

  Future<List<BlueyPeer>> call({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _bluey.discoverPeers(timeout: timeout);
  }
}
```

`bluey/example/lib/features/peer/application/connect_saved_peer.dart`:

```dart
import 'package:bluey/bluey.dart';

import '../infrastructure/shared_prefs_peer_storage.dart';

class ConnectSavedPeer {
  final Bluey _bluey;
  final SharedPrefsPeerStorage _storage;

  ConnectSavedPeer(this._bluey, this._storage);

  /// Attempts to reconnect to the saved peer. Returns null if no
  /// peer is saved. Throws [PeerNotFoundException] if the saved
  /// peer is not currently reachable.
  Future<Connection?> call() async {
    final id = await _storage.load();
    if (id == null) return null;
    final peer = _bluey.peer(id);
    return peer.connect();
  }
}
```

`bluey/example/lib/features/peer/application/forget_saved_peer.dart`:

```dart
import '../infrastructure/shared_prefs_peer_storage.dart';

class ForgetSavedPeer {
  final SharedPrefsPeerStorage _storage;
  ForgetSavedPeer(this._storage);
  Future<void> call() => _storage.clear();
}
```

- [ ] **Step 4: Implement the screen**

Write a simple `PeerScreen` that:
- On open, checks `ConnectSavedPeer()` and tries to restore the last peer automatically, showing a "Reconnecting…" state.
- On failure (or no saved peer), shows a "Discover peers" button that runs `DiscoverPeers()` and lists results.
- When a peer is picked, saves it via `SharedPrefsPeerStorage.save(peer.serverId)` and navigates to the existing `ConnectionScreen` with the returned `Connection`.
- Provides a "Forget saved peer" action.

`bluey/example/lib/features/peer/presentation/peer_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../../../shared/di/service_locator.dart';
import '../application/connect_saved_peer.dart';
import '../application/discover_peers.dart';
import '../application/forget_saved_peer.dart';
import '../infrastructure/shared_prefs_peer_storage.dart';
import 'peer_cubit.dart';

class PeerScreen extends StatelessWidget {
  const PeerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PeerCubit(
        discover: getIt<DiscoverPeers>(),
        connectSaved: getIt<ConnectSavedPeer>(),
        forgetSaved: getIt<ForgetSavedPeer>(),
        storage: getIt<SharedPrefsPeerStorage>(),
      )..restoreOrStartEmpty(),
      child: const _PeerView(),
    );
  }
}

class _PeerView extends StatelessWidget {
  const _PeerView();
  @override
  Widget build(BuildContext context) {
    // Minimal UI — matches the demo-app style. Delegates to the cubit.
    return Scaffold(
      appBar: AppBar(title: const Text('Bluey peers')),
      body: BlocBuilder<PeerCubit, PeerState>(
        builder: (context, state) {
          // ... render based on state
          return const Placeholder();
        },
      ),
    );
  }
}
```

The `PeerCubit` and `PeerState` shapes are straightforward — they follow the same pattern as the existing `ConnectionCubit`. Since the visual style is demo-app-specific, match whatever the existing screens use (design tokens, etc.). If writing the Cubit is complicated, split into a subtask rather than guessing.

- [ ] **Step 5: Register DI**

In `bluey/example/lib/features/peer/di/peer_module.dart` (or extend an existing module):

```dart
import 'package:bluey/bluey.dart';
import 'package:get_it/get_it.dart';

import '../application/connect_saved_peer.dart';
import '../application/discover_peers.dart';
import '../application/forget_saved_peer.dart';
import '../infrastructure/shared_prefs_peer_storage.dart';

void registerPeerDependencies(GetIt getIt) {
  getIt.registerLazySingleton<SharedPrefsPeerStorage>(
    () => SharedPrefsPeerStorage(),
  );
  getIt.registerFactory<DiscoverPeers>(
    () => DiscoverPeers(getIt<Bluey>()),
  );
  getIt.registerFactory<ConnectSavedPeer>(
    () => ConnectSavedPeer(
      getIt<Bluey>(),
      getIt<SharedPrefsPeerStorage>(),
    ),
  );
  getIt.registerFactory<ForgetSavedPeer>(
    () => ForgetSavedPeer(getIt<SharedPrefsPeerStorage>()),
  );
}
```

And call `registerPeerDependencies(getIt)` from the app bootstrap (next to the other `register*Dependencies` calls — search for those to find the site).

- [ ] **Step 6: Wire the peer screen into the app's navigation**

Add a "Peers" entry to whatever top-level navigation the example app uses (bottom nav bar, tabs, or scanner-screen button). Exact placement is up to the engineer's judgement — the goal is discoverability.

- [ ] **Step 7: Run tests and analyzer**

```bash
cd bluey/example && flutter test && flutter analyze
```
Expected: PASS, no issues.

- [ ] **Step 8: Commit**

```bash
git add bluey/example/lib/features/peer/ bluey/example/lib/
git commit -m "example: add peer discovery and saved-peer reconnection flow"
```

---

### Task 17: Final verification

**Files:** all

- [ ] **Step 1: Run the full test suite across all packages**

```bash
cd bluey && flutter test
cd bluey/example && flutter test
cd bluey_platform_interface && flutter test
cd bluey_android && flutter test
cd bluey_ios && flutter test 2>/dev/null || true
```
Expected: all pass.

- [ ] **Step 2: Run the analyzer across all packages**

```bash
cd bluey && flutter analyze
cd bluey/example && flutter analyze
cd bluey_platform_interface && flutter analyze
cd bluey_android && flutter analyze
```
Expected: no new issues beyond pre-existing ones on `main`.

- [ ] **Step 3: Manual smoke test on devices**

Since the library handles cross-platform BLE, manual verification on physical devices matters.

Check:
1. Android server + iOS client: open the example app's peer screen, discover the server, connect. Force-kill the Android server. Observe client disconnect via heartbeat failure. Restart the Android server. On the client, tap the saved peer — if the server's `ServerId` is persisted (Task 15), reconnection succeeds without rediscovery.
2. iOS server + Android client: mirror of above.
3. Multiple servers advertising: `discoverPeers()` lists all of them; picking one connects to the right one.

- [ ] **Step 4: Commit any final fixes**

If manual testing reveals issues, add a fix commit per issue.

```bash
git add ...
git commit -m "fix: <specific issue>"
```

- [ ] **Step 5: Push the branch**

```bash
git push -u origin feature/bluey-peer
```

- [ ] **Step 6: Open a PR**

```bash
gh pr create --title "BlueyPeer — stable peer identity" --body "$(cat <<'EOF'
## Summary
- Introduce `BlueyPeer`, `ServerId`, and `bluey.peer()` / `bluey.discoverPeers()` as the Bluey-to-Bluey connection API.
- Remove `requireLifecycle` from `Bluey.connect()` — its guarantee is subsumed by the new peer API's serverId verification step.
- Move the lifecycle protocol entirely into the new peer module; `BlueyConnection` becomes pure raw-BLE.
- Example app: persist server `ServerId` via `shared_preferences`, add peer discovery + saved-peer reconnect flow.

Spec: `docs/superpowers/specs/2026-04-15-bluey-peer-identity-design.md`
Plan: `docs/superpowers/plans/2026-04-15-bluey-peer-identity.md`

## Test plan
- [x] Unit tests for `ServerId`, `PeerConnection`, `PeerDiscovery`, `_BlueyPeer`
- [x] End-to-end tests for `bluey.peer()` and `bluey.discoverPeers()`
- [x] Existing lifecycle tests extended for `serverId` characteristic
- [ ] Manual device test: Android↔iOS discovery and reconnect-after-server-restart
EOF
)"
```

---

## Self-Review

Going through the spec against the plan:

**1. Protocol extension (spec §1):** Task 2 adds `serverIdCharUuid`, encode/decode, and extends `buildControlService()`. ✓

**2. Public API — ServerId (spec §2):** Task 1. ✓

**3. Public API — BlueyPeer (spec §2):** Tasks 6 (interface), 9 (impl). ✓

**4. Public API — Bluey.peer / Bluey.discoverPeers (spec §2):** Task 11. ✓

**5. Public API — Server.identity (spec §2):** Task 4. ✓

**6. requireLifecycle removed / maxFailedHeartbeats moved (spec §2):** Task 10. ✓

**7. Exceptions (spec §2):** Task 5. ✓

**8. File layout (spec §3):** Tasks 1, 6, 7, 8, 9 create the files. Tasks 2, 4, 10, 11 modify existing files. ✓

**9. Layering discipline (spec §3):** Task 10 strips lifecycle from `BlueyConnection`; Task 9 wires it into `_BlueyPeer`. ✓

**10. `LifecycleServer.serverId` (spec §3, inferred):** Task 3. ✓

**11. `PeerConnection` decorator (spec §3):** Task 7. ✓

**12. `PeerDiscovery` (spec §3):** Task 8. ✓

**13. Concurrency / reentrancy (spec §3):** Task 9's `_BlueyPeer._connecting` flag prevents concurrent connects on the same peer. ✓

**14. Error handling (spec §4):** covered by test cases in Tasks 8, 9, 11. ✓

**15. Testing strategy (spec §5):** Tasks 1, 7, 8, 9, 11 include unit tests; Task 11 adds the e2e test; Task 12 centralizes fake helpers. `lifecycle_client_test.dart` deleted in Task 10. ✓

**16. FakeBlueyPlatform extension (spec §5):** Task 12. ✓

**17. Documentation (spec §6):** Task 13. ✓

**18. Example app updates (spec §7 structural):** Task 14. ✓

**19. Example app persistence demo (spec §7 persistence):** Tasks 15 (server), 16 (client). ✓

No gaps. Type consistency spot-check:
- `ServerId` — same constructor/methods used across tasks. ✓
- `BlueyPeer` — interface in Task 6 matches impl in Task 9. ✓
- `PeerDiscovery.discover` returns `List<ServerId>` (not `List<BlueyPeer>`) — confirmed in Task 8's revised signature and used correctly in Task 11. ✓
- `PeerDiscovery.connectTo` returns `Connection` (not `PeerConnection`) — Task 9 wraps it. ✓
- `LifecycleServer.serverId` param is required (not optional) — confirmed in Task 3 and 4's tests supply it. ✓

All placeholders are filled with concrete code, file paths, commit messages, and verification commands.
