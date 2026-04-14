# DDD & Clean Architecture Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the `bluey` core package to A+ DDD and Clean Architecture adherence across domain purity, ubiquitous language, bounded contexts, aggregate roots, and file organization.

**Architecture:** Bottom-up approach — mechanical refactors first (dependency swap, renames, file splits), then design-intensive changes (new value objects and aggregates), then structural reorganization (directory moves). Each task produces a working, testable codebase.

**Tech Stack:** Dart 3.7+, Flutter, `package:meta` (replacing `package:flutter/foundation.dart`)

**Spec:** `docs/superpowers/specs/2026-04-13-ddd-ca-refinement-design.md`

---

## Task 1: Replace `flutter/foundation` with `package:meta`

Replace the Flutter framework dependency in domain-layer types with the pure Dart `package:meta` package. This makes the domain layer framework-free.

**Files:**
- Modify: `bluey/pubspec.yaml`
- Modify: `bluey/lib/src/device.dart`
- Modify: `bluey/lib/src/characteristic_properties.dart`
- Modify: `bluey/lib/src/connection.dart`
- Modify: `bluey/lib/src/server.dart`
- Modify: `bluey/lib/src/events.dart`

Note: `uuid.dart` does NOT import `flutter/foundation` — no change needed there.

- [ ] **Step 1: Add `package:meta` dependency**

In `bluey/pubspec.yaml`, add `meta` under `dependencies`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  meta: ^1.11.0
  bluey_platform_interface:
    path: ../bluey_platform_interface
```

Run: `cd bluey && flutter pub get`
Expected: Resolves successfully.

- [ ] **Step 2: Update `device.dart` — replace import and add `_listEquals` helper**

In `bluey/lib/src/device.dart`:

Replace:
```dart
import 'package:flutter/foundation.dart';
```

With:
```dart
import 'package:meta/meta.dart';
```

Add a private helper function after the imports (before the `ManufacturerData` class):

```dart
/// Value equality for lists (replaces flutter/foundation listEquals).
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

Replace both calls to `listEquals(` with `_listEquals(` in the file (there are two: one in `ManufacturerData.==` and one in `Advertisement._mapsEqual`).

- [ ] **Step 3: Update `characteristic_properties.dart` — replace import**

In `bluey/lib/src/characteristic_properties.dart`:

Replace:
```dart
import 'package:flutter/foundation.dart';
```

With:
```dart
import 'package:meta/meta.dart';
```

No other changes — this file only uses `@immutable` from the import.

- [ ] **Step 4: Update `connection.dart` — replace import**

In `bluey/lib/src/connection.dart`:

Replace:
```dart
import 'package:flutter/foundation.dart';
```

With:
```dart
import 'package:meta/meta.dart';
```

No other changes — only uses `@immutable`.

- [ ] **Step 5: Update `server.dart` — replace import**

In `bluey/lib/src/server.dart`:

Replace:
```dart
import 'package:flutter/foundation.dart';
```

With:
```dart
import 'package:meta/meta.dart';
```

No other changes — only uses `@immutable`.

- [ ] **Step 6: Update `events.dart` — replace import and remove `_Now` class**

In `bluey/lib/src/events.dart`:

Replace:
```dart
import 'package:flutter/foundation.dart';
```

With:
```dart
import 'package:meta/meta.dart';
```

Remove the entire `_Now` class (lines 32-88).

Update the `BlueyEvent` base class — change from const constructor to regular constructor with default timestamp:

```dart
@immutable
sealed class BlueyEvent {
  final DateTime timestamp;
  final String? source;

  BlueyEvent({DateTime? timestamp, this.source})
    : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$runtimeType] ${_formatTime(timestamp)}';

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
```

Remove `const` from ALL event subclass constructors. There are 20 event subclasses — each one has `const` on its constructor. Remove `const` from every one:

- `ScanStartedEvent` — remove `const` from constructor
- `DeviceDiscoveredEvent` — remove `const` from constructor
- `ScanStoppedEvent` — remove `const` from constructor
- `ConnectingEvent` — remove `const` from constructor
- `ConnectedEvent` — remove `const` from constructor
- `DisconnectedEvent` — remove `const` from constructor
- `DiscoveringServicesEvent` — remove `const` from constructor
- `ServicesDiscoveredEvent` — remove `const` from constructor
- `CharacteristicReadEvent` — remove `const` from constructor
- `CharacteristicWrittenEvent` — remove `const` from constructor
- `NotificationReceivedEvent` — remove `const` from constructor
- `NotificationSubscriptionEvent` — remove `const` from constructor
- `ServerStartedEvent` — remove `const` from constructor
- `ServiceAddedEvent` — remove `const` from constructor
- `AdvertisingStartedEvent` — remove `const` from constructor
- `AdvertisingStoppedEvent` — remove `const` from constructor
- `ClientConnectedEvent` — remove `const` from constructor
- `ClientDisconnectedEvent` — remove `const` from constructor
- `ReadRequestEvent` — remove `const` from constructor
- `WriteRequestEvent` — remove `const` from constructor
- `NotificationSentEvent` — remove `const` from constructor
- `IndicationSentEvent` — remove `const` from constructor
- `ErrorEvent` — remove `const` from constructor
- `DebugEvent` — remove `const` from constructor

Also remove `const` from all event instantiations in `bluey.dart` and `bluey_server.dart` (every place that creates an event with `const ScanStartedEvent(...)` must become `ScanStartedEvent(...)`).

- [ ] **Step 7: Run all tests**

Run: `cd bluey && flutter test`
Expected: All 433 tests pass.

- [ ] **Step 8: Verify no remaining flutter/foundation imports in domain**

Run: `cd bluey && grep -r "package:flutter/foundation" lib/src/`
Expected: No output (zero matches).

- [ ] **Step 9: Commit**

```bash
cd bluey && git add pubspec.yaml pubspec.lock lib/src/device.dart lib/src/characteristic_properties.dart lib/src/connection.dart lib/src/server.dart lib/src/events.dart lib/src/bluey.dart lib/src/bluey_server.dart
git commit -m "refactor: replace flutter/foundation with package:meta in domain layer

Remove framework dependency from domain types. Replace @immutable import
with package:meta, replace listEquals with private helper, remove _Now
class boilerplate from events.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Fix Ubiquitous Language Issues

Four targeted fixes for naming and documentation consistency.

**Files:**
- Modify: `bluey/lib/src/device.dart`
- Modify: `bluey/lib/src/connection.dart`
- Modify: `bluey/lib/src/bluey_connection.dart`
- Modify: `bluey/lib/src/bluey_server.dart`

- [ ] **Step 1: Fix `Device` doc comment — "value object" → "entity"**

In `bluey/lib/src/device.dart`, replace the `Device` class doc comment:

```dart
/// A snapshot of a discovered BLE device at a point in time.
///
/// This is a value object representing device state when discovered or updated.
/// Two snapshots with the same [id] are considered equal, even if other
/// properties differ (e.g., RSSI changed). This enables deduplication in
/// collections while preserving the latest snapshot data.
///
/// Immutable - use [copyWith] to create updated snapshots.
```

With:

```dart
/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [id] are considered equal,
/// even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
```

- [ ] **Step 2: Fix `ConnectionParameters.latency` doc comment — "Slave" → "Peripheral"**

In `bluey/lib/src/connection.dart`, replace:

```dart
  /// Slave latency (0 to 499).
  ///
  /// The number of connection events the peripheral can skip if it has
  /// no data to send. Higher values save power but increase latency for
  /// peripheral-initiated communication.
  final int latency;
```

With:

```dart
  /// Peripheral latency (0 to 499).
  ///
  /// The number of connection events the peripheral can skip if it has
  /// no data to send. Higher values save power but increase latency for
  /// peripheral-initiated communication.
  final int latency;
