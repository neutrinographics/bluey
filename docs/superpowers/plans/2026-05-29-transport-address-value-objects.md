# Transport-address value objects (`DeviceAddress` / `ClientAddress`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the lossy `String → UUID` synthesis behind `Device.id` / `Client.id` with per-context value objects — `DeviceAddress` (Discovery/Connection) and `ClientAddress` (GATT-Server) — that hold the raw platform string natively, fixing the I337 cross-stream identifier mismatch by construction.

**Architecture:** A remote's transport identity becomes an immutable, equality-by-value, format-agnostic value object wrapping the platform string. The raw `String` lives only at the Pigeon seam (wrapped inbound, `.value`-unwrapped outbound); everything inside the domain — maps, sets, `LifecycleServer`, events, streams — holds the value object. Clean break, no deprecation shims (pre-1.0; consumers are in-repo and the analyzer is the migration tool).

**Tech Stack:** Dart/Flutter, `flutter_test`, `package:meta` (`@immutable`). Value objects follow the existing `ServerId` template (`bluey/lib/src/peer/server_id.dart`).

**Reference spec:** `docs/superpowers/specs/2026-05-29-transport-address-value-objects-design.md`

**Decision baked in (flagged for review):** The shared anti-corruption layer (`translatePlatformException`, `withErrorTranslation`) and `DisconnectedException` stay context-neutral — they take/carry a raw `String address`, not a value object, because they serve both the connection and server directions. Callers pass `.value`.

---

## File Structure

**New files:**
- `bluey/lib/src/discovery/device_address.dart` — `DeviceAddress` value object
- `bluey/test/discovery/device_address_test.dart` — its unit test
- `bluey/lib/src/gatt_server/client_address.dart` — `ClientAddress` value object
- `bluey/test/gatt_server/client_address_test.dart` — its unit test
- `bluey/test/gatt_server/i337_stream_bridge_test.dart` — the headline regression test

**Deleted files:**
- `bluey/lib/src/shared/device_id_coercion.dart`
- `bluey/test/device_id_coercion_test.dart`

**Modified (primary edits — call code shown in tasks):**
- `bluey/lib/src/discovery/device.dart` — collapse to `address : DeviceAddress`
- `bluey/lib/src/discovery/bluey_scanner.dart` — seam; delete `_deviceIdToUuid`
- `bluey/lib/bluey.dart` (`_mapDevice`) — seam
- `bluey/lib/src/connection/connection.dart` — `deviceAddress` getter
- `bluey/lib/src/connection/bluey_connection.dart` — field/helpers
- `bluey/lib/src/shared/exceptions.dart` — `DisconnectedException`
- `bluey/lib/src/shared/error_translation.dart` — `String? address`
- `bluey/lib/src/events.dart` — connection + server event id fields
- `bluey/lib/src/gatt_server/server.dart` — `Client.address`, `disconnections`, `isClientConnected`
- `bluey/lib/src/gatt_server/bluey_server.dart` — internals, seam, `BlueyClient`
- `bluey/lib/src/gatt_server/lifecycle_server.dart` — `ClientAddress` throughout

**Modified (analyzer-driven sweeps — mechanical, follow `flutter analyze`):**
- `bluey/lib/bluey.dart` barrel export (add the two value objects)
- ~40 test files + `bluey/test/fakes/test_helpers.dart`, `fake_platform.dart`
- `bluey/example/lib/features/server/**` and any scan/connection screens

> **Sweep convention used throughout:** when a task says "run the analyzer sweep," run `cd bluey && flutter analyze` and fix every reported error using the transformation rule given in that task, then `flutter test`. Enumerating every call site as its own code block would be thousands of identical edits; the analyzer enumerates them precisely and the rule is mechanical. Representative before/after is shown in each sweep step.

---

## Task 1: `DeviceAddress` value object

