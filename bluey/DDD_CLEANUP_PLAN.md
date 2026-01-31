# Bluey DDD/CA Cleanup Plan

This document outlines the plan to address terminology inconsistencies, architectural improvements, and DDD compliance issues identified in the audit.

## Overview

The cleanup is organized into three phases:
1. **Phase 1: Terminology & Naming** - Fix naming inconsistencies
2. **Phase 2: Structural Cleanup** - Remove unused code, fix exports
3. **Phase 3: Domain Model Enhancements** - Add missing domain concepts

Each phase can be completed independently, with Phase 1 being the highest priority.

---

## Phase 1: Terminology & Naming

### 1.1 Rename `platformId` to `address`

**Priority:** High  
**Breaking Change:** Yes  
**Files:** `device.dart`, `bluey.dart`, `bluey_connection.dart`, tests

**Current:**
```dart
class Device {
  final UUID id;
  final String platformId; // Confusing - it's actually MAC address on Android
}
```

**Target:**
```dart
class Device {
  /// Unique device identifier as a UUID.
  /// On iOS, this is the native CoreBluetooth UUID.
  /// On Android, this is derived from the MAC address.
  final UUID id;

  /// Hardware address used for platform connections.
  /// On Android, this is the MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, this is the same as [id] since iOS doesn't expose MAC addresses.
  final String address;
}
```

**Steps:**
1. Rename `platformId` → `address` in `Device` class
2. Update `Device` constructor and `copyWith`
3. Update `Bluey.connect()` to use `device.address`
4. Update `BlueyConnection` to use `address` terminology internally
5. Update all tests referencing `platformId`
6. Update documentation

---

### 1.2 Clarify `Device` as Snapshot Value Object

**Priority:** High  
**Breaking Change:** No  
**Files:** `device.dart`

**Current:**
```dart
/// A discovered BLE device.
///
/// Entity with identity based on [id]. Two devices with the same ID are
/// considered equal even if their other properties differ (e.g., updated RSSI).
///
/// Immutable value - use [copyWith] to create updated instances.
```

**Target:**
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

**Steps:**
1. Update class documentation to clarify "snapshot" semantics
2. Remove "Entity" terminology from comments

---

### 1.3 Rename `Local*` to `Hosted*` for Server-Side Types

**Priority:** Medium  
**Breaking Change:** Yes  
**Files:** `server.dart`, `bluey_server.dart`, tests

**Rationale:** "Local" isn't standard BLE terminology. "Hosted" better conveys that these are services/characteristics hosted by the GATT server.

**Current:**
```dart
class LocalService { ... }
class LocalCharacteristic { ... }
class LocalDescriptor { ... }
```

**Target:**
```dart
class HostedService { ... }
class HostedCharacteristic { ... }
class HostedDescriptor { ... }
```

**Steps:**
1. Rename classes in `server.dart`
2. Update `BlueyServer` to use new names
3. Update all tests
4. Add deprecation typedefs for migration (optional):
   ```dart
   @Deprecated('Use HostedService instead')
   typedef LocalService = HostedService;
   ```

---

### 1.4 Standardize `connectionId` vs `deviceId` Internal Naming

**Priority:** Low  
**Breaking Change:** No (internal only)  
**Files:** `bluey_connection.dart`

**Current:** Uses `_connectionId` internally but public API uses `deviceId`.

**Target:** Use `_deviceAddress` internally to match the connection identifier semantics.

**Steps:**
1. Rename `_connectionId` → `_deviceAddress` in `BlueyConnection`
2. Update all internal references
3. Keep public `deviceId` property unchanged (it returns the UUID)

---

## Phase 2: Structural Cleanup

### 2.1 Remove Unused `ScanStream`

**Priority:** High  
**Breaking Change:** No (never implemented)  
**Files:** `scan.dart`, `bluey.dart`

**Current:** `ScanStream` is defined but `Bluey.scan()` returns `Stream<Device>`.

