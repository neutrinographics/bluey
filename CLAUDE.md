# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Mandatory Development Practices

**All code must follow DDD, Clean Architecture, and TDD (Red, Green, Refactor).** These are non-negotiable requirements.

- **TDD cycle**: Write a failing test first (Red), implement minimum code to pass (Green), then improve (Refactor). No production code without a failing test.
- **DDD**: Use ubiquitous language consistently (see Ubiquitous Language table below). Respect bounded context boundaries. Value objects are immutable with equality by value.
- **Clean Architecture**: Dependencies point inward only. Domain layer has zero framework dependencies. Platform implementations are swappable.
- **Coverage targets**: 90% minimum for domain layer, 80% overall.

## Project Overview

Bluey is a Flutter BLE (Bluetooth Low Energy) library organized as a Dart workspace monorepo with 4 packages:

```
bluey/                         Main library - domain models, public API, tests (543 tests)
bluey_platform_interface/      Abstract BlueyPlatform base class, DTOs, capabilities
bluey_android/                 Android implementation (Kotlin + Pigeon)
bluey_ios/                     iOS implementation (Swift + Pigeon)
bluey/example/                 Demo app with scanner, connection, GATT, server features
```

## Build & Test Commands

```bash
# Run all tests in a package
cd bluey && flutter test
cd bluey_platform_interface && flutter test
cd bluey_android && flutter test

# Run a single test file
cd bluey && flutter test test/uuid_test.dart

# Run tests matching a name pattern
cd bluey && flutter test --name "UUID"

# Run integration tests only
cd bluey && flutter test test/integration/

# Run with coverage
cd bluey && flutter test --coverage

# Analyze (lint)
flutter analyze

# Generate Pigeon bindings (from package root)
cd bluey_android && dart run pigeon --input pigeons/messages.dart
cd bluey_ios && dart run pigeon --input pigeons/messages.dart

# Run example app
cd bluey/example && flutter run
```

## Architecture

### Clean Architecture Layers

```
Application Layer     ← Example app / consumer code
Domain Layer          ← bluey package (UUID, Device, Advertisement, Connection, Server, exceptions, events)
Platform Interface    ← bluey_platform_interface (BlueyPlatform abstract class, platform DTOs)
Platform Impl         ← bluey_android, bluey_ios (Pigeon bindings + native Kotlin/Swift)
```

### Bounded Contexts

1. **Discovery** - Scanning, device discovery, advertisement data
2. **Connection** - Device connections, bonding, PHY, connection parameters
3. **GATT Client** - Service/characteristic read/write/notify, descriptors, MTU
4. **GATT Server** - Peripheral role, advertising, request/response handling
5. **Platform** - Bluetooth state, permissions, capabilities
6. **Peer** - Stable peer identity on top of the lifecycle protocol. `BlueyPeer`, `ServerId`, `bluey.peer()`, `bluey.discoverPeers()`. The peer module owns the client-side protocol layer — raw `BlueyConnection` is protocol-free.

### Key Design Decisions

- **No singletons** - explicit `Bluey()` instance with lifecycle via `dispose()`
- **Streams over callbacks** - all async events use Dart Streams
- **Immutable data, mutable connections** - Device/Advertisement are snapshots; Connection state is observable
- **Pigeon for platform channels** - type-safe generated bindings, no manual MethodChannel code
- **Sealed classes** for exceptions and domain events (exhaustive pattern matching)

### Handle-based attribute identity (post-I088)

- Every GATT attribute (service / characteristic / descriptor) is identified on the wire by an opaque, platform-assigned `int handle`. UUIDs remain for navigation (`connection.service(uuid).characteristic(uuid)`) and display.
- Android characteristic handles come from `BluetoothGattCharacteristic.getInstanceId()`. Android descriptor handles, iOS characteristic handles, and iOS descriptor handles are minted client-side via a per-device monotonic counter (because `BluetoothGattDescriptor.getInstanceId()` is `@hide` in AOSP and CoreBluetooth has no equivalent).
- Handles are valid only within a single connection; invalidated on disconnect or Service Changed. Stale-handle ops surface as `AttributeHandleInvalidatedException`.
- Dart-side wrapper: `AttributeHandle` value object (`value > 0`, equality-by-value). Wire-level int is unwrapped only at the Pigeon boundary.
- User-facing ergonomic path: `connection.service(uuid).characteristic(uuid).read()`. Singular accessors throw `AmbiguousAttributeException(uuid, count)` on duplicate-UUID matches; the plural accessors `service.characteristics({UUID? uuid})` and `characteristic.descriptors({UUID? uuid})` are the disambiguation escape hatches and also expose `.handle` for direct addressing.