**Files:**
- Create: `bluey/lib/src/discovery/device_address.dart`
- Test: `bluey/test/discovery/device_address_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:bluey/src/discovery/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceAddress', () {
    test('preserves an Android MAC verbatim (no transformation)', () {
      const a = DeviceAddress('46:F9:31:94:D7:F6');
      expect(a.value, '46:F9:31:94:D7:F6');
      expect(a.toString(), '46:F9:31:94:D7:F6');
    });

    test('preserves an iOS UUID string verbatim', () {
      const a = DeviceAddress('dcee33dc-985a-48f5-87a9-670804c2c0de');
      expect(a.value, 'dcee33dc-985a-48f5-87a9-670804c2c0de');
    });

    test('equality is by value', () {
      const a = DeviceAddress('46:F9:31:94:D7:F6');
      const b = DeviceAddress('46:F9:31:94:D7:F6');
      const c = DeviceAddress('AA:BB:CC:DD:EE:FF');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toShortString truncates long values, leaves short ones', () {
      expect(const DeviceAddress('46:F9:31:94:D7:F6').toShortString(),
          '46:F9:31');
      expect(const DeviceAddress('short').toShortString(), 'short');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd bluey && flutter test test/discovery/device_address_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../device_address.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// bluey/lib/src/discovery/device_address.dart
import 'package:meta/meta.dart';

/// Opaque, platform-assigned address of a remote BLE **peripheral that this
/// device discovered or reached out to** — the *outbound* direction, in which
/// the local role is GATT **client** and the remote is the GATT server.
///
/// Sourced at the scan/connection seam from `PlatformDevice.id`: the MAC
/// address on Android, the `CBPeripheral.identifier` UUID string on iOS. The
/// format is platform-specific and opaque — never parse it.
///
/// Mirror of [ClientAddress], which addresses a remote central that connected
/// *inbound* to our local `Server`. Both wrap the same kind of platform
/// string; the distinct types keep the communication direction legible and
/// prevent accidental cross-assignment. The two coincide only when one peer
/// both scans and advertises (see `Server.isClientConnected`).
@immutable
class DeviceAddress {
  /// The raw platform identifier. Opaque — never parse.
  final String value;

  const DeviceAddress(this.value);

  /// A short form for display/logging only (first 8 chars).
  String toShortString() =>
      value.length <= 8 ? value : value.substring(0, 8);

  @override
  bool operator ==(Object other) =>
      other is DeviceAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
```