**Options:**
- **Option A:** Remove `ScanStream` entirely
- **Option B:** Implement `ScanStream` with `stop()` and `isScanning`

**Recommendation:** Option A - Remove it. The current `Stream<Device>` API is sufficient, and users can call `bluey.stopScan()` separately.

**Steps:**
1. Delete `ScanStream` class from `scan.dart`
2. Remove export from `bluey.dart` library file
3. Update documentation if it references `ScanStream`

---

### 2.2 Single Export Location for `ConnectionState`

**Priority:** High  
**Breaking Change:** No  
**Files:** `bluey.dart`, `connection.dart`, `connection_state.dart`

**Current:** Exported from both `bluey.dart:17` and `connection.dart:5`.

**Target:** Export only from `connection.dart`, which re-exports it naturally as part of the Connection API.

**Steps:**
1. Remove `export 'connection_state.dart';` from `bluey.dart`
2. Keep `export 'connection_state.dart';` in `connection.dart`
3. Verify all imports still work

---

### 2.3 Hide `BlueyPlatform` from Public API

**Priority:** High  
**Breaking Change:** Yes (constructor parameter)  
**Files:** `bluey.dart`, `bluey_server.dart`, all tests

**Rationale:** The `platformOverride` constructor parameter exposes `BlueyPlatform` type to consumers. This is an infrastructure concern that should be hidden. Tests can inject the platform using the standard Flutter plugin pattern: setting `BlueyPlatform.instance` directly.

**Current:**
```dart
Bluey({platform.BlueyPlatform? platformOverride, BlueyEventBus? eventBus})
  : _platform = platformOverride ?? platform.BlueyPlatform.instance,
    _eventBus = eventBus ?? BlueyEventBus();
```

**Target:**
```dart
Bluey()
  : _platform = platform.BlueyPlatform.instance,
    _eventBus = BlueyEventBus();
```

**Test pattern (standard Flutter plugin approach):**
```dart
// Before
setUp(() {
  fakePlatform = FakeBlueyPlatform();
});
final bluey = Bluey(platformOverride: fakePlatform);

// After
setUp(() {
  fakePlatform = FakeBlueyPlatform();
  BlueyPlatform.instance = fakePlatform;
});
final bluey = Bluey();
```

**Steps:**
1. Remove `platformOverride` parameter from `Bluey` constructor
2. Remove `eventBus` parameter from `Bluey` constructor (combine with 2.4)
3. Update `Bluey` to always use `BlueyPlatform.instance`
4. Update all tests to set `BlueyPlatform.instance = fakePlatform` in setUp
5. Add tearDown to reset platform if needed (or rely on test isolation)
6. Verify `BlueyPlatform` type is not exposed in any public API signatures

**Benefits:**
- Clean public API: just `Bluey()` or `Bluey.shared`
- Follows Flutter plugin conventions (url_launcher, shared_preferences, etc.)
- Platform interface remains testable via instance setter
- Consumers never see infrastructure types

---

### 2.4 Make `BlueyEventBus` Fully Internal

**Priority:** Medium  
**Breaking Change:** Yes (constructor parameter)  
**Files:** `bluey.dart`, `event_bus.dart`

**Note:** This is now combined with 2.3 above. The `eventBus` parameter is removed as part of hiding platform details.

**Additional Steps:**
1. Remove `BlueyEventBus` from public exports (if exported)
2. Ensure `BlueyEventBus` is not referenced in any public API

---

### 2.5 Clean Up Exception `action` Field

**Priority:** Low  
**Breaking Change:** No  
**Files:** `exceptions.dart`

**Current:** `action` field exists but is inconsistently populated.

**Options:**
- **Option A:** Remove `action` field entirely
- **Option B:** Populate consistently for all exceptions

**Recommendation:** Option B - Keep and populate. It's useful for developer guidance.

**Steps:**
1. Add `action` to all exceptions that are missing it:
   - `ConnectionException`: "Check device is in range and advertising"
   - `DisconnectedException`: "Reconnect if needed"
   - `ServiceNotFoundException`: "Verify device supports this service"
   - `CharacteristicNotFoundException`: "Verify service contains this characteristic"
   - `GattException`: "Retry operation or check permissions"
