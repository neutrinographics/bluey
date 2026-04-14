# DDD & Clean Architecture Refinement — Design Spec

## Goal

Bring the `bluey` core package to A+ adherence across all DDD and Clean Architecture dimensions: domain purity, ubiquitous language, bounded context structure, aggregate roots, and file organization. No backward compatibility constraints — the library has no external consumers yet.

## Approach

Bottom-up (Approach A): mechanical, low-risk refactors first, then design-intensive changes, then structural reorganization. Each step produces a working, testable codebase.

---

## Step 1: Domain Purity — Remove `flutter/foundation`

### Problem

Domain-layer types (`UUID`, `Device`, `Advertisement`, `CharacteristicProperties`, events) import `package:flutter/foundation.dart` for `@immutable` and `listEquals()`. This creates a framework dependency in the domain layer, violating Clean Architecture's dependency rule.

### Changes

- Replace `package:flutter/foundation.dart` with `package:meta/meta.dart` for the `@immutable` annotation in all domain files: `uuid.dart`, `device.dart`, `characteristic_properties.dart`, `connection.dart`, `events.dart`, `server.dart` (for hosted GATT types).
- Replace `listEquals()` calls in `device.dart` (`Advertisement` equality) with a private `_listEquals<T>()` helper function in that file. No external dependency needed for a two-line function.
- Remove the `_Now` class from `events.dart` (50+ lines of `DateTime` delegation boilerplate). Replace with non-const constructors on event classes that initialize `timestamp` via `DateTime.now()` when not provided. Events are runtime-created objects — `const` constructors provide no benefit.
- Add `package:meta` as a dependency in `bluey/pubspec.yaml` (it's likely already a transitive dependency but should be explicit).

### Impact

Zero behavior change. All existing tests pass without modification. Domain types become pure Dart, theoretically portable outside Flutter.

---

## Step 2: Ubiquitous Language Fixes

### Problem

Four instances where naming or documentation leaks platform concepts, uses deprecated terminology, or is internally inconsistent.

### Changes

**2a. `Device` doc comment** — Replace "This is a value object" with "This is an entity" and explain identity-based equality. (Full entity/value-object distinction completes in Step 4 when `ScanResult` is introduced.)

**2b. `ConnectionParameters.latency` doc comment** — Replace "Slave latency" with "Peripheral latency" per current Bluetooth SIG inclusive terminology guidelines.

**2c. `BlueyConnection._deviceAddress`** — Rename field to `_connectionId`. The constructor parameter is already named `connectionId`; the field should match. It serves as a connection handle for platform calls, not a "device address."

**2d. `BlueyClient.platformId`** — Make the field private (`_platformId`). It's only accessed within `bluey_server.dart` where `BlueyClient` is defined. The cast `client as BlueyClient` in `BlueyServer.notifyTo()` / `indicateTo()` accesses it — change these to use `_platformId`. The public `Client` interface (`id`, `mtu`, `disconnect()`) remains unchanged.

### Impact

No API changes. Internal naming becomes consistent with domain language. All tests pass without modification.

---

## Step 3: Split Overloaded Files

### Problem

`device.dart` (190 lines, 3 classes, 2 bounded contexts) and `server.dart` (453 lines, 10 types) pack too many concepts into single files.

### Changes

**3a. `device.dart` splits into three files:**

| New file | Contents | Rationale |
|----------|----------|-----------|
| `device.dart` | `Device` entity | Core Discovery entity |
| `advertisement.dart` | `Advertisement` value object | Discovery context, also consumed by Server |
| `manufacturer_data.dart` | `ManufacturerData` value object | Shared kernel — used by Discovery and Server |

**3b. `server.dart` splits into three files:**

| New file | Contents | Rationale |
|----------|----------|-----------|
| `server.dart` | `Server` abstract interface, `Client` abstract class | Aggregate root + direct collaborator |
| `hosted_gatt.dart` | `HostedService`, `HostedCharacteristic`, `HostedDescriptor` | GATT Server building blocks |
| `gatt_request.dart` | `ReadRequest`, `WriteRequest`, `GattResponseStatus`, `GattPermission` | Request/response types |

**Barrel file:** `lib/bluey.dart` adds exports for new files. Public API unchanged — consumers get the same types.

### Impact

No behavior change. Imports within `bluey_connection.dart` and `bluey_server.dart` update to reference new file locations. All tests pass.

---

## Step 4: Introduce `ScanResult` Value Object

### Problem

`scan()` returns `Stream<Device>`, conflating a transient observation (advertisement + signal strength at a moment) with a persistent entity identity. The `Device` doc says "value object" but uses entity equality.

### Changes

**`Device` slims down** to pure entity — stable identity only:
- `id` (UUID) — unique device identifier
- `address` (String) — platform connection handle
- `name` (String?) — advertised name
- `copyWith` covers only `name`
- Equality by `id` only (entity semantics)
- Doc comment updated to "entity"

**New `ScanResult` value object** (`scan_result.dart`):
- `device` (Device) — the discovered device
- `rssi` (int) — signal strength at observation time
- `advertisement` (Advertisement) — broadcast data at observation time
- `lastSeen` (DateTime) — timestamp of observation
- Equality by all fields (value semantics)
- `@immutable`

**`Bluey` changes:**
- Internal `_mapDevice()` now returns `ScanResult` wrapping a `Device`
- `scan()` return type changes to `Stream<ScanResult>` (temporary — Step 5 moves scanning to `Scanner`)
- `connect()` parameter type remains `Device` — callers pass `scanResult.device`
- `bondedDevices` returns `List<Device>` — bonded devices have no scan observation data

**`DeviceDiscoveredEvent`** already carries `deviceId`, `name`, `rssi` — no change needed.

### Impact

API change: `scan()` return type changes from `Stream<Device>` to `Stream<ScanResult>`. Tests that consume scan results update to unwrap `.device` where needed. The `Device` test suite simplifies (fewer fields to test).

---

## Step 5: Introduce `Scanner` Aggregate

### Problem

The Discovery bounded context has no aggregate root. Scanning is two disconnected methods on `Bluey` (`scan()`, `stopScan()`), unlike Server which has a proper aggregate pattern.

### Changes

**New `Scanner` abstract interface** (`scanner.dart`):
```dart
abstract class Scanner {
  bool get isScanning;
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout});
  Future<void> stop();
  Future<void> dispose();
}
```

**New `BlueyScanner` internal implementation** (`bluey_scanner.dart`):
- Wraps platform `scan()` / `stopScan()` calls
- Maps `PlatformDevice` to `ScanResult`
- Emits scan events (`ScanStartedEvent`, `DeviceDiscoveredEvent`, `ScanStoppedEvent`) via the event bus
- Manages scan lifecycle (idempotent stop, resource cleanup on dispose)

**`Bluey` changes:**
- Remove `scan()` and `stopScan()` methods
- Add `Scanner scanner()` factory method (parallels `Server? server()`)
- Non-nullable return — scanning is always available, unlike Server which depends on platform peripheral support

**Usage pattern becomes:**
```dart
final scanner = bluey.scanner();
await for (final result in scanner.scan(timeout: Duration(seconds: 10))) {
  print('Found: ${result.device.name}');
}
scanner.dispose();
```

### Impact

API change: consumers obtain a `Scanner` from `Bluey` instead of calling `scan()` directly. All scan-related tests update. The `Bluey` class shrinks — scanning logic moves to `BlueyScanner`.

---

## Step 6: Bounded Context Directory Structure

### Problem

All 16+ source files live in a flat `src/` directory. Bounded context boundaries are enforced only by convention, not structure.

### Target Structure

```
lib/src/
├── shared/
│   ├── uuid.dart
│   ├── manufacturer_data.dart
│   ├── characteristic_properties.dart
│   └── exceptions.dart
├── discovery/
│   ├── scanner.dart
│   ├── bluey_scanner.dart
│   ├── device.dart
│   ├── advertisement.dart
│   ├── scan_result.dart
│   └── scan.dart
├── connection/
│   ├── connection.dart
│   ├── bluey_connection.dart
│   └── connection_state.dart
├── gatt_client/
│   ├── gatt.dart
│   └── well_known_uuids.dart
├── gatt_server/
│   ├── server.dart
│   ├── bluey_server.dart
│   ├── hosted_gatt.dart
│   └── gatt_request.dart
├── platform/
│   └── bluetooth_state.dart
├── events.dart
├── event_bus.dart
├── lifecycle.dart
└── bluey.dart
```

### Placement Rationale

| Location | Why |
|----------|-----|
| `shared/` | Types used across multiple bounded contexts: `UUID`, `ManufacturerData`, `CharacteristicProperties`, `exceptions` |
| `discovery/` | Everything related to scanning and device discovery |
| `connection/` | Connection lifecycle, state, bonding, PHY, parameters |
| `gatt_client/` | Remote GATT types for reading/writing characteristics on connected devices |
| `gatt_server/` | Server interface, hosted GATT types, request/response handling |
| `platform/` | `BluetoothState` enum (extracted from `bluey.dart` where it's currently defined inline) |
| `src/` root | Cross-cutting concerns: `events.dart`, `event_bus.dart`, `lifecycle.dart`, `bluey.dart` (application facade) |

### Barrel File

`lib/bluey.dart` updates all export paths. Public API surface unchanged — consumers import `package:bluey/bluey.dart` and get the same types.

### Impact

No behavior change. All internal imports update. All tests pass. Git history for individual files is trackable via `git log --follow`.

---

## Testing Strategy

All changes are executed under TDD discipline as required by CLAUDE.md:

- **Steps 1-3** (mechanical refactors): Existing 424 tests serve as the safety net. Run full suite after each step to confirm zero regressions. No new tests needed — behavior is unchanged.
- **Step 4** (`ScanResult`): Write tests for `ScanResult` value equality and construction first (Red), then implement. Update existing scan-related tests to use `ScanResult`. Update `Device` tests to remove `rssi`/`advertisement`/`lastSeen` assertions.
- **Step 5** (`Scanner`): Write `Scanner` contract tests first (Red) — scanning, stopping, idempotent stop, dispose. Implement `BlueyScanner` (Green). Update integration tests that use `bluey.scan()` to use `bluey.scanner().scan()`.
- **Step 6** (directory moves): Run full suite to confirm imports resolve correctly. No new tests needed.

Coverage targets remain: 90% domain layer, 80% overall.

---

## Out of Scope

- Changes to `bluey_platform_interface`, `bluey_android`, or `bluey_ios` packages
- Changes to the example app
- New features or capabilities
- Test infrastructure changes beyond what's needed for new types (`ScanResult`, `Scanner`)