(The `[ClientAddress]` doc reference resolves once Task 4 lands; it is a doc comment, not code, so it does not break analysis.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd bluey && flutter test test/discovery/device_address_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/discovery/device_address.dart bluey/test/discovery/device_address_test.dart
git commit -m "feat(discovery): add DeviceAddress value object"
```

---

## Task 2: Migrate Discovery to `DeviceAddress`; delete coercion

**Files:**
- Modify: `bluey/lib/src/discovery/device.dart` (whole class)
- Modify: `bluey/lib/src/discovery/bluey_scanner.dart` (Device build + delete `_deviceIdToUuid` at `:400-413`)
- Modify: `bluey/lib/bluey.dart` (`_mapDevice` at `:824-830`, plus barrel export)
- Modify: `bluey/lib/src/events.dart` (`DeviceDiscoveredEvent`)
- Delete: `bluey/lib/src/shared/device_id_coercion.dart`, `bluey/test/device_id_coercion_test.dart`
- Test: `bluey/test/device_test.dart` (update)

- [ ] **Step 1: Update `device_test.dart` to the new shape (failing)**

Replace any `Device(id: UUID..., address: '...')` construction and `device.id` assertions. New `Device` has a single identity, `address : DeviceAddress`. Representative test body:

```dart
import 'package:bluey/src/discovery/device.dart';
import 'package:bluey/src/discovery/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Device', () {
    test('is identified by its address', () {
      final d = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'));
      expect(d.address, const DeviceAddress('AA:BB:CC:DD:EE:FF'));
    });

    test('entity equality is by address only', () {
      final a = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'), name: 'x');
      final b = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'), name: 'y');
      final c = Device(address: const DeviceAddress('11:22:33:44:55:66'));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith preserves address, updates name', () {
      final a = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'), name: 'x');
      expect(a.copyWith(name: 'z').name, 'z');
      expect(a.copyWith(name: 'z').address, a.address);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd bluey && flutter test test/device_test.dart`
Expected: FAIL — named param `id` removed / `address` type mismatch.

- [ ] **Step 3: Rewrite `Device`**

```dart
// bluey/lib/src/discovery/device.dart
import 'package:meta/meta.dart';

import 'device_address.dart';

/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [address] are considered
/// equal, even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
@immutable
class Device {
  /// Opaque, platform-assigned address of this remote device.
  ///
  /// On Android this is the MAC address; on iOS the `CBPeripheral.identifier`
  /// UUID string. Format is platform-specific — never parse it.
  final DeviceAddress address;

  /// Advertised device name, if available.
  final String? name;

  Device({required this.address, this.name});

  /// Creates a copy with updated fields.
  ///
  /// To explicitly set [name] to null, pass null. To keep the existing value,
  /// don't pass the parameter.
  Device copyWith({Object? name = _sentinel}) {
    return Device(
      address: address,
      name: name == _sentinel ? this.name : name as String?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is Device && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'Device(address: $address, name: $name)';
}
```

- [ ] **Step 4: Fix the two seam sites and delete the coercion helper**

`bluey/lib/bluey.dart` `_mapDevice`:

```dart
  Device _mapDevice(platform.PlatformDevice platformDevice) {
    return Device(
      address: DeviceAddress(platformDevice.id),
      name: platformDevice.name,
    );
  }
```

`bluey/lib/src/discovery/bluey_scanner.dart` — the `Device(...)` build becomes:

```dart
    final device = Device(
      address: DeviceAddress(platformDevice.id),
      name: platformDevice.name,
    );
```

…and **delete** the private `_deviceIdToUuid` method (`bluey_scanner.dart:400-413`). Add the import `import 'device_address.dart';` to the scanner and `import 'src/discovery/device_address.dart';`-equivalent wherever `_mapDevice` lives (`bluey.dart` already imports discovery; add the value-object import). Then:

```bash
rm bluey/lib/src/shared/device_id_coercion.dart bluey/test/device_id_coercion_test.dart
```

- [ ] **Step 5: Update `DeviceDiscoveredEvent`**

In `bluey/lib/src/events.dart`, change the field and its `toString`:

```dart
/// Device discovered during scan.
final class DeviceDiscoveredEvent extends BlueyEvent {
  final DeviceAddress deviceAddress;
  final String? name;
  final int? rssi;

  DeviceDiscoveredEvent({
    required this.deviceAddress,
    this.name,
    this.rssi,
    super.source,
  });

  @override
  String toString() {
    final n = name != null ? ' "$name"' : '';
    final r = rssi != null ? ' rssi=$rssi' : '';
    return '[Scan] Discovered ${deviceAddress.toShortString()}$n$r';
  }
}
```

Add `import 'discovery/device_address.dart';` to `events.dart`. Update the emit site (search `DeviceDiscoveredEvent(`) to pass `deviceAddress: device.address`.

- [ ] **Step 6: Add the barrel export**

In `bluey/lib/bluey.dart`, beside `export 'src/discovery/device.dart';`:

```dart
export 'src/discovery/device_address.dart';
```

- [ ] **Step 7: Analyzer sweep + tests**

Run: `cd bluey && flutter analyze`
Fix every error with this rule: `device.id` → `device.address`; `Device(id: X, address: Y, ...)` → `Device(address: DeviceAddress(Y or X.toString()), ...)`; any `deviceIdToUuid(s)` call → `DeviceAddress(s)`. In `test/fakes/test_helpers.dart` / `fake_platform.dart`, fixture device ids become `DeviceAddress('AA:BB:...')`.
Representative before/after:

```dart
// before
final d = Device(id: UUID('...'), address: 'AA:BB:CC:DD:EE:FF');
expect(scan.device.id, equals(UUID('...')));
// after
final d = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'));
expect(scan.device.address, const DeviceAddress('AA:BB:CC:DD:EE:FF'));
```

Then: `cd bluey && flutter test`
Expected: PASS (Connection-side `deviceId` still `UUID` until Task 3 — but `Device` no longer exposes a `UUID`; if any connection test built a `Connection` from `device.id`, change it to `device.address.value` for now; Task 3 retypes it properly).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(discovery): Device identified by DeviceAddress; delete lossy UUID coercion"
```

---

## Task 3: Migrate Connection to `DeviceAddress`

**Files:**
- Modify: `bluey/lib/src/connection/connection.dart:97` (`deviceAddress` getter)
- Modify: `bluey/lib/src/connection/bluey_connection.dart` (field, ctor, `_runGattOp`/`_loggedGattOp` params, `DisconnectedException` throw at `:447`)
- Modify: `bluey/lib/src/shared/exceptions.dart:81-87` (`DisconnectedException`)
- Modify: `bluey/lib/src/shared/error_translation.dart:27-42` (`String? address`)
- Modify: `bluey/lib/src/events.dart` (`ConnectingEvent`, `ConnectedEvent`, `DisconnectedEvent`, `DiscoveringServicesEvent`, `ServicesDiscoveredEvent`, and the rest carrying `deviceId`)
- Test: `bluey/test/connection/bluey_connection_disconnect_test.dart` (and the disconnect/exception assertions)

- [ ] **Step 1: Write/adjust a failing test for the new public type**

In `bluey/test/connection/bluey_connection_disconnect_test.dart`, assert the public getter type and the exception's `address`:

```dart
test('connection exposes deviceAddress and DisconnectedException carries it', () async {
  // ... arrange a connection to DeviceAddress('AA:BB:CC:DD:EE:FF') via fake platform
  expect(connection.deviceAddress, const DeviceAddress('AA:BB:CC:DD:EE:FF'));
  // after a link-loss disconnect:
  expect(
    () => connection.someGattOpThatFails(),
    throwsA(isA<DisconnectedException>()
        .having((e) => e.address, 'address', 'AA:BB:CC:DD:EE:FF')),
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd bluey && flutter test test/connection/bluey_connection_disconnect_test.dart`
Expected: FAIL — `deviceAddress` getter undefined; `DisconnectedException.address` undefined.

- [ ] **Step 3: Retype the shared anti-corruption layer (context-neutral String)**

`bluey/lib/src/shared/exceptions.dart`:

```dart
/// Connection was lost unexpectedly. [address] is the raw platform
/// identifier of the endpoint that disconnected (device or client) — a
/// leaf diagnostic value, opaque, do not parse.
class DisconnectedException extends BlueyException {
  final String address;
  final DisconnectReason reason;

  const DisconnectedException(this.address, this.reason)
    : super('Device disconnected: $reason', action: 'Reconnect if needed');
}
```

`bluey/lib/src/shared/error_translation.dart` — change the param and the construction (and drop the now-unused `uuid.dart` import if nothing else uses it):

```dart
BlueyException translatePlatformException(
  Object error, {
  required String operation,
  String? address,
}) {
  if (error is BlueyException) return error;
  // ...
  if (error is platform.GattOperationDisconnectedException) {
    return DisconnectedException(address ?? '', DisconnectReason.linkLoss);
  }
  // ...
```

Update `withErrorTranslation`'s `deviceId`/`deviceId:` forwarding to `address`/`address:` (in `error_translation.dart` where `withErrorTranslation` is defined).

- [ ] **Step 4: Retype `Connection` / `BlueyConnection`**

`bluey/lib/src/connection/connection.dart`:

```dart
  /// Opaque platform address of the remote device this connection targets.
  DeviceAddress get deviceAddress;
```
(rename the getter from `deviceId`; add `import '../discovery/device_address.dart';`).

`bluey/lib/src/connection/bluey_connection.dart`:
- Rename the field `final UUID deviceId;` → `final DeviceAddress deviceAddress;` and ctor param `required this.deviceAddress`.
- The factory entry param `UUID deviceId` / `required UUID deviceId` → `DeviceAddress deviceAddress`.
- `_runGattOp` / `_loggedGattOp` param `UUID deviceId` → `DeviceAddress deviceAddress`; internal callers updated. In the log `data:` maps, `'deviceId': deviceId.toString()` → `'deviceId': deviceAddress.toString()` (log key string unchanged; value comes from the VO).
- `withErrorTranslation(..., deviceId: deviceId)` → `withErrorTranslation(..., address: deviceAddress.value)`.
- `throw DisconnectedException(deviceId, DisconnectReason.unknown);` (`:447`) → `throw DisconnectedException(deviceAddress.value, DisconnectReason.unknown);`.
- Event emits pass `deviceAddress: deviceAddress` (see Step 5).

- [ ] **Step 5: Retype connection events**

In `bluey/lib/src/events.dart`, for each of `ConnectingEvent`, `ConnectedEvent`, `DisconnectedEvent`, `DiscoveringServicesEvent`, `ServicesDiscoveredEvent`, and the remaining events with `final UUID deviceId;` (the connection/GATT cluster), change the field to `final DeviceAddress deviceAddress;`, the ctor param to `required this.deviceAddress`, and `deviceId.toShortString()` in `toString()` → `deviceAddress.toShortString()`. Representative:

```dart
final class ConnectedEvent extends BlueyEvent {
  final DeviceAddress deviceAddress;
  ConnectedEvent({required this.deviceAddress, super.source});
  @override
  String toString() => '[Connection] Connected to ${deviceAddress.toShortString()}';
}
```

> Leave the **server-side** events (`ClientConnectedEvent` etc., the `clientId` cluster) unchanged here — they migrate in Task 6.

- [ ] **Step 6: Analyzer sweep + tests**

Run: `cd bluey && flutter analyze`
Fix-rule: `connection.deviceId` → `connection.deviceAddress`; event `deviceId:` named args → `deviceAddress:`; `e.deviceId` on `DisconnectedException` → `e.address`; constructing `BlueyConnection`/factory with `deviceId: device.id` → `deviceAddress: device.address`; any `.deviceId` read used as a String → `.deviceAddress.value`.
Then: `cd bluey && flutter test`
Expected: PASS (full suite).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(connection): deviceId -> deviceAddress (DeviceAddress); neutral String on DisconnectedException"
```

---

## Task 4: `ClientAddress` value object

**Files:**
- Create: `bluey/lib/src/gatt_server/client_address.dart`
- Test: `bluey/test/gatt_server/client_address_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:bluey/src/gatt_server/client_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientAddress', () {
    test('preserves an Android MAC verbatim', () {
      const a = ClientAddress('46:F9:31:94:D7:F6');
      expect(a.value, '46:F9:31:94:D7:F6');
      expect(a.toString(), '46:F9:31:94:D7:F6');
    });

    test('equality is by value', () {
      const a = ClientAddress('46:F9:31:94:D7:F6');
      const b = ClientAddress('46:F9:31:94:D7:F6');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(const ClientAddress('AA:BB:CC:DD:EE:FF'))));
    });

    test('toShortString truncates long values', () {
      expect(const ClientAddress('46:F9:31:94:D7:F6').toShortString(), '46:F9:31');
      expect(const ClientAddress('short').toShortString(), 'short');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd bluey && flutter test test/gatt_server/client_address_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Implement**

```dart
// bluey/lib/src/gatt_server/client_address.dart
import 'package:meta/meta.dart';

/// Opaque, platform-assigned address of a remote BLE **central that connected
/// inbound to our local `Server`** — the *inbound* direction, in which the
/// local role is GATT **server** and the remote is the GATT client.
///
/// Sourced at the GATT-server seam from `PlatformCentral.id` / `centralId`:
/// the MAC address on Android, the `CBCentral.identifier` UUID string on iOS.
/// The format is platform-specific and opaque — never parse it.
///
/// This is the value emitted on `Server.disconnections` and carried by the
/// server-side events, so it is the stable key for bridging the
/// `peerConnections` and `disconnections` streams (this is the fix for I337).
///
/// Mirror of `DeviceAddress`, which addresses a remote peripheral we
/// discovered/connected to *outbound*.
@immutable
class ClientAddress {
  /// The raw platform identifier. Opaque — never parse.
  final String value;

  const ClientAddress(this.value);

  /// A short form for display/logging only (first 8 chars).
  String toShortString() =>
      value.length <= 8 ? value : value.substring(0, 8);

  @override
  bool operator ==(Object other) =>
      other is ClientAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd bluey && flutter test test/gatt_server/client_address_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/gatt_server/client_address.dart bluey/test/gatt_server/client_address_test.dart
git commit -m "feat(gatt-server): add ClientAddress value object"
```

---

## Task 5: Migrate `LifecycleServer` + `BlueyServer` internals to `ClientAddress`

This is the largest task — it converts all internal server bookkeeping so no raw `String` client id survives in domain code (the structural guarantee against I337 regression). It deliberately does **not** change the public `Client.id` / `disconnections` types yet (Task 6) — to keep this task green, the seam wraps inbound and the public surfaces unwrap `.value` temporarily.

**Files:**
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart` (all `String clientId` → `ClientAddress`)
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart` (`_connectedClients`, `_identifiedPeerClientIds`, handlers, seam)
- Test: `bluey/test/bluey_server_test.dart`, lifecycle tests

- [ ] **Step 1: Retype `LifecycleServer`**

In `bluey/lib/src/gatt_server/lifecycle_server.dart` add `import 'client_address.dart';` and change every `String clientId` to `ClientAddress clientId`:
- `onClientGone : void Function(ClientAddress clientId)`
- `onPeerIdentified : void Function(ClientAddress clientId, ServerId senderId)?`
- `cancelTimer(ClientAddress clientId)`, `recordActivity(ClientAddress clientId)`, `requestStarted(ClientAddress clientId, int requestId)`, `requestCompleted(ClientAddress clientId, int requestId)`, `_resetTimer(ClientAddress clientId)`
- internal `_clients` map key type → `ClientAddress`
- At the inbound seam inside `handleWriteRequest`/`handleReadRequest`: `final clientId = ClientAddress(req.centralId);` (wrap the raw DTO string once, here).
- Log `data:` maps: `'clientId': clientId` → `'clientId': clientId.toString()`.

- [ ] **Step 2: Run lifecycle/server tests to see them fail**

Run: `cd bluey && flutter test test/bluey_server_test.dart`
Expected: FAIL — callers pass `String` where `ClientAddress` now required.

- [ ] **Step 3: Retype `BlueyServer` internals + seam**

In `bluey/lib/src/gatt_server/bluey_server.dart` (`import 'client_address.dart';`):
- `Map<String, BlueyClient> _connectedClients` → `Map<ClientAddress, BlueyClient>`.
- `Set<String> _identifiedPeerClientIds` → `Set<ClientAddress>`.
- Inbound seam (wrap once): in the connect callback, `final clientId = ClientAddress(platformCentral.id);`; in `_handleClientDisconnected(String raw)` change to accept the already-wrapped `ClientAddress` from the callback (wrap at the platform callback registration site, e.g. `onDisconnect: (raw) => _handleClientDisconnected(ClientAddress(raw))`).
- `_trackPeerClient(ClientAddress clientId, ServerId senderId)`.
- Request handlers: `_connectedClients[ClientAddress(platformRequest.centralId)]`.
- `_lifecycle.cancelTimer(clientId)` / `requestCompleted(...)` now receive `ClientAddress` (already wrapped).
- Outbound to platform stays `.value`: `_platform.notifyCharacteristicTo(blueyClient._platformId, ...)` is unaffected (uses the stored raw string — see Task 6 where `_platformId` becomes a `ClientAddress`); for this task keep `_platformId : String` and pass `clientId.value` where a map key meets a platform call.
- **Temporary unwrap at still-String public surfaces** (retyped in Task 6): `_disconnectionsController.add(clientId.value)`; event constructors still take `String` so pass `clientId.value`; `BlueyClient` ctor still takes `String id` so build it with `clientId.value`. `isClientConnected(String address)` → `_connectedClients.containsKey(ClientAddress(address))`.

- [ ] **Step 4: Analyzer sweep + tests**

Run: `cd bluey && flutter analyze` then fix call sites in `bluey_server.dart` and lifecycle/server tests (test calls like `lifecycle.recordActivity('mac')` → `lifecycle.recordActivity(const ClientAddress('mac'))`).
Then: `cd bluey && flutter test`
Expected: PASS (full suite — public types unchanged, so external assertions still compile).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(gatt-server): internal bookkeeping + LifecycleServer keyed by ClientAddress"
```

---

## Task 6: Public `Client.address`, server events, `disconnections` — close I337

**Files:**
- Modify: `bluey/lib/src/gatt_server/server.dart` (`Client.address`, `disconnections`, `isClientConnected`)
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart` (`BlueyClient`, controller types, event emits)
- Modify: `bluey/lib/src/events.dart` (6 server events: `clientId : String` → `clientAddress : ClientAddress`)
- Modify: `bluey/lib/bluey.dart` (export `client_address.dart`)
- Test (new): `bluey/test/gatt_server/i337_stream_bridge_test.dart`

- [ ] **Step 1: Write the headline I337 regression test (failing on a hypothetical pre-fix build)**

```dart
import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  test('I337: peerConnections client.address equals disconnections value (Android MAC)', () async {
    final fake = FakeBlueyPlatform();
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 'test');

    const mac = '46:F9:31:94:D7:F6'; // 17-char MAC: the exact I337 case
    final peers = <ClientAddress>[];
    final gone = <ClientAddress>[];
    server.peerConnections.listen((p) => peers.add(p.client.address));
    server.disconnections.listen(gone.add);

    // Simulate inbound central connect + lifecycle identify + disconnect.
    fake.simulateCentralConnected(mac, mtu: 23);
    fake.simulatePeerHeartbeat(mac, ServerId.generate());
    fake.simulateCentralDisconnected(mac);
    await Future<void>.delayed(Duration.zero);

    expect(peers.single, gone.single,
        reason: 'the bridge key must be identical across both streams');
    expect(gone.single, const ClientAddress(mac));

    await bluey.dispose();
  });
}
```

> Use the actual `FakeBlueyPlatform` helpers for simulating central connect / heartbeat / disconnect; adjust method names to those in `test/fakes/fake_platform.dart`. The assertion `peers.single == gone.single` is the contract.

- [ ] **Step 2: Run to verify it fails**

Run: `cd bluey && flutter test test/gatt_server/i337_stream_bridge_test.dart`
Expected: FAIL — `client.address` undefined (and `disconnections` still emits `String`, type mismatch with `List<ClientAddress>`).

- [ ] **Step 3: Retype `Client` + `BlueyClient`**

`bluey/lib/src/gatt_server/server.dart` (`import 'client_address.dart';`):

```dart
abstract class Client {
  /// Opaque platform address of this connected client — the same value
  /// emitted on [Server.disconnections]. Use it to bridge peerConnections
  /// and disconnections bookkeeping.
  ClientAddress get address;

  /// The current MTU for this connection.
  int get mtu;
}
```

```dart
  /// Stream of disconnected client addresses.
  Stream<ClientAddress> get disconnections;

  /// Whether a client with [address] is currently attached to this server.
  bool isClientConnected(ClientAddress address);
```

`bluey/lib/src/gatt_server/bluey_server.dart` — rewrite `BlueyClient` (delete the lossy `id` getter entirely):

```dart
class BlueyClient implements Client {
  final ClientAddress _address;
  final int _mtu;

  BlueyClient({required ClientAddress address, required int mtu})
    : _address = address,
      _mtu = mtu;

  @override
  ClientAddress get address => _address;

  @override
  int get mtu => _mtu;
}
```

Update construction: `BlueyClient(address: clientId, mtu: ...)` (where `clientId` is already a `ClientAddress` from Task 5). Where `_platformId` was previously passed to platform calls, use `client.address.value` (e.g. `notifyTo`/`indicateTo`: `_platform.notifyCharacteristicTo(client.address.value, handle, data)`).

- [ ] **Step 4: Retype the controllers, stream, `isClientConnected`, and event emits**

In `bluey_server.dart`:
- `StreamController<ClientAddress> _disconnectionsController` and `_disconnectionsController.add(clientId)` (no `.value` now).
- `isClientConnected(ClientAddress address) => _connectedClients.containsKey(address);`
- Event emits: pass `clientAddress: clientId` (the `ClientAddress`) to the server events.
- `withErrorTranslation(..., address: client.address.value)` for `notifyTo`/`indicateTo` (the ACL still takes `String?` — Task 3).

- [ ] **Step 5: Retype the 6 server events**

In `bluey/lib/src/events.dart` (`import 'gatt_server/client_address.dart';`), for `ClientConnectedEvent`, `ClientDisconnectedEvent`, `ReadRequestEvent`, `WriteRequestEvent`, `ClientLifecycleTimeoutEvent`, `LifecyclePausedForPendingRequestEvent`: change `final String clientId;` → `final ClientAddress clientAddress;`, ctor param `required this.clientAddress`, and replace the per-class private `_shortId(...)` helpers with `clientAddress.toShortString()`. Representative:

```dart
final class ClientDisconnectedEvent extends BlueyEvent {
  final ClientAddress clientAddress;
  ClientDisconnectedEvent({required this.clientAddress, super.source});
  @override
  String toString() => '[Server] Client disconnected: ${clientAddress.toShortString()}';
}
```

Delete the now-dead `_shortId` private methods. Add the export in `bluey/lib/bluey.dart`:

```dart
export 'src/gatt_server/client_address.dart';
```

- [ ] **Step 6: Run the I337 test + full suite**

Run: `cd bluey && flutter test test/gatt_server/i337_stream_bridge_test.dart`
Expected: PASS.
Run: `cd bluey && flutter analyze` (fix any remaining `clientId` references in tests → `clientAddress`, and `e.clientId` → `e.clientAddress`; `server.isClientConnected('mac')` → `server.isClientConnected(const ClientAddress('mac'))`).
Run: `cd bluey && flutter test`
Expected: PASS (full suite).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(gatt-server): Client.address (ClientAddress); disconnections emits ClientAddress; fixes I337"
```

---

## Task 7: Example app + final verification

**Files:**
- Modify: `bluey/example/lib/features/server/presentation/{server_screen.dart,server_cubit.dart,server_state.dart}` and any scan/connection screens referencing `device.id` / `client.id` / event `deviceId`/`clientId`.

- [ ] **Step 1: Analyzer sweep across the example**

Run: `cd bluey/example && flutter analyze`
Fix-rule:
- `client.id` → `client.address`; `client.id.toShortString()` → `client.address.toShortString()`; `client.id.toString()` → `client.address.toString()`.
- `Set<UUID> blueyPeerClientIds` / membership → `Set<ClientAddress>` keyed by `client.address`.
- `device.id` → `device.address`; `_shortId(client.id)` → `_shortId(client.address.toString())` (or pass the VO and call `.toShortString()`).
- Event field reads `e.clientId` → `e.clientAddress`, `e.deviceId` → `e.deviceAddress`.

Representative:

```dart
// server_state.dart — before
bool isBlueyPeer(Client client) => blueyPeerClientIds.contains(client.id);
// after
bool isBlueyPeer(Client client) => blueyPeerClientIds.contains(client.address);
```

- [ ] **Step 2: Build the example to confirm it compiles**

Run: `cd bluey/example && flutter analyze`
Expected: No issues.

- [ ] **Step 3: Full workspace verification**

Run:
```bash
cd bluey && flutter analyze && flutter test
cd bluey_platform_interface && flutter analyze && flutter test
```
Expected: analyzer clean; all tests pass (the `bluey` suite was 543 tests pre-change; expect that count minus the deleted `device_id_coercion_test.dart` cases, plus the new value-object and I337 tests).

- [ ] **Step 4: Update the backlog**

Mark `docs/backlog/I337-client-id-mismatch-between-peerconnections-and-disconnections.md` status `open` → `resolved`, noting the resolution (per-context value objects; Android-only manifestation correction) and the implementing branch.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(example): adopt DeviceAddress/ClientAddress; resolve I337"
```

---

## Self-Review

**Spec coverage:**
- Value objects `DeviceAddress`/`ClientAddress`, context-local, format-agnostic, no `toUuid` hatch → Tasks 1, 4. ✅
- Delete lossy coercion (all 3 sites) → Task 2 (helper + scanner copy), Task 6 (`Client.id` getter deleted). ✅
- Seam wrap/unwrap; platform-interface stays String → Tasks 2, 3, 5, 6. ✅
- `LifecycleServer` + internal maps retyped → Task 5. ✅
- `disconnections : Stream<ClientAddress>`, `isClientConnected(ClientAddress)`, event renames → Task 6. ✅
- `Connection.deviceId` → `deviceAddress`, connection events → Task 3. ✅
- `Device` equality moves to `address` → Task 2. ✅
- Clean break, no shims → reflected throughout (types swapped, sweeps). ✅
- I337 bridge test → Task 6. ✅
- Example migration → Task 7. ✅

**Placeholder scan:** No "TBD/TODO"; the one parametric area (the I337 test's `fake.simulate*` method names) is explicitly flagged to match `fake_platform.dart` rather than left vague. Sweep steps give a concrete fix-rule + representative before/after, which is the correct form for a clean-break type migration (per-site enumeration would be thousands of identical edits).

**Type consistency:** `DeviceAddress`/`ClientAddress` members (`value`, `toShortString()`, `==`, `toString`) identical across Tasks 1/4 and all references. `Connection.deviceAddress`, `Client.address`, `DisconnectedException.address (String)`, `translatePlatformException(address:)`, event fields `deviceAddress`/`clientAddress` used consistently in later tasks.

**Open decision (flagged):** `DisconnectedException.address` and the shared ACL use a raw `String`, not a value object (Task 3 rationale). If you'd rather the exception carry a typed address, that's a small change — say so before execution.