2. Update base class to make `action` non-nullable with default

---

## Phase 3: Domain Model Enhancements

### 3.1 Add Server Request/Response Handling to Domain Layer

**Priority:** High  
**Breaking Change:** No (additive)  
**Files:** `server.dart`, `bluey_server.dart`

**Current:** Read/write request handling exists only in `FakeBlueyPlatform`. The domain layer has no model for handling requests.

**Target:** Add domain-level abstractions for request handling.

```dart
/// A read request from a connected central.
@immutable
class ReadRequest {
  final Central central;
  final UUID characteristicId;
  final int offset;

  const ReadRequest({
    required this.central,
    required this.characteristicId,
    this.offset = 0,
  });
}

/// A write request from a connected central.
@immutable
class WriteRequest {
  final Central central;
  final UUID characteristicId;
  final Uint8List value;
  final int offset;
  final bool responseNeeded;

  const WriteRequest({
    required this.central,
    required this.characteristicId,
    required this.value,
    this.offset = 0,
    this.responseNeeded = true,
  });
}

/// Response status for GATT operations.
enum GattResponseStatus {
  success,
  invalidOffset,
  invalidAttributeLength,
  requestNotSupported,
  // ... other statuses
}

abstract class Server {
  // Existing members...

  /// Stream of read requests from centrals.
  Stream<ReadRequest> get readRequests;

  /// Stream of write requests from centrals.
  Stream<WriteRequest> get writeRequests;

  /// Respond to a read request.
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  });

  /// Respond to a write request.
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  });
}
```

**Steps:**
1. Add `ReadRequest` and `WriteRequest` value objects to `server.dart`
2. Add `GattResponseStatus` enum (or reuse `GattStatus` from exceptions)
3. Add request streams and response methods to `Server` interface
4. Implement in `BlueyServer`
5. Update `FakeBlueyPlatform` to use domain types
6. Add tests

---

### 3.2 Add Notification vs Indication Distinction

**Priority:** Medium  
**Breaking Change:** No (additive)  
**Files:** `server.dart`, `bluey_server.dart`

**Current:** `notify()` and `notifyTo()` don't distinguish between notifications and indications.

**Target:** Add indication methods or a parameter.

**Option A: Separate methods**
```dart
Future<void> notify(UUID characteristic, {required Uint8List data});
Future<void> indicate(UUID characteristic, {required Uint8List data});
```

**Option B: Parameter**
```dart
Future<void> notify(
  UUID characteristic, {
  required Uint8List data,
  bool requireConfirmation = false, // true = indication
});
```

**Recommendation:** Option A for clarity.

**Steps:**
1. Add `indicate()` and `indicateTo()` methods to `Server` interface
2. Implement in `BlueyServer`
3. Update platform interface if needed
4. Add tests

---

### 3.3 Add Bonding/Pairing Domain Model

**Priority:** Low  
**Breaking Change:** No (additive)  
**Files:** New `bonding.dart`, `connection.dart`, `bluey.dart`

**Target:**
```dart
/// Bonding state of a device.
enum BondState {
  none,
  bonding,
  bonded,
}

abstract class Connection {
  // Existing members...

  /// Current bonding state.
  BondState get bondState;

  /// Stream of bonding state changes.
  Stream<BondState> get bondStateChanges;

  /// Initiate bonding/pairing with the device.
  Future<void> bond();

  /// Remove bond with the device.
  Future<void> removeBond();
}

class Bluey {
  /// Get all bonded devices.
  Future<List<Device>> get bondedDevices;
}
```

**Steps:**
1. Create `bonding.dart` with `BondState` enum
2. Add bonding methods to `Connection` interface
3. Add `bondedDevices` to `Bluey`
4. Implement in `BlueyConnection`
5. Update platform interface
6. Add tests

---