See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design.

### Platform-tagged Connection extensions (post-I089/I066)

- `Connection` declares only cross-platform members (state, services, mtu, rssi, disconnect).
- Android-specific features (bond, PHY, connection parameters, connection priority, refreshGattCache) live on `connection.android` of type `AndroidConnectionExtensions?`. iOS-specific extensions reserved on `connection.ios` of type `IosConnectionExtensions?` (currently empty).
- The asymmetry is type-visible at every call site: `connection.android?.bond()` evaluates to a no-op (null) on iOS and dispatches on Android.

### Peer composition (post-I300)

- `Bluey.connect(device)` returns a raw `Connection` — no peer-protocol attempt.
- `Bluey.connectAsPeer(device)` returns `PeerConnection` (throws `NotABlueyPeerException` if the device doesn't expose the lifecycle control service).
- `Bluey.tryUpgrade(connection)` returns `PeerConnection?` for the rare post-connect upgrade path.
- `PeerConnection` is a composition wrapper: it holds a `Connection` (use `peer.connection` for raw GATT) plus a `serverId` and the lifecycle-protocol disconnect path.

### Structured logging (post-I307)

- `bluey.logEvents` is a broadcast `Stream<BlueyLogEvent>` covering domain-layer **and** native (Android + iOS) events in arrival order — single subscription point for the whole stack.
- `bluey.setLogLevel(BlueyLogLevel level)` filters Dart-side and pushes the filter down to the native side, so no Pigeon traffic is incurred for filtered events. Default level is `info`.
- Levels: `trace`, `debug`, `info`, `warn`, `error`.
- Context naming convention: `bluey`, `bluey.connection`, `bluey.connection.lifecycle`, `bluey.server`, `bluey.server.lifecycle`, `bluey.peer`, `bluey.peer.discovery`, `bluey.android.{plugin,gatt_server,gatt_queue,advertiser}`, `bluey.ios.{plugin,central,peripheral,op_slot}`.
- Native logs **also** tee to `Logcat` (Android) and `os_log` (iOS) for native-side debugging — the Dart bridge is additive, not exclusive.
- Bootstrap caveat: events emitted during `Bluey()` construction are dropped if no listener has subscribed yet (broadcast stream semantics).

### Ubiquitous Language (avoid platform-specific terms)

| Use | Avoid |
|-----|-------|
| `Bluey`, `Scanner` | CentralManager |
| `Server` | PeripheralManager |
| `Device` | CBPeripheral, BluetoothDevice |
| `Connection` | (implicit GATT handle) |
| `ServerId` | server UUID, peer ID |
| `BlueyPeer` | peer device (in Bluey-specific contexts) |
| `AttributeHandle` | raw int, "instance ID" |
| `PeerConnection` | "upgraded connection", "peer connection wrapper" |
| `AndroidConnectionExtensions` | "platform extension methods" |

## Testing

Tests live in each package's `test/` directory. The `bluey` package has the most comprehensive suite:

- **Unit tests**: `bluey/test/*.dart` - one per domain class
- **Integration tests**: `bluey/test/integration/` - cross-concern scenarios
- **Fakes**: `bluey/test/fakes/fake_platform.dart` - in-memory `BlueyPlatform` implementation that simulates both central and peripheral roles
- **Test helpers**: `bluey/test/fakes/test_helpers.dart` - common UUIDs (`TestUuids`), device IDs (`TestDeviceIds`), property builders (`TestProperties`)

When writing tests, use `FakeBlueyPlatform` (not mocks) and the helpers from `test_helpers.dart`.

## Key Files

- `bluey_android/pigeons/messages.dart` - Pigeon API definition for Android (generates `Messages.g.kt` + `messages.g.dart`)
- `bluey_ios/pigeons/messages.dart` - Pigeon API definition for iOS (generates `Messages.g.swift` + `messages.g.dart`)
- `docs/backlog/README.md` - living index of known bugs, no-op stubs, and unimplemented features; start here for outstanding work
- `docs/old/` - historical references (`BUGS_ANALYSIS.md`, `ANDROID_IMPLEMENTATION_COMPARISON.md`, `IOS_IMPLEMENTATION_COMPARISON.md`, all dated January 2026 and superseded by `docs/backlog/`)
- `bluey_android/ANDROID_BLE_NOTES.md` - Android BLE gotchas (threading, lifecycle, force-kill behavior)
- `bluey_ios/IOS_BLE_NOTES.md` - iOS BLE quirks and operational notes