```

- [ ] **Step 3: Rename `BlueyConnection._deviceAddress` → `_connectionId`**

In `bluey/lib/src/bluey_connection.dart`, rename the field declaration:

```dart
  final String _connectionId;
```

And update the constructor assignment:

```dart
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
  }) : _platform = platformInstance,
       _connectionId = connectionId {
```

Then replace all occurrences of `_deviceAddress` with `_connectionId` throughout the file. There are approximately 25 occurrences — every platform call that passes the connection handle. Use a find-and-replace for `_deviceAddress` → `_connectionId`.

- [ ] **Step 4: Make `BlueyClient.platformId` private**

In `bluey/lib/src/bluey_server.dart`, in the `BlueyClient` class, rename `platformId` to `_platformId`:

```dart
class BlueyClient implements Client {
  final platform.BlueyPlatform _platform;
  final String _platformId;
  final int _mtu;

  BlueyClient({
    required platform.BlueyPlatform platform,
    required String id,
    required int mtu,
  }) : _platform = platform,
       _platformId = id,
       _mtu = mtu;
```

Update the `id` getter:

```dart
  @override
  UUID get id {
    if (_platformId.length == 36 && _platformId.contains('-')) {
      return UUID(_platformId);
    }
    final bytes = _platformId.codeUnits;
    final padded = List<int>.filled(16, 0);
    for (var i = 0; i < bytes.length && i < 16; i++) {
      padded[i] = bytes[i];
    }
    final hex = padded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return UUID(hex);
  }
```

Update the `disconnect` method:

```dart
  @override
  Future<void> disconnect() async {
    await _platform.disconnectCentral(_platformId);
  }
```

Then update all references to `platformId` elsewhere in `BlueyServer` to use `_platformId`. These are in:
- `_connectedClients[platformCentral.id]` — these use `platformCentral.id` (the local variable), not the field, so no change needed
- `blueyClient.platformId` in `notifyTo()` — change to `blueyClient._platformId`
- `blueyClient.platformId` in `indicateTo()` — change to `blueyClient._platformId`
- `blueyClient.platformId` in `indicateCharacteristicTo()` — change to `blueyClient._platformId`
- `NotificationSentEvent(clientId: blueyClient.platformId)` — change to `blueyClient._platformId`
- `IndicationSentEvent(clientId: blueyClient.platformId)` — change to `blueyClient._platformId`

Since `BlueyClient` is defined in the same file as `BlueyServer`, private members are accessible.

- [ ] **Step 5: Run all tests**

Run: `cd bluey && flutter test`
Expected: All 433 tests pass.

- [ ] **Step 6: Commit**

```bash
cd bluey && git add lib/src/device.dart lib/src/connection.dart lib/src/bluey_connection.dart lib/src/bluey_server.dart
git commit -m "refactor: fix ubiquitous language issues

Update Device doc to say entity instead of value object. Replace
deprecated 'slave latency' with 'peripheral latency'. Rename
_deviceAddress to _connectionId. Make BlueyClient.platformId private.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Split `device.dart` Into Three Files

Extract `ManufacturerData` and `Advertisement` into their own files.

**Files:**
- Modify: `bluey/lib/src/device.dart`
- Create: `bluey/lib/src/manufacturer_data.dart`
- Create: `bluey/lib/src/advertisement.dart`
- Modify: `bluey/lib/bluey.dart` (barrel file)
- Modify: `bluey/lib/src/bluey.dart` (update imports)
- Modify: `bluey/lib/src/bluey_connection.dart` (update imports)
- Modify: `bluey/lib/src/server.dart` (update imports)
- Modify: `bluey/lib/src/bluey_server.dart` (update imports)

- [ ] **Step 1: Create `manufacturer_data.dart`**

Create `bluey/lib/src/manufacturer_data.dart` with the `ManufacturerData` class extracted from `device.dart`:

```dart
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Manufacturer-specific advertisement data.
///
/// Value object containing company ID and associated data.
@immutable
class ManufacturerData {
  final int companyId;
  final Uint8List data;

  const ManufacturerData(this.companyId, this.data);

  /// Well-known company IDs
  static const int apple = 0x004C;
  static const int google = 0x00E0;
  static const int microsoft = 0x0006;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ManufacturerData &&
        other.companyId == companyId &&
        _listEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(companyId, Object.hashAll(data));

  @override
  String toString() =>
      'ManufacturerData(companyId: 0x${companyId.toRadixString(16).padLeft(4, '0')}, data: $data)';
}

/// Value equality for lists.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 2: Create `advertisement.dart`**

Create `bluey/lib/src/advertisement.dart` with the `Advertisement` class extracted from `device.dart`:

```dart
import 'dart:collection';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'manufacturer_data.dart';
import 'uuid.dart';

/// BLE advertisement data.
///
/// Value object containing all data broadcast by a BLE peripheral.
/// Immutable — all collections are unmodifiable.
@immutable
class Advertisement {
  final List<UUID> serviceUuids;
  final Map<UUID, Uint8List> serviceData;
  final ManufacturerData? manufacturerData;
  final int? txPowerLevel;
  final bool isConnectable;

  Advertisement({
    required List<UUID> serviceUuids,
    required Map<UUID, Uint8List> serviceData,
    this.manufacturerData,
    this.txPowerLevel,
    required this.isConnectable,
  }) : serviceUuids = UnmodifiableListView(serviceUuids),
       serviceData = UnmodifiableMapView(serviceData);

  /// Creates an empty advertisement.
  factory Advertisement.empty() {
    return Advertisement(
      serviceUuids: [],
      serviceData: {},
      isConnectable: false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Advertisement &&
        _listEquals(other.serviceUuids, serviceUuids) &&
        _mapsEqual(other.serviceData, serviceData) &&
        other.manufacturerData == manufacturerData &&
        other.txPowerLevel == txPowerLevel &&
        other.isConnectable == isConnectable;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(serviceUuids),
    Object.hashAllUnordered(
      serviceData.entries.map(
        (e) => Object.hash(e.key, Object.hashAll(e.value)),
      ),
    ),
    manufacturerData,
    txPowerLevel,
    isConnectable,
  );

  @override
  String toString() {
    return 'Advertisement(serviceUuids: $serviceUuids, '
        'serviceData: ${serviceData.length} entries, '
        'manufacturerData: $manufacturerData, '
        'txPowerLevel: $txPowerLevel, '
        'isConnectable: $isConnectable)';
  }

  bool _mapsEqual(Map<UUID, Uint8List> a, Map<UUID, Uint8List> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_listEquals(a[key], b[key])) return false;
    }
    return true;
  }
}

/// Value equality for lists.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 3: Slim down `device.dart`**

Replace the contents of `bluey/lib/src/device.dart` with just the `Device` class. Remove the `ManufacturerData` and `Advertisement` classes and the `_listEquals` helper. Add imports for the extracted files:

```dart
import 'advertisement.dart';
import 'uuid.dart';

export 'advertisement.dart';
export 'manufacturer_data.dart';

/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [id] are considered equal,
/// even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
class Device {
  /// Unique device identifier as a UUID.
  ///
  /// On iOS, this is the native CoreBluetooth UUID.
  /// On Android, this is derived from the MAC address.
  final UUID id;

  /// Hardware address used for platform connections.
  ///
  /// On Android, this is the MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, this is the same as [id] since iOS doesn't expose MAC addresses.
  final String address;

  /// Advertised device name, if available.
  final String? name;

  /// Signal strength in dBm (typically -30 to -100).
  final int rssi;

  /// Advertisement data broadcast by the device.
  final Advertisement advertisement;

  /// When this device was last seen.
  final DateTime lastSeen;

  Device({
    required this.id,
    String? address,
    this.name,
    required this.rssi,
    required this.advertisement,
    DateTime? lastSeen,
  }) : address = address ?? id.toString(),
       lastSeen = lastSeen ?? DateTime.now();

  /// Creates a copy with updated fields.
  ///
  /// To explicitly set [name] to null, pass null. To keep the existing value,
  /// don't pass the parameter.
  Device copyWith({
    Object? name = _sentinel,
    int? rssi,
    Advertisement? advertisement,
    DateTime? lastSeen,
  }) {
    return Device(
      id: id,
      address: address,
      name: name == _sentinel ? this.name : name as String?,
      rssi: rssi ?? this.rssi,
      advertisement: advertisement ?? this.advertisement,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) {
    return other is Device && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Device(id: $id, name: $name, rssi: $rssi dBm, lastSeen: $lastSeen)';
  }
}
```

Note: `device.dart` re-exports `advertisement.dart` and `manufacturer_data.dart` so existing imports of `device.dart` continue to work without changes. The `import 'dart:collection'`, `import 'dart:typed_data'`, and `import 'package:meta/meta.dart'` are no longer needed in `device.dart` and should be removed.

- [ ] **Step 4: Update barrel file**

In `bluey/lib/bluey.dart`, add the new exports:

```dart
// Core value objects
export 'src/uuid.dart';
export 'src/device.dart';
export 'src/advertisement.dart';
export 'src/manufacturer_data.dart';
export 'src/characteristic_properties.dart';
```

- [ ] **Step 5: Update internal imports**

Files that directly import types from the old `device.dart` may need updating. Check and fix any import issues in:
- `bluey/lib/src/bluey.dart` — imports `device.dart`, uses `ManufacturerData`, `Advertisement`, `Device`. The re-exports from `device.dart` should cover this.
- `bluey/lib/src/server.dart` — imports `device.dart` for `ManufacturerData`. Change to import `manufacturer_data.dart`.
- `bluey/lib/src/bluey_server.dart` — imports `device.dart` for `ManufacturerData`. Change to import `manufacturer_data.dart`.
- `bluey/lib/src/bluey_connection.dart` — imports `device.dart`. The re-export covers its needs.

- [ ] **Step 6: Run all tests**

Run: `cd bluey && flutter test`
Expected: All 433 tests pass.

- [ ] **Step 7: Commit**

```bash
cd bluey && git add lib/src/device.dart lib/src/manufacturer_data.dart lib/src/advertisement.dart lib/bluey.dart lib/src/bluey.dart lib/src/server.dart lib/src/bluey_server.dart lib/src/bluey_connection.dart
git commit -m "refactor: extract ManufacturerData and Advertisement from device.dart

Split device.dart into three focused files: device.dart (Device entity),
advertisement.dart (Advertisement value object), manufacturer_data.dart
(ManufacturerData value object). Re-exports preserve backward compat
within the package.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Split `server.dart` Into Three Files

Extract hosted GATT types and request/response types into their own files.

**Files:**
- Modify: `bluey/lib/src/server.dart`
- Create: `bluey/lib/src/hosted_gatt.dart`
- Create: `bluey/lib/src/gatt_request.dart`
- Modify: `bluey/lib/bluey.dart` (barrel file)
- Modify: `bluey/lib/src/bluey_server.dart` (update imports)

- [ ] **Step 1: Create `hosted_gatt.dart`**

Create `bluey/lib/src/hosted_gatt.dart` with `HostedService`, `HostedCharacteristic`, and `HostedDescriptor`:

```dart
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'characteristic_properties.dart';
import 'uuid.dart';

/// Permissions for GATT characteristic and descriptor values.
///
/// These control what operations clients can perform on local attributes.
enum GattPermission {
  /// Allow reading the attribute value.
  read,

  /// Allow reading only with an encrypted connection.
  readEncrypted,

  /// Allow writing the attribute value.
  write,

  /// Allow writing only with an encrypted connection.
  writeEncrypted,
}

/// A descriptor hosted by this device's GATT server.
///
/// Descriptors provide metadata about characteristics. The most common
/// descriptor is the Client Characteristic Configuration Descriptor (CCCD)
/// used to enable notifications.
@immutable
class HostedDescriptor {
  /// The UUID of this descriptor.
  final UUID uuid;

  /// The permissions for this descriptor.
  final List<GattPermission> permissions;

  /// The static value of this descriptor (for immutable descriptors).
  final Uint8List? value;

  /// Creates a hosted descriptor with the given UUID and permissions.
  const HostedDescriptor({
    required this.uuid,
    required this.permissions,
    this.value,
  });

  /// Creates an immutable (read-only) descriptor with a static value.
  ///
  /// Use this for descriptors whose value never changes, like
  /// Characteristic User Description.
  factory HostedDescriptor.immutable({
    required UUID uuid,
    required Uint8List value,
  }) {
    return HostedDescriptor(
      uuid: uuid,
      permissions: const [GattPermission.read],
      value: value,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostedDescriptor && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A characteristic hosted by this device's GATT server.
///
/// Characteristics are the primary way clients interact with a peripheral.
/// They can be read, written, or subscribed to for notifications.
@immutable
class HostedCharacteristic {
  /// The UUID of this characteristic.
  final UUID uuid;

  /// The properties of this characteristic (read, write, notify, etc.).
  final CharacteristicProperties properties;

  /// The permissions for this characteristic's value.
  final List<GattPermission> permissions;

  /// The descriptors for this characteristic.
  final List<HostedDescriptor> descriptors;

  /// Creates a hosted characteristic.
  const HostedCharacteristic({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.descriptors = const [],
  });

  /// Creates a read-only characteristic.
  factory HostedCharacteristic.readable({
    required UUID uuid,
    List<HostedDescriptor> descriptors = const [],
  }) {
    return HostedCharacteristic(
      uuid: uuid,
      properties: const CharacteristicProperties(canRead: true),
      permissions: const [GattPermission.read],
      descriptors: descriptors,
    );
  }

  /// Creates a writable characteristic.
  factory HostedCharacteristic.writable({
    required UUID uuid,
    bool withResponse = true,
    List<HostedDescriptor> descriptors = const [],
  }) {
    return HostedCharacteristic(
      uuid: uuid,
      properties: CharacteristicProperties(
        canWrite: withResponse,
        canWriteWithoutResponse: !withResponse,
      ),
      permissions: const [GattPermission.write],
      descriptors: descriptors,
    );
  }

  /// Creates a notifiable characteristic.
  ///
  /// Notifiable characteristics can push updates to subscribed clients.
  factory HostedCharacteristic.notifiable({
    required UUID uuid,
    List<HostedDescriptor> descriptors = const [],
  }) {
    return HostedCharacteristic(
      uuid: uuid,
      properties: const CharacteristicProperties(canNotify: true),
      permissions: const [GattPermission.read],
      descriptors: descriptors,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HostedCharacteristic && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

/// A service hosted by this device's GATT server.
///
/// Services group related characteristics together. For example, the
/// Heart Rate Service contains the Heart Rate Measurement characteristic.
@immutable
class HostedService {
  /// The UUID of this service.
  final UUID uuid;

  /// Whether this is a primary service.
  ///
  /// Primary services are discoverable by clients. Secondary services
  /// can only be included by other services.
  final bool isPrimary;

  /// The characteristics in this service.
  final List<HostedCharacteristic> characteristics;

  /// Other services included by this service.
  final List<HostedService> includedServices;

  /// Creates a hosted service.
  const HostedService({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
    this.includedServices = const [],
  });

  @override
  bool operator ==(Object other) {
    return other is HostedService && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}
```

- [ ] **Step 2: Create `gatt_request.dart`**

Create `bluey/lib/src/gatt_request.dart` with `ReadRequest`, `WriteRequest`, and `GattResponseStatus`:

```dart
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'server.dart';
import 'uuid.dart';

/// Response status for GATT operations.
///
/// Used when responding to read or write requests from clients.
enum GattResponseStatus {
  /// Operation completed successfully.
  success,

  /// Read operation not permitted.
  readNotPermitted,

  /// Write operation not permitted.
  writeNotPermitted,

  /// Invalid offset for the attribute value.
  invalidOffset,

  /// Invalid attribute value length.
  invalidAttributeLength,

  /// Insufficient authentication for the operation.
  insufficientAuthentication,

  /// Insufficient encryption for the operation.
  insufficientEncryption,

  /// Request not supported.
  requestNotSupported,
}

/// A read request from a connected client.
///
/// When a client reads a characteristic value, a [ReadRequest] is emitted
/// on [Server.readRequests]. The server must respond using [Server.respondToRead].
@immutable
class ReadRequest {
  /// The client that initiated this request.
  final Client client;

  /// The characteristic being read.
  final UUID characteristicId;

  /// The offset into the characteristic value.
  final int offset;

  // Internal request ID for response correlation.
  // ignore: public_member_api_docs
  final int internalRequestId;

  /// Creates a read request.
  const ReadRequest({
    required this.client,
    required this.characteristicId,
    required this.offset,
    required this.internalRequestId,
  });
}

/// A write request from a connected client.
///
/// When a client writes to a characteristic, a [WriteRequest] is emitted
/// on [Server.writeRequests]. If [responseNeeded] is true, the server must
/// respond using [Server.respondToWrite].
@immutable
class WriteRequest {
  /// The client that initiated this request.
  final Client client;

  /// The characteristic being written.
  final UUID characteristicId;

  /// The value being written.
  final Uint8List value;

  /// The offset into the characteristic value.
  final int offset;

  /// Whether a response is needed.
  ///
  /// If true, the server must call [Server.respondToWrite].
  /// If false, this is a "write without response" operation.
  final bool responseNeeded;

  // Internal request ID for response correlation.
  // ignore: public_member_api_docs
  final int internalRequestId;

  /// Creates a write request.
  const WriteRequest({
    required this.client,
    required this.characteristicId,
    required this.value,
    required this.offset,
    required this.responseNeeded,
    required this.internalRequestId,
  });
}
```

- [ ] **Step 3: Slim down `server.dart`**

Remove `HostedDescriptor`, `HostedCharacteristic`, `HostedService`, `GattPermission`, `GattResponseStatus`, `ReadRequest`, and `WriteRequest` from `bluey/lib/src/server.dart`. Add re-exports so existing imports continue to work:

At the top of `server.dart`, after existing imports, add:

```dart
export 'gatt_request.dart';
export 'hosted_gatt.dart';
```

Add imports for the types still used in the `Server` interface:

```dart
import 'gatt_request.dart';
import 'hosted_gatt.dart';
```

The file should then contain only `Client` (abstract class) and `Server` (abstract class), plus their imports.

- [ ] **Step 4: Update barrel file**

In `bluey/lib/bluey.dart`, add exports for the new files:

```dart
// Server (Peripheral role)
export 'src/server.dart';
export 'src/hosted_gatt.dart';
export 'src/gatt_request.dart';
```

- [ ] **Step 5: Update `bluey_server.dart` imports**

In `bluey/lib/src/bluey_server.dart`, add imports for the extracted types if not already available through `server.dart` re-export:

```dart
import 'gatt_request.dart';
import 'hosted_gatt.dart';
```

- [ ] **Step 6: Run all tests**

Run: `cd bluey && flutter test`
Expected: All 433 tests pass.

- [ ] **Step 7: Commit**

```bash
cd bluey && git add lib/src/server.dart lib/src/hosted_gatt.dart lib/src/gatt_request.dart lib/bluey.dart lib/src/bluey_server.dart
git commit -m "refactor: extract hosted GATT types and request types from server.dart

Split server.dart into three files: server.dart (Server + Client
interfaces), hosted_gatt.dart (HostedService, HostedCharacteristic,
HostedDescriptor, GattPermission), gatt_request.dart (ReadRequest,
WriteRequest, GattResponseStatus).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Introduce `ScanResult` Value Object

Create a `ScanResult` value object that separates transient observation data from stable device identity, and update `Device` to be a pure entity.

**Files:**
- Create: `bluey/test/scan_result_test.dart`
- Create: `bluey/lib/src/scan_result.dart`
- Modify: `bluey/lib/src/device.dart`
- Modify: `bluey/lib/src/bluey.dart`
- Modify: `bluey/lib/bluey.dart` (barrel file)
- Modify: `bluey/test/device_test.dart`
- Modify: `bluey/test/bluey_test.dart`
- Modify: Multiple integration test files

- [ ] **Step 1: Write failing tests for `ScanResult`**

Create `bluey/test/scan_result_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanResult', () {
    late Device device;
    late Advertisement advertisement;

    setUp(() {
      device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
        name: 'Test Device',
      );
      advertisement = Advertisement(
        serviceUuids: [UUID.short(0x180D)],
        serviceData: {},
        isConnectable: true,
      );
    });

    test('creates with required fields', () {
      final now = DateTime.now();
      final result = ScanResult(
        device: device,
        rssi: -65,
        advertisement: advertisement,
        lastSeen: now,
      );

      expect(result.device, equals(device));
      expect(result.rssi, equals(-65));
      expect(result.advertisement, equals(advertisement));
      expect(result.lastSeen, equals(now));
    });

    test('defaults lastSeen to now', () {
      final before = DateTime.now();
      final result = ScanResult(
        device: device,
        rssi: -65,
        advertisement: advertisement,
      );
      final after = DateTime.now();

      expect(result.lastSeen.isAfter(before) || result.lastSeen.isAtSameMomentAs(before), isTrue);
      expect(result.lastSeen.isBefore(after) || result.lastSeen.isAtSameMomentAs(after), isTrue);
    });

    test('equality based on all fields', () {
      final now = DateTime(2026, 1, 1);
      final result1 = ScanResult(
        device: device,
        rssi: -65,
        advertisement: advertisement,
        lastSeen: now,
      );
      final result2 = ScanResult(
        device: device,
        rssi: -65,
        advertisement: advertisement,
        lastSeen: now,
      );

      expect(result1, equals(result2));
      expect(result1.hashCode, equals(result2.hashCode));
    });

    test('not equal when rssi differs', () {
      final now = DateTime(2026, 1, 1);
      final result1 = ScanResult(
        device: device,
        rssi: -65,
        advertisement: advertisement,
        lastSeen: now,
      );
      final result2 = ScanResult(
        device: device,
        rssi: -80,
        advertisement: advertisement,
        lastSeen: now,
      );

      expect(result1, isNot(equals(result2)));
    });

    test('not equal when advertisement differs', () {
      final now = DateTime(2026, 1, 1);
      final ad1 = Advertisement(
        serviceUuids: [UUID.short(0x180D)],
        serviceData: {},
        isConnectable: true,
      );
      final ad2 = Advertisement(
        serviceUuids: [UUID.short(0x180F)],
        serviceData: {},
        isConnectable: true,
      );
      final result1 = ScanResult(
        device: device,
        rssi: -65,
        advertisement: ad1,
        lastSeen: now,
      );
      final result2 = ScanResult(
        device: device,
        rssi: -65,
        advertisement: ad2,
        lastSeen: now,
      );

      expect(result1, isNot(equals(result2)));
    });

    test('toString includes key fields', () {
      final result = ScanResult(
        device: device,
        rssi: -65,
        advertisement: advertisement,
      );

      final str = result.toString();
      expect(str, contains('ScanResult'));
      expect(str, contains('-65'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd bluey && flutter test test/scan_result_test.dart`
Expected: FAIL — `ScanResult` class not found.

- [ ] **Step 3: Implement `ScanResult`**

Create `bluey/lib/src/scan_result.dart`:

```dart
import 'package:meta/meta.dart';

import 'advertisement.dart';
import 'device.dart';

/// A snapshot of a BLE device observation at a point in time.
///
/// This is a value object — two scan results are equal when all their
/// fields match. Contains transient observation data (signal strength,
/// advertisement, timestamp) alongside the stable [device] identity.
///
/// Immutable.
@immutable
class ScanResult {
  /// The discovered device.
  final Device device;

  /// Signal strength in dBm (typically -30 to -100).
  final int rssi;

  /// Advertisement data broadcast by the device.
  final Advertisement advertisement;

  /// When this device was last seen.
  final DateTime lastSeen;

  ScanResult({
    required this.device,
    required this.rssi,
    required this.advertisement,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScanResult &&
        other.device == device &&
        other.rssi == rssi &&
        other.advertisement == advertisement &&
        other.lastSeen == lastSeen;
  }

  @override
  int get hashCode => Object.hash(device, rssi, advertisement, lastSeen);

  @override
  String toString() {
    return 'ScanResult(device: ${device.id}, rssi: $rssi dBm, '
        'advertisement: $advertisement)';
  }
}
```

- [ ] **Step 4: Export `ScanResult` from barrel file**

In `bluey/lib/bluey.dart`, add:

```dart
export 'src/scan_result.dart';
```

- [ ] **Step 5: Run `ScanResult` tests to verify they pass**

Run: `cd bluey && flutter test test/scan_result_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Slim down `Device` — remove transient fields**

In `bluey/lib/src/device.dart`, remove `rssi`, `advertisement`, `lastSeen` from `Device`. Remove the `advertisement.dart` import and re-export (they'll be re-exported by other paths). The new `device.dart`:

```dart
import 'uuid.dart';

/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [id] are considered equal,
/// even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
class Device {
  /// Unique device identifier as a UUID.
  ///
  /// On iOS, this is the native CoreBluetooth UUID.
  /// On Android, this is derived from the MAC address.
  final UUID id;

  /// Hardware address used for platform connections.
  ///
  /// On Android, this is the MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, this is the same as [id] since iOS doesn't expose MAC addresses.
  final String address;

  /// Advertised device name, if available.
  final String? name;

  Device({
    required this.id,
    String? address,
    this.name,
  }) : address = address ?? id.toString();

  /// Creates a copy with updated fields.
  Device copyWith({
    Object? name = _sentinel,
  }) {
    return Device(
      id: id,
      address: address,
      name: name == _sentinel ? this.name : name as String?,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) {
    return other is Device && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Device(id: $id, name: $name)';
  }
}
```

Remove the re-exports (`export 'advertisement.dart'` and `export 'manufacturer_data.dart'`) from `device.dart` — these will be exported directly from the barrel file.

- [ ] **Step 7: Update `Bluey._mapDevice` to return `ScanResult`**

In `bluey/lib/src/bluey.dart`:

Add import:
```dart
import 'scan_result.dart';
```

Rename `_mapDevice` to `_mapScanResult` and update it to return `ScanResult`:

```dart
  ScanResult _mapScanResult(platform.PlatformDevice platformDevice) {
    // Convert manufacturer data
    ManufacturerData? manufacturerData;
    if (platformDevice.manufacturerDataCompanyId != null &&
        platformDevice.manufacturerData != null) {
      manufacturerData = ManufacturerData(
        platformDevice.manufacturerDataCompanyId!,
        Uint8List.fromList(platformDevice.manufacturerData!),
      );
    }

    // Convert service UUIDs
    final serviceUuids =
        platformDevice.serviceUuids.map((s) => UUID(s)).toList();

    // Create advertisement
    final advertisement = Advertisement(
      serviceUuids: serviceUuids,
      serviceData: {}, // TODO: Add service data when platform supports it
      manufacturerData: manufacturerData,
      isConnectable: true, // TODO: Get from platform when available
    );

    // Create device
    final device = Device(
      id: _deviceIdToUuid(platformDevice.id),
      address: platformDevice.id,
      name: platformDevice.name,
    );

    return ScanResult(
      device: device,
      rssi: platformDevice.rssi,
      advertisement: advertisement,
    );
  }
```

Update `scan()` to return `Stream<ScanResult>`:

```dart
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    _emitEvent(ScanStartedEvent(serviceFilter: services, timeout: timeout));

    return _platform
        .scan(config)
        .map((platformDevice) {
          final result = _mapScanResult(platformDevice);
          _emitEvent(
            DeviceDiscoveredEvent(
              deviceId: result.device.id,
              name: result.device.name,
              rssi: result.rssi,
            ),
          );
          return result;
        })
        .handleError((error) => throw _wrapError(error));
  }
```

Update `bondedDevices` — create `Device` without transient fields:

```dart
  Future<List<Device>> get bondedDevices async {
    try {
      final platformDevices = await _platform.getBondedDevices();
      return platformDevices.map((pd) => Device(
        id: _deviceIdToUuid(pd.id),
        address: pd.id,
        name: pd.name,
      )).toList();
    } catch (e) {
      throw _wrapError(e);
    }
  }
```

Also add the required import for `Advertisement` and `ManufacturerData`:

```dart
import 'advertisement.dart';
import 'manufacturer_data.dart';
```

Export `scan_result.dart`:

```dart
export 'scan_result.dart';
```

- [ ] **Step 8: Update `device_test.dart`**

In `bluey/test/device_test.dart`, remove tests for `rssi`, `advertisement`, and `lastSeen` on `Device`. Update `Device` construction calls to remove those fields. Keep the `Advertisement` and `ManufacturerData` test groups (they're testing standalone classes now).

Update the Device construction — every `Device(...)` call in the test needs `rssi`, `advertisement`, and `lastSeen` parameters removed. The `copyWith` tests for `rssi`, `advertisement`, and `lastSeen` should be removed.

Update imports to include `advertisement.dart` and `manufacturer_data.dart` if needed (or ensure the barrel import covers them).

- [ ] **Step 9: Update `bluey_test.dart` scan tests**

In `bluey/test/bluey_test.dart`, the scan group (lines ~394-486) currently does:

```dart
final devices = <Device>[];
final subscription = bluey.scan().listen(devices.add);
```

Change to:

```dart
final results = <ScanResult>[];
final subscription = bluey.scan().listen(results.add);
```

Then update assertions to access `results.first.device.name`, `results.first.rssi`, `results.first.advertisement`, etc. instead of `devices.first.name`, `devices.first.rssi`, etc.

- [ ] **Step 10: Update integration tests — add `scanFirstDevice` helper to `test_helpers.dart`**

Most integration tests use `await bluey.scan().first` to get a `Device` for connection. Add a helper to `test/fakes/test_helpers.dart`:

```dart
import 'package:bluey/bluey.dart';

/// Scans for the first device — convenience for tests that need
/// a Device to connect to.
Future<Device> scanFirstDevice(Bluey bluey) async {
  final result = await bluey.scan().first;
  return result.device;
}
```

Then update all integration test files to use `scanFirstDevice(bluey)` instead of `bluey.scan().first`:

Replace pattern `await bluey.scan().first` → `await scanFirstDevice(bluey)` across:
- `test/integration/service_discovery_test.dart`
- `test/integration/connection_lifecycle_test.dart`
- `test/integration/data_exchange_test.dart`
- `test/integration/error_scenarios_test.dart`
- `test/integration/concurrent_operations_test.dart`
- `test/integration/state_machine_test.dart`
- `test/integration/advanced_scenarios_test.dart`
- `test/integration/real_world_scenarios_test.dart`
- `test/integration/descriptor_operations_test.dart`

Each file needs `import '../fakes/test_helpers.dart';` if not already present.

For tests that use `bluey.scan().listen(devices.add)` — change the list type to `List<ScanResult>` and update assertions to access `.device` on each result.

- [ ] **Step 11: Run all tests**

Run: `cd bluey && flutter test`
Expected: All tests pass (count may change slightly due to test additions/removals).

- [ ] **Step 12: Commit**

```bash
cd bluey && git add lib/ test/
git commit -m "feat: introduce ScanResult value object, slim down Device entity

ScanResult captures transient observation data (rssi, advertisement,
lastSeen). Device becomes a pure entity with only stable identity
fields (id, address, name). scan() now returns Stream<ScanResult>.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Introduce `Scanner` Aggregate

Create a `Scanner` aggregate root for the Discovery bounded context.

**Files:**
- Create: `bluey/test/scanner_test.dart`
- Create: `bluey/lib/src/scanner.dart`
- Create: `bluey/lib/src/bluey_scanner.dart`
- Modify: `bluey/lib/src/bluey.dart`
- Modify: `bluey/lib/bluey.dart` (barrel file)
- Modify: `bluey/test/bluey_test.dart`
- Modify: `bluey/test/fakes/test_helpers.dart`
- Modify: Multiple integration test files

- [ ] **Step 1: Write failing tests for `Scanner`**

Create `bluey/test/scanner_test.dart`:

```dart
import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_platform.dart';
import 'fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Scanner', () {
    test('scanner() returns a Scanner instance', () {
      final scanner = bluey.scanner();
      expect(scanner, isNotNull);
      scanner.dispose();
    });

    test('isScanning is false initially', () {
      final scanner = bluey.scanner();
      expect(scanner.isScanning, isFalse);
      scanner.dispose();
    });

    test('scan emits discovered devices as ScanResults', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Heart Rate Monitor',
        rssi: -65,
        services: [
          TestServiceBuilder(TestUuids.heartRateService)
              .withNotifiable(TestUuids.heartRateMeasurement)
              .build(),
        ],
      );

      final scanner = bluey.scanner();
      final results = <ScanResult>[];
      final subscription = scanner.scan().listen(results.add);

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(results, hasLength(1));
      expect(results.first.device.name, equals('Heart Rate Monitor'));
      expect(results.first.rssi, equals(-65));

      scanner.dispose();
    });

    test('isScanning is true during scan', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Device',
      );

      final scanner = bluey.scanner();
      final subscription = scanner.scan().listen((_) {});

      // Allow scan to start
      await Future.delayed(const Duration(milliseconds: 10));
      expect(scanner.isScanning, isTrue);

      await subscription.cancel();
      await scanner.stop();

      scanner.dispose();
    });

    test('stop is idempotent', () async {
      final scanner = bluey.scanner();

      // Stopping when not scanning should not throw
      await scanner.stop();
      await scanner.stop();

      scanner.dispose();
    });

    test('scan with service filter', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Heart Rate Monitor',
        services: [
          TestServiceBuilder(TestUuids.heartRateService)
              .withNotifiable(TestUuids.heartRateMeasurement)
              .build(),
        ],
      );
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device2,
        name: 'Battery Device',
        services: [
          TestServiceBuilder(TestUuids.batteryService)
              .withReadable(TestUuids.batteryLevel)
              .build(),
        ],
      );

      final scanner = bluey.scanner();
      final results = <ScanResult>[];
      final subscription = scanner
          .scan(services: [UUID(TestUuids.heartRateService)])
          .listen(results.add);

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(results, hasLength(1));
      expect(results.first.device.name, equals('Heart Rate Monitor'));

      scanner.dispose();
    });

    test('scan with timeout', () async {
      final scanner = bluey.scanner();

      // Just verify it accepts the parameter without error
      final subscription = scanner
          .scan(timeout: const Duration(seconds: 10))
          .listen((_) {});

      await Future.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();

      scanner.dispose();
    });

    test('dispose cleans up resources', () async {
      final scanner = bluey.scanner();
      final subscription = scanner.scan().listen((_) {});

      await Future.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();
      scanner.dispose();

      // After dispose, the scanner should not throw
      // (implementation detail: streams are closed)
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd bluey && flutter test test/scanner_test.dart`
Expected: FAIL — `scanner()` method not found on `Bluey`.

- [ ] **Step 3: Create `Scanner` abstract interface**

Create `bluey/lib/src/scanner.dart`:

```dart
import 'scan_result.dart';
import 'uuid.dart';

/// Aggregate root for the Discovery bounded context.
///
/// The Scanner manages BLE device scanning operations. Obtain a Scanner
/// from [Bluey.scanner()], use it to scan for devices, then [dispose]
/// when done.
///
/// Example:
/// ```dart
/// final scanner = bluey.scanner();
/// await for (final result in scanner.scan(timeout: Duration(seconds: 10))) {
///   print('Found: ${result.device.name} at ${result.rssi} dBm');
/// }
/// scanner.dispose();
/// ```
abstract class Scanner {
  /// Whether a scan is currently active.
  bool get isScanning;

  /// Start scanning for nearby BLE devices.
  ///
  /// Returns a stream of [ScanResult]s. The stream completes when
  /// scanning stops (timeout or [stop] called).
  ///
  /// [services] — Optional list of service UUIDs to filter by.
  /// [timeout] — Optional timeout duration.
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout});

  /// Stop the current scan.
  ///
  /// Idempotent — safe to call when not scanning.
  Future<void> stop();

  /// Release all resources held by this scanner.
  ///
  /// After calling dispose, this scanner instance should not be used.
  void dispose();
}
```

- [ ] **Step 4: Create `BlueyScanner` implementation**

Create `bluey/lib/src/bluey_scanner.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'advertisement.dart';
import 'device.dart';
import 'event_bus.dart';
import 'events.dart';
import 'manufacturer_data.dart';
import 'scan_result.dart';
import 'scanner.dart';
import 'uuid.dart';

/// Internal implementation of [Scanner] that wraps platform calls.
///
/// This class is created by [Bluey.scanner] and should not be instantiated
/// directly by users.
class BlueyScanner implements Scanner {
  final platform.BlueyPlatform _platform;
  final BlueyEventBus _eventBus;

  bool _isScanning = false;
  StreamSubscription? _scanSubscription;

  BlueyScanner(this._platform, this._eventBus);

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    _isScanning = true;
    _eventBus.emit(ScanStartedEvent(serviceFilter: services, timeout: timeout));

    return _platform
        .scan(config)
        .map((platformDevice) {
          final result = _mapScanResult(platformDevice);
          _eventBus.emit(
            DeviceDiscoveredEvent(
              deviceId: result.device.id,
              name: result.device.name,
              rssi: result.rssi,
            ),
          );
          return result;
        })
        .handleError((error) {
          _isScanning = false;
          throw error;
        });
  }

  @override
  Future<void> stop() async {
    if (!_isScanning) return;
    await _platform.stopScan();
    _isScanning = false;
    _eventBus.emit(ScanStoppedEvent());
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _isScanning = false;
  }

  ScanResult _mapScanResult(platform.PlatformDevice platformDevice) {
    ManufacturerData? manufacturerData;
    if (platformDevice.manufacturerDataCompanyId != null &&
        platformDevice.manufacturerData != null) {
      manufacturerData = ManufacturerData(
        platformDevice.manufacturerDataCompanyId!,
        Uint8List.fromList(platformDevice.manufacturerData!),
      );
    }

    final serviceUuids =
        platformDevice.serviceUuids.map((s) => UUID(s)).toList();

    final advertisement = Advertisement(
      serviceUuids: serviceUuids,
      serviceData: {},
      manufacturerData: manufacturerData,
      isConnectable: true,
    );

    final device = Device(
      id: _deviceIdToUuid(platformDevice.id),
      address: platformDevice.id,
      name: platformDevice.name,
    );

    return ScanResult(
      device: device,
      rssi: platformDevice.rssi,
      advertisement: advertisement,
    );
  }

  UUID _deviceIdToUuid(String id) {
    if (id.length == 36 && id.contains('-')) {
      return UUID(id);
    }
    final clean = id.replaceAll(':', '').toLowerCase();
    final padded = clean.padLeft(32, '0');
    return UUID(padded);
  }
}
```

- [ ] **Step 5: Update `Bluey` — add `scanner()`, remove `scan()`/`stopScan()`**

In `bluey/lib/src/bluey.dart`:

Add imports:
```dart
import 'bluey_scanner.dart';
import 'scanner.dart';
```

Add export:
```dart
export 'scanner.dart';
```

Add the `scanner()` factory method:

```dart
  /// Create a Scanner for discovering nearby BLE devices.
  ///
  /// Returns a [Scanner] aggregate for the Discovery bounded context.
  /// Call [Scanner.dispose] when done to release resources.
  ///
  /// Example:
  /// ```dart
  /// final scanner = bluey.scanner();
  /// await for (final result in scanner.scan(timeout: Duration(seconds: 10))) {
  ///   print('Found: ${result.device.name}');
  /// }
  /// scanner.dispose();
  /// ```
  Scanner scanner() {
    return BlueyScanner(_platform, _eventBus);
  }
```

Remove the `scan()` method, `stopScan()` method, `_mapScanResult()` method, and `_deviceIdToUuid()` method from `Bluey`. These are now in `BlueyScanner`.

Keep `_deviceIdToUuid` in `Bluey` only if `bondedDevices` still uses it — if so, keep it. Otherwise move it entirely to `BlueyScanner`.

Check: `bondedDevices` still needs `_deviceIdToUuid`. Keep it in `Bluey` as well (duplication is acceptable between the two files, or extract to a shared private utility — but at two usages, duplication is fine).

Also remove the `ScanStartedEvent`, `DeviceDiscoveredEvent`, `ScanStoppedEvent` emissions from `Bluey` (they're now in `BlueyScanner`).

Remove imports no longer needed: `scan_result.dart`, `advertisement.dart`, `manufacturer_data.dart` (if only used by the removed scan mapping code). Keep any imports still used by `bondedDevices` or other methods.

- [ ] **Step 6: Update barrel file**

In `bluey/lib/bluey.dart`, add:

```dart
export 'src/scanner.dart';
```

- [ ] **Step 7: Run `Scanner` tests to verify they pass**

Run: `cd bluey && flutter test test/scanner_test.dart`
Expected: All tests PASS.

- [ ] **Step 8: Update `test_helpers.dart` — change `scanFirstDevice` to use Scanner**

In `bluey/test/fakes/test_helpers.dart`, update the helper:

```dart
/// Scans for the first device — convenience for tests that need
/// a Device to connect to.
Future<Device> scanFirstDevice(Bluey bluey) async {
  final scanner = bluey.scanner();
  final result = await scanner.scan().first;
  scanner.dispose();
  return result.device;
}
```

- [ ] **Step 9: Update `bluey_test.dart` — remove scan tests from Bluey, update remaining**

In `bluey/test/bluey_test.dart`:

The scan test group (testing `bluey.scan()`) should be moved to `scanner_test.dart` or rewritten to use `bluey.scanner().scan()`. Since we already have scanner tests, remove the scan group from `bluey_test.dart` and instead verify that `bluey.scanner()` returns a non-null Scanner:

```dart
    test('scanner() returns a Scanner', () {
      final scanner = bluey.scanner();
      expect(scanner, isA<Scanner>());
      scanner.dispose();
    });
```

Move the manufacturer data conversion test and service UUID conversion test to `scanner_test.dart` if they aren't already covered.

- [ ] **Step 10: Update integration tests — replace `bluey.scan()` with scanner pattern**

All integration test files that use `bluey.scan().first` already use `scanFirstDevice(bluey)` from Step 10 of Task 5. Verify they all work.

For integration tests that use `bluey.scan().listen(...)` (collecting multiple results), update to use the scanner:

```dart
// Before:
final devices = <Device>[];
final subscription = bluey.scan().listen(devices.add);

// After:
final scanner = bluey.scanner();
final results = <ScanResult>[];
final subscription = scanner.scan().listen(results.add);
// ... later ...
await subscription.cancel();
scanner.dispose();
```

Update assertions from `devices.first` to `results.first.device` where needed.

Files that use the listen pattern (check each):
- `test/integration/concurrent_operations_test.dart`
- `test/integration/connection_lifecycle_test.dart`
- `test/integration/real_world_scenarios_test.dart`
- `test/integration/state_machine_test.dart`
- `test/integration/advanced_scenarios_test.dart`
- `test/integration/error_scenarios_test.dart`

- [ ] **Step 11: Run all tests**

Run: `cd bluey && flutter test`
Expected: All tests pass.

- [ ] **Step 12: Commit**

```bash
cd bluey && git add lib/ test/
git commit -m "feat: introduce Scanner aggregate for Discovery bounded context

Scanner is the aggregate root for device discovery. Obtained via
bluey.scanner(), paralleling the Server pattern. scan() and stopScan()
removed from Bluey. Scanning logic moved to BlueyScanner.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Reorganize Into Bounded Context Directories

Move all source files into their bounded context directories. Pure structural change — no logic modifications.

**Files:**
- Create directories: `lib/src/shared/`, `lib/src/discovery/`, `lib/src/connection/`, `lib/src/gatt_client/`, `lib/src/gatt_server/`, `lib/src/platform/`
- Move ~20 files into new locations
- Modify: `bluey/lib/bluey.dart` (barrel file — update all export paths)
- Modify: All `lib/src/*.dart` files (update relative imports)

- [ ] **Step 1: Create directory structure**

```bash
cd bluey && mkdir -p lib/src/shared lib/src/discovery lib/src/connection lib/src/gatt_client lib/src/gatt_server lib/src/platform
```

- [ ] **Step 2: Move shared kernel files**

```bash
cd bluey
git mv lib/src/uuid.dart lib/src/shared/uuid.dart
git mv lib/src/manufacturer_data.dart lib/src/shared/manufacturer_data.dart
git mv lib/src/characteristic_properties.dart lib/src/shared/characteristic_properties.dart
git mv lib/src/exceptions.dart lib/src/shared/exceptions.dart
```

- [ ] **Step 3: Move discovery context files**

```bash
cd bluey
git mv lib/src/scanner.dart lib/src/discovery/scanner.dart
git mv lib/src/bluey_scanner.dart lib/src/discovery/bluey_scanner.dart
git mv lib/src/device.dart lib/src/discovery/device.dart
git mv lib/src/advertisement.dart lib/src/discovery/advertisement.dart
git mv lib/src/scan_result.dart lib/src/discovery/scan_result.dart
git mv lib/src/scan.dart lib/src/discovery/scan.dart
```

- [ ] **Step 4: Move connection context files**

```bash
cd bluey
git mv lib/src/connection.dart lib/src/connection/connection.dart
git mv lib/src/bluey_connection.dart lib/src/connection/bluey_connection.dart
git mv lib/src/connection_state.dart lib/src/connection/connection_state.dart
```

- [ ] **Step 5: Move GATT client context files**

```bash
cd bluey
git mv lib/src/gatt.dart lib/src/gatt_client/gatt.dart
git mv lib/src/well_known_uuids.dart lib/src/gatt_client/well_known_uuids.dart
```

- [ ] **Step 6: Move GATT server context files**

```bash
cd bluey
git mv lib/src/server.dart lib/src/gatt_server/server.dart
git mv lib/src/bluey_server.dart lib/src/gatt_server/bluey_server.dart
git mv lib/src/hosted_gatt.dart lib/src/gatt_server/hosted_gatt.dart
git mv lib/src/gatt_request.dart lib/src/gatt_server/gatt_request.dart
```

- [ ] **Step 7: Extract `BluetoothState` into platform context**

Create `bluey/lib/src/platform/bluetooth_state.dart`:

```dart
/// The state of the Bluetooth adapter.
enum BluetoothState {
  /// Initial state before platform reports.
  unknown,

  /// Device doesn't support BLE.
  unsupported,

  /// Permission not granted.
  unauthorized,

  /// Bluetooth is disabled.
  off,

  /// Bluetooth is ready to use.
  on;

  /// Whether Bluetooth is ready for use.
  bool get isReady => this == BluetoothState.on;

  /// Whether Bluetooth can be enabled (only true when off).
  bool get canBeEnabled => this == BluetoothState.off;
}
```

Remove the `BluetoothState` enum from `bluey/lib/src/bluey.dart` and add:

```dart
import 'platform/bluetooth_state.dart';
export 'platform/bluetooth_state.dart';
```

- [ ] **Step 8: Update barrel file with new paths**

Replace `bluey/lib/bluey.dart` contents:

```dart
/// Bluey — A modern, elegant Bluetooth Low Energy library for Flutter
///
/// This library provides a clean, intuitive API for BLE operations following
/// Domain-Driven Design and Clean Architecture principles.
library bluey;

// Application facade
export 'src/bluey.dart';

// Shared kernel
export 'src/shared/uuid.dart';
export 'src/shared/manufacturer_data.dart';
export 'src/shared/characteristic_properties.dart';
export 'src/shared/exceptions.dart';

// Discovery bounded context
export 'src/discovery/scanner.dart';
export 'src/discovery/device.dart';
export 'src/discovery/advertisement.dart';
export 'src/discovery/scan_result.dart';
export 'src/discovery/scan.dart';

// Connection bounded context
export 'src/connection/connection.dart';

// GATT Client bounded context
export 'src/gatt_client/gatt.dart';
export 'src/gatt_client/well_known_uuids.dart';

// GATT Server bounded context
export 'src/gatt_server/server.dart';
export 'src/gatt_server/hosted_gatt.dart';
export 'src/gatt_server/gatt_request.dart';

// Domain events
export 'src/events.dart';
```

- [ ] **Step 9: Update all internal imports**

This is the bulk of the work. Every `lib/src/` file that imports another `lib/src/` file needs its relative import paths updated. Update each file:

**`lib/src/bluey.dart`** — update imports:
```dart
import 'connection/bluey_connection.dart';
import 'discovery/bluey_scanner.dart';
import 'discovery/device.dart';
import 'discovery/scanner.dart';
import 'discovery/scan_result.dart';
import 'gatt_server/bluey_server.dart';
import 'gatt_server/server.dart';
import 'shared/exceptions.dart';
import 'shared/uuid.dart';
import 'platform/bluetooth_state.dart';
```

**`lib/src/discovery/bluey_scanner.dart`** — update imports:
```dart
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import '../event_bus.dart';
import '../events.dart';
import 'advertisement.dart';
import 'device.dart';
import 'scan_result.dart';
import 'scanner.dart';
```

**`lib/src/discovery/scanner.dart`** — same-directory imports unchanged, update:
```dart
import '../shared/uuid.dart';
import 'scan_result.dart';
```

**`lib/src/discovery/scan_result.dart`** — same-directory imports unchanged:
```dart
import 'advertisement.dart';
import 'device.dart';
```

**`lib/src/discovery/advertisement.dart`** — update imports:
```dart
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
```

**`lib/src/discovery/device.dart`** — update imports:
```dart
import '../shared/uuid.dart';
```

**`lib/src/connection/connection.dart`** — update imports:
```dart
import 'connection_state.dart';
import '../gatt_client/gatt.dart';
import '../shared/uuid.dart';
```

**`lib/src/connection/bluey_connection.dart`** — update imports:
```dart
import '../shared/characteristic_properties.dart';
import 'connection.dart';
import 'connection_state.dart';
import '../shared/exceptions.dart';
import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/uuid.dart';
```

**`lib/src/gatt_client/gatt.dart`** — update imports:
```dart
import '../shared/characteristic_properties.dart';
import '../shared/uuid.dart';
```

**`lib/src/gatt_client/well_known_uuids.dart`** — update imports:
```dart
import '../shared/uuid.dart';
```

**`lib/src/gatt_server/server.dart`** — update imports:
```dart
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import 'gatt_request.dart';
import 'hosted_gatt.dart';
```

**`lib/src/gatt_server/bluey_server.dart`** — update imports:
```dart
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import '../event_bus.dart';
import '../events.dart';
import '../lifecycle.dart' as lifecycle;
import 'gatt_request.dart';
import 'hosted_gatt.dart';
import 'server.dart';
```

**`lib/src/gatt_server/hosted_gatt.dart`** — update imports:
```dart
import '../shared/characteristic_properties.dart';
import '../shared/uuid.dart';
```

**`lib/src/gatt_server/gatt_request.dart`** — update imports:
```dart
import 'server.dart';
import '../shared/uuid.dart';
```

**`lib/src/events.dart`** — update imports:
```dart
import 'shared/uuid.dart';
```

**`lib/src/lifecycle.dart`** — no import changes needed (only imports platform interface).

**`lib/src/event_bus.dart`** — no import changes needed (only imports `events.dart`).

- [ ] **Step 10: Run all tests**

Run: `cd bluey && flutter test`
Expected: All tests pass. Tests import via the barrel file (`package:bluey/bluey.dart`) so they don't need path updates.

- [ ] **Step 11: Verify no files remain in flat `lib/src/` that should have moved**

```bash
ls bluey/lib/src/*.dart
```

Expected remaining files:
- `bluey.dart` (application facade)
- `events.dart` (cross-cutting)
- `event_bus.dart` (cross-cutting internal)
- `lifecycle.dart` (cross-cutting internal)

All other `.dart` files should be in subdirectories.

- [ ] **Step 12: Commit**

```bash
cd bluey && git add lib/
git commit -m "refactor: organize source into bounded context directories

Move files into shared/, discovery/, connection/, gatt_client/,
gatt_server/, and platform/ directories. Extract BluetoothState
into platform context. Cross-cutting concerns (events, lifecycle)
remain at src/ root. All imports updated.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Final Verification

Run full test suite and analysis to confirm everything is clean.

**Files:** None modified.

- [ ] **Step 1: Run full test suite**

Run: `cd bluey && flutter test`
Expected: All tests pass.

- [ ] **Step 2: Run static analysis**

Run: `cd bluey && flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Verify no `flutter/foundation` imports in domain**

Run: `cd bluey && grep -r "package:flutter/foundation" lib/src/`
Expected: No output.

- [ ] **Step 4: Verify directory structure matches spec**

Run: `cd bluey && find lib/src -name "*.dart" | sort`

Expected:
```
lib/src/bluey.dart
lib/src/connection/bluey_connection.dart
lib/src/connection/connection.dart
lib/src/connection/connection_state.dart
lib/src/discovery/advertisement.dart
lib/src/discovery/bluey_scanner.dart
lib/src/discovery/device.dart
lib/src/discovery/scan.dart
lib/src/discovery/scan_result.dart
lib/src/discovery/scanner.dart
lib/src/event_bus.dart
lib/src/events.dart
lib/src/gatt_client/gatt.dart
lib/src/gatt_client/well_known_uuids.dart
lib/src/gatt_server/bluey_server.dart
lib/src/gatt_server/gatt_request.dart
lib/src/gatt_server/hosted_gatt.dart
lib/src/gatt_server/server.dart
lib/src/lifecycle.dart
lib/src/platform/bluetooth_state.dart
lib/src/shared/characteristic_properties.dart
lib/src/shared/exceptions.dart
lib/src/shared/manufacturer_data.dart
lib/src/shared/uuid.dart
```

- [ ] **Step 5: Verify barrel file exports**

Run: `cd bluey && grep "^export" lib/bluey.dart | wc -l`
Expected: ~16 exports covering all public types.