### 3.4 Add PHY (Physical Layer) Support

**Priority:** Low  
**Breaking Change:** No (additive)  
**Files:** New `phy.dart`, `connection.dart`

**Target:**
```dart
/// BLE Physical Layer options.
enum Phy {
  /// 1 Mbps PHY (default, most compatible)
  le1m,

  /// 2 Mbps PHY (faster, shorter range)
  le2m,

  /// Coded PHY (longer range, slower)
  leCoded,
}

abstract class Connection {
  // Existing members...

  /// Current transmit PHY.
  Phy get txPhy;

  /// Current receive PHY.
  Phy get rxPhy;

  /// Request specific PHY.
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy});

  /// Stream of PHY changes.
  Stream<({Phy tx, Phy rx})> get phyChanges;
}
```

**Steps:**
1. Create `phy.dart` with `Phy` enum
2. Add PHY methods to `Connection` interface
3. Implement in `BlueyConnection`
4. Update platform interface
5. Add tests

---

### 3.5 Add Connection Parameters

**Priority:** Low  
**Breaking Change:** No (additive)  
**Files:** New `connection_parameters.dart`, `connection.dart`

**Target:**
```dart
/// BLE connection parameters.
@immutable
class ConnectionParameters {
  /// Connection interval in milliseconds (7.5ms to 4s).
  final double intervalMs;

  /// Slave latency (number of connection events to skip).
  final int latency;

  /// Supervision timeout in milliseconds.
  final int timeoutMs;

  const ConnectionParameters({
    required this.intervalMs,
    required this.latency,
    required this.timeoutMs,
  });
}

abstract class Connection {
  // Existing members...

  /// Current connection parameters.
  ConnectionParameters get connectionParameters;

  /// Request updated connection parameters.
  Future<void> requestConnectionParameters(ConnectionParameters params);
}
```

**Steps:**
1. Create `connection_parameters.dart` with value object
2. Add to `Connection` interface
3. Implement in `BlueyConnection`
4. Update platform interface
5. Add tests

---

## Implementation Order

### Recommended Sequence

```
Phase 1 (Terminology) - 1-2 days
├── 1.1 Rename platformId → address
├── 1.2 Clarify Device documentation
├── 1.3 Rename Local* → Hosted*
└── 1.4 Standardize internal naming

Phase 2 (Structural) - 1-1.5 days
├── 2.1 Remove ScanStream
├── 2.2 Single ConnectionState export
├── 2.3 Hide BlueyPlatform from public API (HIGH)
├── 2.4 Make BlueyEventBus internal (combined with 2.3)
└── 2.5 Clean up exception actions

Phase 3 (Enhancements) - 2-3 days
├── 3.1 Server request/response handling (HIGH)
├── 3.2 Notification vs indication
├── 3.3 Bonding/pairing model
├── 3.4 PHY support
└── 3.5 Connection parameters
```

### Dependencies

- Phase 1 items are independent of each other
- Phase 2 items are independent of each other (except 2.3 and 2.4 which are combined)
- Phase 2.3 is high priority as it affects all tests
- Phase 3.1 should be done before other Phase 3 items
- Bonding (3.3) should be done before PHY (3.4) and Connection Parameters (3.5)

---

## Testing Strategy

For each change:

1. **Update existing tests** to use new naming/APIs
2. **Add new tests** for new functionality
3. **Run full test suite** after each item
4. **Update FakeBlueyPlatform** as needed to support new domain concepts

---

## Migration Notes

For breaking changes (1.1, 1.3, 2.3/2.4):

1. Since the library has no external users yet, we can make breaking changes freely
2. If users existed, we would:
   - Add `@Deprecated` annotations
   - Provide migration guide
   - Support old API for one version

---

## Success Criteria

- [x] All tests pass (424 tests passing)
- [x] No terminology inconsistencies in public API
- [x] Clear separation between domain and infrastructure
- [x] Comprehensive domain model for common BLE operations
- [x] Documentation updated to reflect changes
