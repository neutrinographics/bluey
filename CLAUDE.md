# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Mandatory Development Practices

**All code must follow DDD, Clean Architecture, and TDD (Red, Green, Refactor).** These are non-negotiable requirements.

- **TDD cycle**: Write a failing test first (Red), implement minimum code to pass (Green), then improve (Refactor). No production code without a failing test.
- **DDD**: Use ubiquitous language consistently (see Ubiquitous Language table below). Respect bounded context boundaries. Value objects are immutable with equality by value.
- **Clean Architecture**: Dependencies point inward only. Domain layer has zero framework dependencies. Platform implementations are swappable.
- **Coverage floor**: 90% of the lines of the `bluey` package, held by CI's coverage gate, which also fails on a file with code that no test loads (`docs/ARCHITECTURE.md` §10).
- **Comments explain why, never how** (Clean Code). A doc comment on a class or function says why a reader would use it and what non-obvious consequence to expect; the code itself shows how it works. Avoid inline comments: if a line needs explaining, extract it into a well-named function and document that function instead. Reserve inline comments for a genuinely special line (a platform quirk, a spec constraint). Delete commented-out code, journal comments, and comments that restate the code.

### Design review before execution

Every spec and every plan carries a "Design review (cohesion, coupling, DDD, Clean Architecture)" section that ends `Verdict: ready.` before any task starts: each unit's single responsibility, each dependency and its direction, the bounded context and its language, and the layer each file lands in. A claim that names an existing class is checked against that class's source before the verdict is written. A finding is fixed in the document before any task starts.

## Project Overview

Bluey is a Flutter BLE (Bluetooth Low Energy) library organized as a Dart workspace monorepo with 5 packages:

```
bluey/                         Main library - domain models, public API, tests
bluey_platform_interface/      Abstract BlueyPlatform base class, DTOs, capabilities
bluey_android/                 Android implementation (Kotlin + Pigeon)
bluey_ios/                     iOS implementation (Swift + Pigeon)
bluey/example/                 Demo app with scanner, connection, GATT, server features
bluey_guards/                  The guards the build runs (architecture rules, the public API dump, the CI gate tools), dev-only and never published
```

## Build & Test Commands

```bash
# Run the Dart tests in a package (all five have Dart suites; bluey_guards' runs with `dart test`, below)
cd bluey && flutter test
cd bluey_platform_interface && flutter test
cd bluey_android && flutter test
cd bluey_ios && flutter test
cd bluey/example && flutter test       # the example app, the one consumer of the public API here
cd bluey_ios/example && flutter test

# Run the Android native (Kotlin/JVM) unit tests — standalone Gradle.
# Needs the Flutter SDK path: set FLUTTER_ROOT or bluey_android/android/local.properties (flutter.sdk=...).
cd bluey_android/android && FLUTTER_ROOT="$(dirname "$(dirname "$(which flutter)")")" ./gradlew test

# Run the iOS native (XCTest) unit tests — RunnerTests target via xcodebuild (macOS + Xcode + CocoaPods).
cd bluey_ios/example && flutter build ios --config-only && (cd ios && pod install)
cd bluey_ios/example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16'   # substitute an available sim: xcrun simctl list devices

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

# Formatting, as CI's Analyze job holds it: the guards and every root of new code that exists
dart format --output=none --set-exit-if-changed bluey_guards */test/architecture */test/known_defects bluey/lib/src/shared/domain

# The guards' own tests
cd bluey_guards && dart test

# The architecture rules; each package keeps its lists in test/architecture/known_violations.dart
cd bluey && flutter test test/architecture

# No list grew since the branch left main (CI compares with the pull request's base, and runs it in every package)
cd bluey && dart run test/architecture/list_growth.dart origin/main test/architecture/known_violations.dart test/known_defects/roster.dart

# The public API dump: check it, or rewrite it after a change that was meant
cd bluey && dart run bluey_guards:public_api lib/bluey.dart api/bluey.api
cd bluey && dart run bluey_guards:public_api lib/bluey.dart api/bluey.api --write

# The known defects, which are expected to fail; each package's roster in test/known_defects/roster.dart names them (docs/ARCHITECTURE.md)
cd bluey && flutter test test/known_defects --run-skipped --tags known-defect

# The coverage floor
cd bluey && flutter test --coverage && dart run bluey_guards:coverage_gate coverage/lcov.info 90 lib

# Once per checkout: create the Gradle wrapper, which is not committed
cd bluey_android/android && gradle wrapper --gradle-version 8.14

# Generate Pigeon bindings (from package root)
cd bluey_android && dart run pigeon --input pigeons/messages.dart
cd bluey_ios && dart run pigeon --input pigeons/messages.dart

# Run example app
cd bluey/example && flutter run
```

## Architecture

`docs/ARCHITECTURE.md` is the authoritative guide; this section is its short version. New code goes into the target layout (`lib/src/{api, features/<context>/{domain,application,infrastructure}, shared}`), the old folders only shrink, failures below `api/` are values (`Either<Failure, T>`), and the architecture test holds all of it against lists that never grow.

### Clean Architecture Layers

The packages, from the consumer down. Inside `bluey`, the layers (`domain`, `application`, `infrastructure`) are those of each `features/<context>/` and of `shared/`, as `docs/ARCHITECTURE.md` §3 lays out.

```
Consumer              ← Example app / consumer code
Library               ← bluey package (UUID, Device, Advertisement, Connection, Server, exceptions, events)
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

- **No singletons** - explicit `await Bluey.create()` instance with lifecycle via `dispose()`
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
- Bootstrap caveat: events emitted during `Bluey.create()` construction are dropped if no listener has subscribed yet (broadcast stream semantics). Subscribe immediately after `create()` resolves to start capturing events.

### Ubiquitous Language

The domain layer uses bounded-context-aligned vocabulary; the platform-interface layer uses BLE-spec-aligned vocabulary (`Central`, `Peripheral`, `PlatformDevice`). The seam between them translates intentionally — `PlatformCentral` becomes `Client` inside the GATT-Server context, `PlatformDevice` becomes `Device` inside the Discovery context. Each bounded context is internally consistent; the translation only happens at the Domain ↔ Platform-Interface boundary.

#### Glossary

| Term | Bounded context | Definition |
|------|-----------------|------------|
| **Device** | Discovery | A BLE peripheral discovered via scanning. The local role is implicitly central. Wraps `PlatformDevice` at the platform seam. |
| **Connection** | Connection | An established GATT link to a remote `Device`. The local role is GATT client. |
| **Server** | GATT Server | The peripheral role hosted by *this* device. The local role is GATT server. |
| **Client** | GATT Server | A GATT central that has connected to our local `Server`. Wraps `PlatformCentral` at the platform seam. |
| **Peer** (`BlueyPeer`) | Peer | A `Device` (or, server-side, a `Client`) that speaks the Bluey lifecycle protocol. Promotion to peer happens only after control-service discovery; raw connections are protocol-free. |
| **PeerConnection** | Peer | A `Connection` wrapped with a stable `ServerId` and the lifecycle-protocol disconnect path. Composition over inheritance — `peer.connection` exposes the raw GATT surface. |
| **ServerId** | Peer | The stable identity advertised through the lifecycle control service. Survives MAC randomization on Android and CBPeripheral identifier rotation on iOS. |
| **Central / Peripheral** | (BLE-spec, platform-interface only) | The wire-level BLE roles. Surfaces only in `bluey_platform_interface` types (`PlatformCentral`, `centralConnections`, etc.). The domain layer translates these to `Client` / `Server` at the seam. |
| **AttributeHandle** | Connection / GATT Client | Opaque platform-assigned identifier for a service / characteristic / descriptor. Valid only within one connection; invalidated on disconnect or Service Changed. |

#### Quick reference (use / avoid)

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

When writing tests, use `FakeBlueyPlatform` (not mocks) and the helpers from `test_helpers.dart`. Read `docs/testing-conventions.md` first — it records the simulate-time rule, the fakeAsync broadcast-cancel trap, and the fake's scenario-simulation surface (fault rules, latency, `FakeBleLink`).

## Key Files

- `docs/ARCHITECTURE.md` - the authoritative guide to the structure, the rules the build holds and the gates; this file is its short version
- `bluey/test/architecture/known_violations.dart` - what the architecture rules find today, as lists that only shrink (each package has one)
- `bluey/api/bluey.api` - the committed public API dump; a change to it is reviewed as an API change
- `.github/workflows/ci.yml` - the gates every pull request runs (XCTest runs from `ios.yml`)
- `bluey_android/pigeons/messages.dart` - Pigeon API definition for Android (generates `Messages.g.kt` + `messages.g.dart`)
- `bluey_ios/pigeons/messages.dart` - Pigeon API definition for iOS (generates `Messages.g.swift` + `messages.g.dart`)
- `docs/roadmap.md` - the development roadmap: source of truth for what to work on next (priority, status, ordering, grouped by bounded context). Start here for outstanding work.
- `docs/backlog/` - one file per known bug, no-op stub, and unimplemented feature (the detailed technical record behind each roadmap item); `docs/backlog/README.md` documents the entry schema and ID-allocation conventions
- `docs/old/` - historical references (`BUGS_ANALYSIS.md`, `ANDROID_IMPLEMENTATION_COMPARISON.md`, `IOS_IMPLEMENTATION_COMPARISON.md`, all dated January 2026 and superseded by `docs/backlog/`)
- `bluey/docs/cross-platform-quirks.md` - consumer-facing behavioral differences between Android and iOS that bluey cannot hide (e.g. iOS `CBPeer` shared-link trap on bidirectional discovery). Read before designing apps that scan and advertise simultaneously.
- `bluey_android/ANDROID_BLE_NOTES.md` - Android BLE gotchas for platform-package maintainers (threading, lifecycle, force-kill behavior)
- `bluey_ios/IOS_BLE_NOTES.md` - iOS BLE quirks for platform-package maintainers (CBPeripheralManager workarounds, etc.)
