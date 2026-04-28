# Bundled Architectural Rewrite — GATT Handle Identity + Connection Composition

**Bundle:** I088 (Pigeon GATT schema rewrite) + I089/I066 (platform-tagged Connection extensions) + I300 (PeerConnection composition) + I301 (value objects for ConnectionParameters / Mtu).

**Status:** design draft, awaiting review. No code written.

## Problem

Four open backlog items touch the `Connection` aggregate and the GATT wire schema. Fixing them piecemeal would mean editing the same files three or four times, each commit invalidating the next. They are bundled here as one coherent breaking-change release.

- **I088 (critical)** — every GATT operation routes by `(deviceId, characteristicUuid)` or `(deviceId, descriptorUuid)`. UUIDs are not unique within a peripheral's GATT database. On any device with two services that expose a characteristic of the same UUID — or, *much* more commonly, any device that has more than one notifyable characteristic (each with its own CCCD `0x2902` descriptor) — operations are non-deterministically routed to the wrong attribute. The CCCD case alone makes this a critical correctness bug on essentially every multi-notify peripheral.
- **I089/I066 (high)** — the cross-platform `Connection` interface declares ten platform-asymmetric methods (bond, PHY, connection-parameters) as if they were portable. iOS cannot satisfy them at all (Apple wontfix per I200); Android currently has them stubbed (I035 Stage B). The interface lies about what the library can do.
- **I300 (high)** — `BlueyConnection` carries `isBlueyServer` / `serverId` and an `upgrade()` method that mutates a "raw GATT" connection into a "Bluey peer" connection in place. The Connection aggregate root is therefore not stable across its lifetime, and Connection knows about Peer-context types (inverting the bounded-context dependency).
- **I301 (low)** — `ConnectionParameters.intervalMs/latency/timeoutMs` and `Connection.mtu` are primitives. Their BLE-spec ranges and cross-field invariants are documented in doc-comments only and validated nowhere.

The four are bundled because:
- I088 changes every method on the GATT-op surface of `Connection`. So does I089. Doing them separately means rewriting `BlueyConnection` twice.
- I300 removes `isBlueyServer` / `serverId` from `Connection`. Doing it before I089 means rewriting Connection's interface in two passes.
- I301 introduces `Mtu` and `ConnectionParameters` value objects that show up in Connection's signature — a third pass at the same interface if separate.

A single coherent rewrite, sequenced and reviewable phase by phase, is cleaner.

## Goal

Three architectural shifts, plus a value-object pass:

1. **Handle-based attribute identity (I088).** Every GATT attribute (service, characteristic, descriptor) gets an opaque, platform-assigned `int handle` at discovery time. Pigeon GATT methods route by handle, not UUID. UUIDs are still carried for display, equality, and navigation (`connection.service(uuid).characteristic(uuid)`), but routing identity is the handle.
2. **Cross-platform `Connection` shrinks to the intersection (I089/I066).** Bonding, PHY, and connection-parameters move to `connection.android: AndroidConnectionExtensions?`. iOS gets a typed-null `connection.ios: IosConnectionExtensions?` (currently empty, reserved). Capabilities matrix becomes load-bearing — it's what gates whether `connection.android` is non-null.
3. **Peer-protocol concerns extracted via composition (I300).** `Connection.upgrade()` is removed. `Bluey.connect()` returns a raw `Connection`, no upgrade attempt. New `Bluey.connectAsPeer(device)` returns `Future<PeerConnection>` (throws `NotABlueyPeerException` on non-peer). `PeerConnection` *wraps* a `Connection` (composition), exposing `serverId`, `sendDisconnectCommand()`, and a service tree that hides the lifecycle control service.
4. **Value objects (I301).** `Mtu`, `ConnectionInterval`, `PeripheralLatency`, `SupervisionTimeout`, plus `AttributeHandle` (the Dart-side wrapper around a wire-level int handle from shift 1). Validation at construction; cross-field invariant on `ConnectionParameters` (timeout > (1+latency)·interval).

### In scope

**Pigeon schema rewrite (both platforms):**
- `CharacteristicDto`, `DescriptorDto` gain `int handle`.
- `ReadRequestDto`, `WriteRequestDto` gain `int characteristicHandle`.
- `readCharacteristic`, `writeCharacteristic`, `setNotification`, `notifyCharacteristic`, `notifyCharacteristicTo` switch from `String characteristicUuid` to `int characteristicHandle`.
- `readDescriptor`, `writeDescriptor` switch from `String descriptorUuid` to `int descriptorHandle`.
- DTOs keep their `String uuid` fields for display.
- Wire type stays `int` (Pigeon-portable). The Dart domain layer wraps in `AttributeHandle` immediately after Pigeon decode and unwraps just before encode; native sides operate on raw int. The wrapper type does not cross the wire.

**Android handle source:**
- `BluetoothGattCharacteristic.getInstanceId()` and `BluetoothGattDescriptor.getInstanceId()` for client-side.
- For server-side (`GattServer.kt`), the same `getInstanceId()` works once a characteristic has been added to a service.
- New per-device maps in `ConnectionManager.kt`: `characteristicByHandle: MutableMap<String, MutableMap<Int, BluetoothGattCharacteristic>>` and `descriptorByHandle: MutableMap<String, MutableMap<Int, BluetoothGattDescriptor>>`. Populated in `onServicesDiscovered`, cleared in `STATE_DISCONNECTED` and on Service Changed.

**iOS handle source:**
- A monotonic int counter minted at `peripheral(_, didDiscoverCharacteristicsFor:)` and `peripheral(_, didDiscoverDescriptorsFor:)`.
- New per-device maps in `CentralManagerImpl.swift`: `characteristicByHandle: [String: [Int: CBCharacteristic]]`, `descriptorByHandle: [String: [Int: CBDescriptor]]`, `nextHandle: [String: Int]`. Cleared on disconnect and on `peripheral(_, didModifyServices:)`.
- Server-side in `PeripheralManagerImpl.swift`: `characteristicByHandle: [Int: CBMutableCharacteristic]`, minted at `addService`.

**Handle lifetime invariants:**
1. **Connection scope.** A handle is valid only within the connection that issued it. Disconnect invalidates all handles for that device.
2. **Service Changed scope.** Handles are invalidated on Service Changed (Android `onServiceChanged`; iOS `peripheral(_, didModifyServices:)`). Dart-side `BlueyConnection._handleServiceChange` clears `_cachedServices` and fails in-flight ops with `AttributeHandleInvalidatedException`. Subscribers re-call `connection.services()` to acquire fresh handles.
3. **Out-of-band use.** Passing a handle from connection A to connection B is a programmer error. Platform side rejects unknown handles with a typed `AttributeNotFoundException`.

**Connection interface refactor:**
- New abstract `AndroidConnectionExtensions` interface (bond, PHY, connection-parameters, connection-priority, refreshGattCache).
- New abstract `IosConnectionExtensions` interface (empty; reserved).
- `Connection.android` returns the extension instance only when `Capabilities.canBond || canRequestPhy || canRequestConnectionParameters`. Otherwise null.
- `Connection.mtu: Mtu` (was `int`); `Connection.requestMtu(Mtu)` (was `int`).

**Peer composition:**
- New `PeerConnection` abstract class: `connection: Connection`, `serverId: ServerId`, `sendDisconnectCommand()`, plus the service-tree view that hides the control service.
- New `_BlueyPeerConnection` impl that holds the `LifecycleClient` privately.
- New `PeerRemoteServiceView` (or equivalent) that wraps `Connection.services()` and excludes the lifecycle control service for peer-protocol consumers.
- `Bluey.connect(device): Future<Connection>` returns raw — no upgrade attempt.
- New `Bluey.connectAsPeer(device): Future<PeerConnection>` (throws `NotABlueyPeerException` on miss).
- New `Bluey.tryUpgrade(Connection): Future<PeerConnection?>` for the rare post-connect upgrade path (e.g. Service Changed reveals control service after the initial connect).
- `BlueyPeer.connect()` returns `Future<PeerConnection>` (was `Future<Connection>`).

**Value objects:**
- `AttributeHandle(int value)` — Dart-side wrapper for the platform-assigned handle. Validates `value > 0`. Equality by value. Unwrapped to `int` only at the Pigeon boundary.
- `Mtu(int value, {required Capabilities capabilities})`. Construction validates `23 ≤ value ≤ capabilities.maxMtu`. `Mtu.fromPlatform(int)` factory bypasses validation for platform reads (the platform is authoritative).
- `ConnectionInterval(double milliseconds)` — 7.5–4000 ms.
- `PeripheralLatency(int events)` — 0–499.
- `SupervisionTimeout(int milliseconds)` — 100–32000 ms.
- `ConnectionParameters({required ConnectionInterval interval, required PeripheralLatency latency, required SupervisionTimeout timeout})`. Construction enforces `timeout.milliseconds > (1 + latency.events) * interval.milliseconds`.

**Navigation API extensions (the "support both" answer to the same-UUID-in-one-service edge case):**
- `RemoteCharacteristic.handle: AttributeHandle` — getter exposing the handle for disambiguation.
- `RemoteDescriptor.handle: AttributeHandle` — same.
- `RemoteService.characteristics({UUID? uuid}): List<RemoteCharacteristic>` — plural accessor returning all characteristics matching the optional UUID filter (or all if no filter).
- `RemoteCharacteristic.descriptors({UUID? uuid}): List<RemoteDescriptor>` — same shape for descriptors.
- **The existing singular accessors throw on ambiguity instead of returning the first match.** `Connection.service(uuid)`, `RemoteService.characteristic(uuid)`, and `RemoteCharacteristic.descriptor(uuid)` now have semantics: "exactly one match required." On zero matches → existing `*NotFoundException`. On two-or-more matches → new `AmbiguousAttributeException(uuid, matchCount)` with a message pointing the user at the plural accessor. This eliminates silent wrong-routing on duplicate-UUID peripherals; the failure mode becomes loud and helpful instead of silent and harmful.

**FakeBlueyPlatform:**
- Switch internal storage to handle-keyed; mint handles at fake `discoverServices`. Helper `fake.handleFor(deviceId, charUuid)` for tests that prefer to express their setup in UUID terms.
- Parameterize the fake's capabilities so existing bonding tests can run with Android-flavored capabilities (relates to I069, but only the minimum needed by this rewrite).

### Out of scope

- **No migration guide.** Confirmed: only the example app uses Bluey. Example-app updates stand in for migration docs; a CHANGELOG note suffices.
- **No new GATT op semantics.** `read`/`write`/`notify`/`setNotification` semantics are preserved; only the routing identity changes.
- **No threading-model change.** The main-thread invariant from I098 holds. Handle-table mutations happen on main, just like every other map mutation in `ConnectionManager`.
- **No bond/PHY/conn-param plumbing.** I035 Stage B remains a separate item. We only relocate the existing surface from `Connection` to `AndroidConnectionExtensions`; the underlying stub-or-real implementations are unchanged.
- **No CoreBluetooth API changes.** iOS handle table is a new internal layer; CB callbacks are unchanged in shape.
- **No Capabilities matrix expansion (I053).** We only need `Capabilities.maxMtu` to be consulted by `Mtu` (already there) and the three booleans for the `connection.android` gate (already there).
- **No `removeService` race fixes** (I086 iOS side); separate Tier-4 item.

## Architecture

### Handle model — wire-level identity

Every attribute has an opaque `int handle` assigned by the platform side at discovery time. Handles are returned to Dart in service-discovery DTOs. Subsequent GATT ops carry the handle, not the UUID. UUIDs are still carried in DTOs for display, equality with user-supplied UUIDs at navigation time (`connection.service(uuid)`), and logging — but **identity for routing is the handle**.

**Layering:** the wire type is `int` (Pigeon-portable). The Dart domain layer wraps it in `AttributeHandle` (a value object with `value > 0` validation and equality-by-value) immediately on decode and unwraps it only at the Pigeon boundary on the way out. Native code (Kotlin / Swift) operates on raw int; the wrapper exists purely on the Dart side to prevent accidental misuse (e.g. passing a deviceId int as a handle).

### Android handle source

`BluetoothGattCharacteristic.getInstanceId()` and `BluetoothGattDescriptor.getInstanceId()` return implementation-defined ints that are unique within a connection and stable for its lifetime. They're invalidated on disconnect (the `BluetoothGattCharacteristic` references themselves become unusable). On Service Changed, the OS calls `onServiceChanged`; we re-discover and new instance IDs are issued.

For Android-server-side hosted attributes, the same `getInstanceId()` works after the characteristic has been added to a service (`BluetoothGattServer.addService`). The platform assigns the ID at add-time.

The handle table in `ConnectionManager.kt`:

```kotlin
private val characteristicByHandle:
    MutableMap<String /*deviceId*/, MutableMap<Int /*instanceId*/, BluetoothGattCharacteristic>>
    = mutableMapOf()
private val descriptorByHandle:
    MutableMap<String, MutableMap<Int, BluetoothGattDescriptor>>
    = mutableMapOf()
```

(No service-handle map needed — Android characteristic ops take a `BluetoothGattCharacteristic` reference directly, which already carries its parent service.)

Populated in `onServicesDiscovered` by walking `gatt.services` and calling `getInstanceId()` on each characteristic and descriptor; cleared in the `STATE_DISCONNECTED` branch of `onConnectionStateChange` (alongside the existing `connections.remove(deviceId)` cleanup).

### iOS handle source

CoreBluetooth has no native equivalent of `getInstanceId()`. Instead, we use **object identity** (CB returns the same `CBCharacteristic` reference object across all callbacks for a given attribute) plus a counter we mint ourselves to give Dart something portable to address.

The handle allocator in `CentralManagerImpl.swift`:

```swift
private var characteristicByHandle: [String /*deviceId*/: [Int: CBCharacteristic]] = [:]
private var descriptorByHandle: [String: [Int: CBDescriptor]] = [:]
private var nextHandle: [String: Int] = [:]   // per-device counter, starts at 1

private func mintHandle(for deviceId: String) -> Int {
    let h = (nextHandle[deviceId] ?? 0) + 1
    nextHandle[deviceId] = h
    return h
}
```

Discovery wiring:
- `peripheral(_, didDiscoverCharacteristicsFor:)` → for each `CBCharacteristic`, mint a handle and store.
- `peripheral(_, didDiscoverDescriptorsFor:)` → for each `CBDescriptor`, mint a handle and store.

Cleared on:
- `centralManager(_, didDisconnectPeripheral:)` — clear all three maps' `[deviceId]` entries.
- `peripheral(_, didModifyServices:)` — clear all three for that device, then re-discover.

Server-side (`PeripheralManagerImpl.swift`):

```swift
private var characteristicByHandle: [Int: CBMutableCharacteristic] = [:]
private var nextHandle = 1     // module-wide; only one local server
```

Minted in `addService` for each `CBMutableCharacteristic`. Cleared on `removeService` (and full clear on `peripheralManagerDidUpdateState(.poweredOff)` — though that latter fix is its own backlog item I083).

### Service Changed handling

Service Changed is the central tricky case. Both platforms can deliver it any time after `STATE_CONNECTED`.

```
Android: onServiceChanged(gatt) [binder thread]
  → handler.post {
      // Clear handle tables for this device:
      characteristicByHandle.remove(deviceId)
      descriptorByHandle.remove(deviceId)
      // Existing service-rediscovery path runs:
      gatt.discoverServices()
      // (When onServicesDiscovered fires later, maps are repopulated.)
    }
  → Pigeon-side notify Dart of service change.

Dart: BlueyConnection._handleServiceChange()
  → fail in-flight GATT ops with AttributeHandleInvalidatedException
  → _cachedServices = null
  → emit ServiceChangedEvent (existing event path; extended to include the typed exception)

…onServicesDiscovered fires…
  → handler.post {
      // Repopulate characteristicByHandle, descriptorByHandle from gatt.services
      // Emit new ServiceDiscoveryDto with new handles
    }

Dart: subscribers re-call connection.services() and re-resolve handles.
```

iOS analog: `peripheral(_, didModifyServices:)` → clear maps for this device, force a re-discover, repopulate on the new discovery callbacks. `BlueyConnection._handleServiceChange()` runs identically on both platforms.

### `Connection` interface refactor (I089/I066)

Before:

```dart
abstract class Connection {
  // 8 cross-platform members
  // + bond / removeBond / bondState / bondStateChanges
  // + txPhy / rxPhy / phyChanges / requestPhy
  // + connectionParameters / requestConnectionParameters
}
```

After:

```dart
abstract class Connection {
  UUID get deviceId;
  ConnectionState get state;
  Stream<ConnectionState> get stateChanges;
  Mtu get mtu;
  RemoteService service(UUID uuid);
  Future<List<RemoteService>> services({bool cache = false});
  Future<bool> hasService(UUID uuid);
  Future<Mtu> requestMtu(Mtu mtu);
  Future<int> readRssi();
  Future<void> disconnect();

  AndroidConnectionExtensions? get android;
  IosConnectionExtensions? get ios;
}

abstract class AndroidConnectionExtensions {
  BondState get bondState;
  Stream<BondState> get bondStateChanges;
  Future<void> bond();
  Future<void> removeBond();

  Phy get txPhy;
  Phy get rxPhy;
  Stream<({Phy tx, Phy rx})> get phyChanges;
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy});

  ConnectionParameters get connectionParameters;
  Future<void> requestConnectionParameters(ConnectionParameters params);

  Future<void> requestConnectionPriority(ConnectionPriority priority);
  Future<void> refreshGattCache();
}

abstract class IosConnectionExtensions {
  // Currently empty — reserved for future iOS-specific features (e.g. L2CAP).
}
```

Implementation: `BlueyConnection` exposes `android` as an instance of a private `_AndroidConnectionExtensionsImpl` only when the platform reports `Capabilities.canBond || Capabilities.canRequestPhy || Capabilities.canRequestConnectionParameters`. Otherwise null. `_IosConnectionExtensionsImpl` is a singleton placeholder.

The user-facing call shape becomes `connection.android?.bond()`. On iOS, this evaluates to null (no-op). On Android, it dispatches. The asymmetry is type-visible at every call site — review-time.

### Peer composition (I300)

Before:

```dart
final connection = await bluey.connect(device);
if (connection.isBlueyServer) {
  print(connection.serverId);
  // ...
}
```

After:

```dart
// Path A — explicit peer connect (common case):
final peer = await bluey.connectAsPeer(device);
print(peer.serverId);
await peer.sendDisconnectCommand();

// Path B — try to upgrade an existing raw connection (rare):
final connection = await bluey.connect(device);
final peer = await bluey.tryUpgrade(connection);  // PeerConnection?

// Raw GATT navigation, no peer concerns:
final connection = await bluey.connect(device);
final battery = await connection.service(batteryServiceUuid).characteristic(batteryLevelUuid).read();
```

New types:

```dart
abstract class PeerConnection {
  Connection get connection;
  ServerId get serverId;

  /// Service tree with the lifecycle control service hidden.
  Future<List<RemoteService>> services({bool cache = false});
  RemoteService service(UUID uuid);  // throws if uuid is the control service UUID
  Future<bool> hasService(UUID uuid);

  Future<void> sendDisconnectCommand();
  // (other peer-protocol-only ops as they accumulate)
}

class _BlueyPeerConnection implements PeerConnection {
  _BlueyPeerConnection({
    required this.connection,
    required ServerId serverId,
    required LifecycleClient lifecycleClient,
  }) : _serverId = serverId, _lifecycle = lifecycleClient;

  @override final Connection connection;
  final ServerId _serverId;
  final LifecycleClient _lifecycle;

  @override ServerId get serverId => _serverId;

  // services / service / hasService delegate to PeerRemoteServiceView
  // which wraps connection.services() and excludes the control service.
}
```

`Connection.isBlueyServer`, `Connection.serverId`, `BlueyConnection.upgrade()` are removed. The control-service filtering that currently lives at `bluey_connection.dart:368-369` (and parallel sites in `services()`/`hasService()`) moves into `PeerRemoteServiceView`. The raw `Connection.services()` returns the full service tree, including the control service.

`Bluey._upgradeIfBlueyServer` (`bluey.dart:379–447`) is renamed `_tryBuildPeerConnection(Connection raw): Future<PeerConnection?>`. It runs the same control-service detection logic but builds a fresh `_BlueyPeerConnection` instead of mutating the raw connection. Used internally by `connectAsPeer` and `tryUpgrade`.

### Value objects (I301)

```dart
@immutable
class ConnectionInterval {
  final double milliseconds;
  ConnectionInterval(this.milliseconds) {
    if (milliseconds < 7.5 || milliseconds > 4000) {
      throw ArgumentError(
        'connection interval out of spec range (7.5–4000 ms): $milliseconds',
      );
    }
  }
  // equality / hashCode / toString
}

@immutable
class PeripheralLatency {
  final int events;
  PeripheralLatency(this.events) {
    if (events < 0 || events > 499) {
      throw ArgumentError('peripheral latency out of spec range (0–499 events): $events');
    }
  }
}

@immutable
class SupervisionTimeout {
  final int milliseconds;
  SupervisionTimeout(this.milliseconds) {
    if (milliseconds < 100 || milliseconds > 32000) {
      throw ArgumentError(
        'supervision timeout out of spec range (100–32000 ms): $milliseconds',
      );
    }
  }
}

@immutable
class ConnectionParameters {
  final ConnectionInterval interval;
  final PeripheralLatency latency;
  final SupervisionTimeout timeout;

  ConnectionParameters({
    required this.interval,
    required this.latency,
    required this.timeout,
  }) {
    final minTimeout = (1 + latency.events) * interval.milliseconds;
    if (timeout.milliseconds <= minTimeout) {
      throw ArgumentError(
        'supervision timeout must exceed (1 + latency) * interval '
        '($minTimeout ms); got ${timeout.milliseconds} ms',
      );
    }
  }
}

@immutable
class Mtu {
  final int value;
  const Mtu._(this.value);

  factory Mtu(int value, {required Capabilities capabilities}) {
    if (value < 23) {
      throw ArgumentError('MTU must be ≥ 23 (BLE spec minimum): $value');
    }
    if (value > capabilities.maxMtu) {
      throw ArgumentError(
        'MTU $value exceeds platform maximum ${capabilities.maxMtu}',
      );
    }
    return Mtu._(value);
  }

  /// Bypasses validation. Use only for values read back from the platform —
  /// the platform is authoritative about negotiated MTU.
  factory Mtu.fromPlatform(int value) => Mtu._(value);

  /// The minimum guaranteed across all platforms.
  static const Mtu minimum = Mtu._(23);
}
```

`PlatformConnectionParameters` keeps primitive fields (it's a wire DTO; validation is the domain layer's job). A separate mapper file (`connection_parameters_mapper.dart`) handles `toPlatform()` / `fromPlatform()` conversion to keep the value objects free of platform-interface dependencies.

## Components

### Files modified

#### Pigeon schemas

- `bluey_android/pigeons/messages.dart`:
  - L96–100: `DescriptorDto` gains `final int handle`.
  - L103–113: `CharacteristicDto` gains `final int handle`.
  - L253–265: `ReadRequestDto` gains `final int characteristicHandle`.
  - L268–284: `WriteRequestDto` gains `final int characteristicHandle`.
  - L384: `readCharacteristic(deviceId, charHandle)` (was `charUuid`).
  - L388–393: `writeCharacteristic(deviceId, charHandle, value, withResponse)`.
  - L397: `setNotification(deviceId, charHandle, enable)`.
  - L401: `readDescriptor(deviceId, descHandle)`.
  - L405: `writeDescriptor(deviceId, descHandle, value)`.
  - L436: `notifyCharacteristic(charHandle, value)`.
  - L440–444: `notifyCharacteristicTo(centralId, charHandle, value)`.

- `bluey_ios/pigeons/messages.dart`: identical changes at L96–100, L103–113, L253–265, L268–284, L339, L343–348, L352, L356, L360, L390, L394–398.

#### Generated bindings (regenerated)

- `bluey_android/lib/src/messages.g.dart`
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt`
- `bluey_ios/lib/src/messages.g.dart`
- `bluey_ios/ios/Classes/Messages.g.swift`

#### Platform interface

- `bluey_platform_interface/lib/src/platform_interface.dart`:
  - L127–131 `PlatformDescriptor` gains `final int handle`.
  - L135–145 `PlatformCharacteristic` gains `final int handle`.
  - L385–388 `readCharacteristic(deviceId, charHandle)`.
  - L391–396 `writeCharacteristic(deviceId, charHandle, value, withResponse)`.
  - L399–403 `setNotification(deviceId, charHandle, enable)`.
  - L409 `readDescriptor(deviceId, descHandle)`.
  - L412–416 `writeDescriptor(deviceId, descHandle, value)`.
  - L482 `notifyCharacteristic(charHandle, value)`.
  - L485–489 `notifyCharacteristicTo(centralId, charHandle, value)`.
  - L671–683 `PlatformReadRequest` gains `final int characteristicHandle`.
  - L687–703 `PlatformWriteRequest` gains `final int characteristicHandle`.
  - `PlatformConnectionParameters` (L46–56) keeps primitives. A new mapper file in `bluey/lib/src/connection/` handles domain ↔ wire conversion.

#### Android native

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`:
  - Add `characteristicByHandle: MutableMap<String, MutableMap<Int, BluetoothGattCharacteristic>>` and `descriptorByHandle: MutableMap<String, MutableMap<Int, BluetoothGattDescriptor>>` near the existing field declarations.
  - Replace `findCharacteristic(gatt, uuid)` (L853–863) with `characteristicByHandle[deviceId]?[handle]`.
  - Replace `findDescriptor(gatt, uuid)` (L865–877) with `descriptorByHandle[deviceId]?[handle]`.
  - In `onServicesDiscovered` (after the existing rediscovery flow), populate the maps from `gatt.services` walk using `getInstanceId()`.
  - In the `STATE_DISCONNECTED` branch of `onConnectionStateChange`, clear `characteristicByHandle.remove(deviceId)` and `descriptorByHandle.remove(deviceId)`.
  - In `onServiceChanged`, clear maps before `gatt.discoverServices()`.
  - `mapCharacteristics` / `mapServices` (L879–902) emit `getInstanceId()` as the `handle` field.
  - `setNotification` (L360–416): use `characteristicByHandle` lookup instead of `findCharacteristic`. CCCD comes from `characteristic.getDescriptor(CCCD_UUID)` as before — already correctly scoped to the resolved characteristic.

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` (or wherever the local server lives):
  - At `addService`, walk `BluetoothGattService.characteristics` and emit `getInstanceId()` as the handle in the `CharacteristicDto`.
  - In `onCharacteristicReadRequest` / `onCharacteristicWriteRequest`, include `characteristic.getInstanceId()` in `ReadRequestDto` / `WriteRequestDto`.
  - `notifyCharacteristic(handle, value)` / `notifyCharacteristicTo(centralId, handle, value)` look up by handle.

#### iOS native

- `bluey_ios/ios/Classes/CentralManagerImpl.swift`:
  - Replace `characteristics: [String: [String: CBCharacteristic]]` (L26–28) with `characteristicByHandle: [String: [Int: CBCharacteristic]]`, `descriptorByHandle: [String: [Int: CBDescriptor]]`, `nextHandle: [String: Int]`.
  - Add `mintHandle(for deviceId: String) -> Int` helper.
  - In `peripheral(_, didDiscoverCharacteristicsFor:)` (around L587), mint and store handles.
  - In `peripheral(_, didDiscoverDescriptorsFor:)`, mint and store descriptor handles.
  - Replace `findCharacteristic(deviceId, uuid)` (L307–324) with `findCharacteristic(deviceId, handle)`.
  - Add analogous `findDescriptor(deviceId, handle)`.
  - Update `readCharacteristic` (L228–249), `writeCharacteristic` (L251–281), `setNotification` (L283–304) to use handle-keyed lookup.
  - In `centralManager(_, didDisconnectPeripheral:)`, clear `characteristicByHandle[deviceId]`, `descriptorByHandle[deviceId]`, `nextHandle[deviceId]`.
  - In `peripheral(_, didModifyServices:)`, clear and re-discover.

- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift`:
  - Replace `characteristics: [String: CBMutableCharacteristic]` (L17–18) with `characteristicByHandle: [Int: CBMutableCharacteristic]` and `private var nextHandle = 1`.
  - In `addService` (L44–61), mint a handle for each char. Return DTOs with handles.
  - `notifyCharacteristic` (L111), `notifyCharacteristicTo` (L130), `respondToReadRequest`, `respondToWriteRequest` look up by handle.

#### Domain layer

- `bluey/lib/src/connection/connection.dart`:
  - Remove bond/PHY/conn-params section (L211–290) from `Connection`.
  - Remove `isBlueyServer` (L144), `serverId` (L148).
  - Add `AndroidConnectionExtensions? get android` and `IosConnectionExtensions? get ios`.
  - Change `int get mtu` to `Mtu get mtu`.
  - Change `Future<int> requestMtu(int)` to `Future<Mtu> requestMtu(Mtu)`.
  - Replace primitive-typed `ConnectionParameters` (L36–78) with the value-object version. (Or move ConnectionParameters into `value_objects/connection_parameters.dart` and re-export.)

- `bluey/lib/src/connection/android_connection_extensions.dart` (NEW): the `AndroidConnectionExtensions` abstract class.
- `bluey/lib/src/connection/ios_connection_extensions.dart` (NEW): the empty `IosConnectionExtensions` abstract class.

- `bluey/lib/src/connection/bluey_connection.dart`:
  - Remove `_lifecycle` (L153), `_serverId` (L154), `isBlueyServer` (L157), `serverId` (L160), `upgrade()` (L296–315), and control-service filtering (L368–369 plus parallel sites in `services()`/`hasService()`).
  - Implement `android` getter — return `_AndroidConnectionExtensionsImpl(this)` only when the capabilities check passes; otherwise null.
  - Implement `ios` getter — return the singleton placeholder on iOS, null on other platforms.
  - Add private inner classes `_AndroidConnectionExtensionsImpl` and `_IosConnectionExtensionsImpl` (or move to siblings if they grow).
  - Add `_handle: AttributeHandle` to `BlueyRemoteCharacteristic` and `BlueyRemoteDescriptor`. Keep UUID for display/equality/navigation.
  - Expose `handle: AttributeHandle` getter on `RemoteCharacteristic` / `RemoteDescriptor`.
  - Add `RemoteService.characteristics({UUID? uuid})` plural accessor.
  - Add `RemoteCharacteristic.descriptors({UUID? uuid})` plural accessor.
  - At the Pigeon-call boundary in `BlueyRemoteCharacteristic.read()` / `write()` / `subscribe()` etc., unwrap to int via `_handle.value` for the platform call.

- `bluey/lib/src/peer/peer_connection.dart` (NEW): `PeerConnection` interface and `_BlueyPeerConnection` impl.
- `bluey/lib/src/peer/peer_remote_service_view.dart` (NEW): control-service-hiding view wrapper.

- `bluey/lib/src/bluey.dart`:
  - `_upgradeIfBlueyServer` (L379–447) becomes `_tryBuildPeerConnection(Connection raw): Future<PeerConnection?>`.
  - `connect(device)` returns raw `Connection` (no upgrade attempt).
  - New `connectAsPeer(device): Future<PeerConnection>` — throws `NotABlueyPeerException` on miss.
  - New `tryUpgrade(Connection): Future<PeerConnection?>`.

- `bluey/lib/src/peer/bluey_peer.dart`:
  - `BlueyPeer.connect()` returns `Future<PeerConnection>`.

- `bluey/lib/src/exceptions.dart`: add `NotABlueyPeerException`, `AttributeHandleInvalidatedException`, `AttributeNotFoundException`, `AmbiguousAttributeException`.

- `bluey/lib/src/connection/connection_parameters_mapper.dart` (NEW): bidirectional `toPlatform()` / `fromPlatform()`.

#### Value objects

- `bluey/lib/src/connection/value_objects/attribute_handle.dart` (NEW)
- `bluey/lib/src/connection/value_objects/mtu.dart` (NEW)
- `bluey/lib/src/connection/value_objects/connection_interval.dart` (NEW)
- `bluey/lib/src/connection/value_objects/peripheral_latency.dart` (NEW)
- `bluey/lib/src/connection/value_objects/supervision_timeout.dart` (NEW)
- `bluey/lib/src/connection/value_objects/connection_parameters.dart` (NEW; moved out of `connection.dart`)

Re-exported via `bluey/lib/bluey.dart`.

`AttributeHandle` shape:

```dart
@immutable
class AttributeHandle {
  final int value;
  AttributeHandle(this.value) {
    if (value <= 0) {
      throw ArgumentError('attribute handle must be positive: $value');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AttributeHandle && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AttributeHandle($value)';
}
```

#### Test infrastructure

- `bluey/test/fakes/fake_platform.dart`: switch internal storage to handle-keyed; mint handles at fake `discoverServices`. Add `fake.handleFor(deviceId, charUuid)` helper.
- `bluey/test/fakes/test_helpers.dart`: add `TestHandles` companion to `TestUuids`.

## Data flow

### Successful read of a characteristic on a multi-service peripheral

```
Dart: connection.service(uuidA).characteristic(charUuid).read()
  → BlueyRemoteCharacteristic._handle = 17
  → _platform.readCharacteristic(deviceId, 17)
  → Pigeon → Android receiver
  → Kotlin: characteristicByHandle["AA:BB:..."]?[17]  → BluetoothGattCharacteristic ref
  → enqueue read → callback delivers value
  → Dart: Future<Uint8List>
```

If two services both expose `charUuid`, the second is at handle 42. `connection.service(uuidB).characteristic(charUuid).read()` resolves to handle 42. Routing is unambiguous.

### Successful CCCD write on a per-characteristic basis

```
Dart: connection.service(uuidA).characteristic(charUuid).subscribe()
  → BlueyRemoteCharacteristic._handle = 17
  → _platform.setNotification(deviceId, 17, true)
  → Pigeon → Android receiver
  → Kotlin: char = characteristicByHandle[deviceId][17]
  → cccd = char.getDescriptor(CCCD_UUID)   // scoped to THIS characteristic
  → write CCCD
```

The "first descriptor with UUID 0x2902 wins" bug (I011) is gone: the CCCD lookup is intrinsically scoped to the resolved characteristic.

### Service Changed mid-flight

```
Android: onServiceChanged(gatt) [binder]
  → handler.post {
      characteristicByHandle.remove(deviceId)
      descriptorByHandle.remove(deviceId)
      gatt.discoverServices()
    }
Dart: BlueyConnection._handleServiceChange()
  → fail in-flight ops with AttributeHandleInvalidatedException
  → _cachedServices = null
  → emit ServiceChangedEvent

…onServicesDiscovered fires…
  → handler.post {
      // rebuild handle maps from gatt.services
      // emit new ServiceDiscoveryDto with new handles
    }
Dart: subscribers re-call connection.services() and re-resolve handles.
```

### Connect-as-peer flow

```
Dart: bluey.connectAsPeer(device)
  → bluey.connect(device) returns Connection (raw)
  → _tryBuildPeerConnection(connection):
      services = await connection.services()
      if no control service → throw NotABlueyPeerException
      controlChar = service.characteristic(ctrlChar)
      serverId = ServerId.parse(await controlChar.read())
      lifecycle = LifecycleClient(connection, controlChar)
      return _BlueyPeerConnection(connection, serverId, lifecycle)
```

`peer.connection.android` is reachable for users who need Android-extension features alongside peer-protocol features.

## Error handling

| Scenario | Outcome |
|---|---|
| Read with stale handle (post-Service-Changed) | `AttributeHandleInvalidatedException` |
| Read with handle from a different connection | `AttributeNotFoundException` |
| `connection.service(uuid)` matches more than one service | `AmbiguousAttributeException(uuid, n)` |
| `service.characteristic(uuid)` matches more than one char in the service | `AmbiguousAttributeException(uuid, n)` |
| `characteristic.descriptor(uuid)` matches more than one descriptor | `AmbiguousAttributeException(uuid, n)` |
| `bluey.connectAsPeer(non-bluey-device)` | throws `NotABlueyPeerException` |
| `bluey.tryUpgrade(non-bluey-connection)` | returns null |
| `connection.android.bond()` on iOS | `connection.android` is `null` — user must use `?.`; `connection.android?.bond()` evaluates to `null` (no-op) |
| `Mtu(20, capabilities: …)` | `ArgumentError: MTU must be ≥ 23` |
| `Mtu(517, capabilities: iosCapabilities)` | `ArgumentError: MTU 517 exceeds platform maximum 185` |
| `ConnectionParameters(interval: ConnectionInterval(100), latency: PeripheralLatency(99), timeout: SupervisionTimeout(50))` | `ArgumentError: supervision timeout must exceed (1 + 99) * 100 = 10000 ms` |

## Testing

Existing baseline (per the catalog):
- bluey: 653 tests
- bluey_platform_interface: 32 tests
- bluey_android JVM + bluey_ios XCTest: ~50 + ~80 (approx; see Decision 12).

Many tests will need call-site updates (Mtu construction, `connection.android?` migration, peer-connect migration), but should pass without semantic changes.

### TDD per backlog item

#### I088 — Pigeon handle rewrite

- `bluey_platform_interface/test/messages_handle_test.dart` — DTO round-trips with handle.
- `bluey/test/connection/handle_routing_test.dart` — duplicate-UUID across services routes to the right handle (FakeBlueyPlatform with two services exposing the same charUuid; user disambiguates via plural accessor + `handle`).
- `bluey/test/connection/ambiguous_attribute_test.dart` — singular `service(uuid)` / `characteristic(uuid)` / `descriptor(uuid)` accessors throw `AmbiguousAttributeException` when more than one attribute matches.
- `bluey/test/connection/cccd_routing_test.dart` — subscribing to one of two notifyable chars only writes that one's CCCD.
- `bluey_android/android/src/test/kotlin/.../HandleLookupTest.kt` — `characteristicByHandle` population and clear-on-disconnect.
- `bluey_android/android/src/test/kotlin/.../ServiceChangedHandleTest.kt` — Service Changed clears and rebuilds the handle table; in-flight ops fail with `AttributeHandleInvalidatedException`.
- `bluey_ios/ios/Tests/CentralManagerHandleTests.swift` — handle minting and lookup.
- `bluey_ios/ios/Tests/PeripheralManagerHandleTests.swift` — server-side handle assignment at `addService`.

#### I089/I066 — Platform-tagged extensions

- `bluey/test/connection/android_extensions_test.dart` — `connection.android` non-null when caps permit, null otherwise.
- `bluey/test/connection/extensions_null_safety_test.dart` — `connection.android?.bond()` on iOS-flavored caps is null.
- Parameterize FakeBlueyPlatform so existing bonding tests can run with Android-flavored capabilities.

#### I300 — PeerConnection composition

- `bluey/test/peer/peer_connection_test.dart` — `connectAsPeer(non-peer)` throws; `connectAsPeer(peer)` returns wrapping; `peer.connection` is the raw connection; raw `connection.services()` includes the control service while `peer.services()` excludes it.
- `bluey/test/peer/try_upgrade_test.dart` — `tryUpgrade` returns null on non-peer, `PeerConnection` on peer.
- "Test by deletion": `Connection.isBlueyServer` no longer compiles. Existing tests that asserted on it are migrated.

#### I301 — Value objects

- `bluey/test/connection/mtu_test.dart` — Mtu boundary tests (23, 184/185 on iOS, 517/518 on Android, capabilities-aware).
- `bluey/test/connection/connection_parameters_test.dart` — value-object boundaries; cross-field invariant.
- Update FakeBlueyPlatform fixtures to construct value objects.

### Existing tests requiring call-site updates

- Tests calling `connection.requestMtu(517)` change to `connection.requestMtu(Mtu(517, capabilities: caps))`. ~10–20 sites estimated.
- Tests asserting `connection.isBlueyServer == true` change to `final peer = await bluey.connectAsPeer(device);`.
- Tests calling `connection.bond()` change to `connection.android?.bond()`. (FakeBlueyPlatform's capabilities matrix gates the extension.)
- `connection.services()` / `service().characteristic()` navigation works unchanged at the user-facing API layer.

### Manual verification

Run the example app on both platforms against:

1. **Multi-service peripheral with duplicate characteristics** — connect to a peripheral that exposes two services each with the same charUuid (set up in example app debug mode, or use a real third-party device with this property); verify subscribing to one doesn't toggle the other's notifications. **This is the load-bearing test for I088.**
2. **Service Changed flow** — peripheral that triggers Service Changed via a debug command; verify in-flight ops fail with `AttributeHandleInvalidatedException` cleanly and re-discovery rebuilds handles.
3. **Existing soak / failure-injection scenarios** unchanged — confirms no regressions to I098-era fixes.
4. **iOS connect + bond attempt** — `connection.android` is null; `connection.android?.bond()` evaluates to null (no exception).
5. **Android connect + bond attempt** — `connection.android?.bond()` succeeds (or returns the existing stub success per I035 Stage A).
6. **connectAsPeer on a non-Bluey peripheral** — throws `NotABlueyPeerException`.
7. **connect + tryUpgrade on a Bluey peer** — succeeds; `peer.serverId` is the expected ID.

The user (Joel) runs these manually after JVM/XCTest pass; the JVM tests alone don't prove the rewrite is correct in production.

## Migration plan (commit sequence)

The bundled rewrite is large; commits are sequenced for reviewability. Each commit leaves the suite green and follows TDD (Red → Green → Refactor). Phase boundaries are explicit review checkpoints.

The phase order is **value objects → extensions → peer composition → handles**. Why this order:
- Value objects are foundation — every later phase touches `Connection`'s signature.
- Extensions are the simpler split (no behavior change, just relocation).
- Peer composition restructures around the now-cleaner Connection.
- Handle rewrite is most invasive; doing it last means the handle work doesn't have to keep changing as we refactor `Connection` underneath it.

(See open question 7 about whether D should go first instead, since it's the highest-severity item.)

### Phase A — I301 value objects

1. `feat(bluey): add Mtu, ConnectionInterval, PeripheralLatency, SupervisionTimeout, value-object ConnectionParameters`
2. `feat(bluey): add ConnectionParameters mapper (domain ↔ wire)`
3. `refactor(bluey): change Connection.mtu to Mtu, requestMtu to take Mtu`
4. `test(bluey): value-object boundary tests`
5. `refactor(example): migrate example app to value-object Mtu / ConnectionParameters`

### Phase B — I089/I066 platform-tagged extensions

6. `refactor(bluey): introduce AndroidConnectionExtensions + IosConnectionExtensions interfaces`
7. `feat(bluey): wire connection.android / connection.ios accessors via Capabilities gate`
8. `test(bluey): connection.android non-null on Android caps, null on iOS caps`
9. `refactor(bluey): remove bond/PHY/conn-params from Connection interface (breaking)`
10. `refactor(example): migrate example app bond/PHY usage to connection.android?`

### Phase C — I300 PeerConnection composition

11. `feat(bluey/peer): introduce PeerConnection abstract + _BlueyPeerConnection impl`
12. `feat(bluey/peer): introduce PeerRemoteServiceView (control-service hider)`
13. `feat(bluey): add Bluey.connectAsPeer and Bluey.tryUpgrade`
14. `refactor(bluey): remove BlueyConnection.upgrade and isBlueyServer/serverId (breaking)`
15. `refactor(bluey/peer): BlueyPeer.connect returns PeerConnection`
16. `refactor(example): migrate example app to connectAsPeer / PeerConnection`
17. `refactor(bluey): remove control-service filtering from BlueyConnection.{service,services,hasService}`

### Phase D — I088 Pigeon handle rewrite

D is sequenced as: schema additive → platform-side population → platform-side switch → domain switch → schema breaking-cleanup. Both platforms are progressed in parallel within each step where possible; the platform plugins live in independent packages.

18. `refactor(pigeons): add handle field to CharacteristicDto/DescriptorDto and ReadRequest/WriteRequest (additive; UUID kept)`
19. `refactor(bluey_platform_interface): add handle parameter alongside UUID on GATT methods (additive)`
20. `feat(bluey_android): populate characteristicByHandle / descriptorByHandle at discovery; clear on disconnect`
21. `refactor(bluey_android): switch read/write/setNotification to handle-keyed lookup`
22. `refactor(bluey_android): handle Service Changed by clearing handle maps`
23. `feat(bluey_ios): mint handles in CentralManager discovery callbacks`
24. `refactor(bluey_ios): switch read/write/setNotify to handle-keyed lookup`
25. `feat(bluey_ios): mint handles in PeripheralManager addService`
26. `refactor(bluey_ios): switch notify / respondTo* to handle-keyed lookup`
27. `refactor(bluey): BlueyRemoteCharacteristic/Descriptor carry handle`
28. `refactor(pigeons): drop UUID parameter from GATT methods (handle-only; breaking)`
29. `refactor(bluey_platform_interface): drop UUID parameter from GATT methods (breaking)`
30. `test(bluey): handle-routing tests for duplicate UUIDs across services`
31. `test(bluey): cccd-routing test for two notifyable chars`
32. `test(bluey_android): JVM tests for handle-table population and clear`
33. `test(bluey_ios): XCTest for handle minting and lookup`

### Phase E — cleanup + close-out

34. `refactor(bluey): update FakeBlueyPlatform to handle-keyed storage`
35. `docs(bluey): update CLAUDE.md with handle-identity invariant and connection.android pattern`
36. `docs(android): note handle lifetime in ANDROID_BLE_NOTES.md`
37. `docs(ios): note handle minting in IOS_BLE_NOTES.md`
38. `chore(backlog): mark I010, I011, I016, I066, I088, I089, I300, I301 fixed`
39. `chore(release): bump major version (breaking change) across all four packages`

## Decisions

### Decision 1: handle wire type — `int` on the wire, `AttributeHandle` value object on the Dart side

Pigeon's `int` is the right wire type. Android's `getInstanceId()` returns `Int`; iOS counter is `Int64`-domained. **The Dart domain layer wraps the wire int in an `AttributeHandle` value object** so user code can't accidentally pass a deviceId int (or any other int) where a handle is expected. Native code stays raw int — the wrapper exists purely on the Dart side. Confirmed by user.

### Decision 2: handle 0 / negative semantics

0 is reserved as "invalid handle". Valid handles are positive. Android's `getInstanceId()` is implementation-defined but in practice always positive; iOS counter starts at 1.

### Decision 3: navigation API supports both UUIDs and handles; singular accessors throw on ambiguity

Confirmed by user: support both. UUIDs stay as the primary navigation key — they're what users discover from vendor specs, BLE GATT registries, and product docs. Handles are platform-assigned and not predictable, so they cannot be the user's discovery path. But once a `RemoteCharacteristic` / `RemoteDescriptor` is in hand, its `handle: AttributeHandle` getter is exposed so users can disambiguate when needed.

The user-facing common path stays `connection.service(uuid).characteristic(uuid)`. **The singular accessors throw `AmbiguousAttributeException` on duplicate-UUID matches instead of silently returning the first** — that was the silent-wrong-routing trap the user flagged. Concrete shapes:

```dart
RemoteCharacteristic characteristic(UUID uuid) {
  final matches = characteristics(uuid: uuid);
  if (matches.isEmpty) throw CharacteristicNotFoundException(uuid);
  if (matches.length > 1) {
    throw AmbiguousAttributeException(uuid, matches.length);
  }
  return matches.single;
}
```

Same rule on `Connection.service(uuid)` (throw on duplicate services with same UUID at the connection level) and `RemoteCharacteristic.descriptor(uuid)` (throw on duplicate descriptors). The plural accessor (`characteristics({UUID? uuid})`, etc.) is the disambiguation escape hatch for the pathological case.

Considered alternative: remove the singular accessor entirely and force `.single` chains everywhere. Rejected because of the verbosity tax on the 99% common case. Throw-on-ambiguous gives the same safety with no ergonomic regression for non-duplicate peripherals.

### Decision 4: PeerConnection composes Connection (not inherits)

`peer.connection.services()` is the access path, not `peer.services()` for raw GATT. PeerConnection has its own narrow surface (peer-protocol ops + control-service-hidden service tree). Composition keeps the bounded-context boundary explicit. Forwarding getters can be added later if call sites demand them.

### Decision 5: `connectAsPeer` and `tryUpgrade` both exist

`connectAsPeer(device)` is the common path (one call, throws on miss). `tryUpgrade(connection)` covers the rare case where a Service Changed reveals a control service post-connect on an initially-raw connection. Both share `_tryBuildPeerConnection` internally.

### Decision 6: Mtu validation is runtime

`Mtu(value, capabilities: caps)` validates at construction. A compile-time approach would require platform-tagged Mtu types (`AndroidMtu`, `IosMtu`), not worth the cost. `Mtu.fromPlatform(int)` factory bypasses validation for platform reads.

### Decision 7: value-object file layout

One file per value object under `bluey/lib/src/connection/value_objects/`. Re-exported via `bluey/lib/bluey.dart`.

### Decision 8: keep `IosConnectionExtensions` empty class

Yes. ~10 lines, signals that iOS-side extensions are a planned axis (vs "we forgot"), and means future iOS-only methods don't change Connection's interface — they add to the existing type. Symmetric with Android.

### Decision 9: Service Changed handle-invalidation error type

`AttributeHandleInvalidatedException`. Distinct from `DeviceNotConnectedException` (the link is up; topology changed) and `ServiceNotFoundException` (the service is gone after rediscovery).

### Decision 10: no migration guide

Confirmed. Only the example app uses Bluey. Example-app updates and a CHANGELOG entry suffice.

### Decision 11: control-service filtering moves into PeerRemoteServiceView

Raw `Connection.services()` returns the full tree. Hiding the lifecycle control service is a Peer-protocol concern; it belongs in the Peer module's view layer.

### Decision 12: existing tests should pass with call-site updates only

The semantic surface stays the same; only routing identity and platform-asymmetry expression change. If a test fails for any reason other than a call-site update (Mtu construction, `connection.android?` migration, `connectAsPeer` migration, or handle-keyed FakeBlueyPlatform setup), treat it as a regression and stop.

## Success criteria

- All baseline tests pass with call-site updates: 653 (bluey) + 32 (bluey_platform_interface) + bluey_android JVM + bluey_ios XCTest.
- New tests added per *Testing* above: ~30 across Dart + Android JVM + iOS XCTest.
- `flutter analyze` clean across all four packages.
- `./gradlew test` clean for `bluey_android/android`.
- iOS test runner clean for `bluey_ios`.
- Manual verification on both platforms against the seven scenarios above passes (load-bearing).
- `docs/backlog/I010.md`, `I011.md`, `I016.md`, `I066.md`, `I088.md`, `I089.md`, `I300.md`, `I301.md` all marked `status: fixed` with the bundle's last commit SHAs in `fixed_in`.
- `docs/backlog/README.md` Tier 3 list updated; bundle moves to "Fixed — verified in HEAD".
- Major version bumped in all four `pubspec.yaml` files; cross-package version constraints coordinated.

## Open questions

All resolved by user (2026-04-28):

1. **`AttributeHandle` Dart-side wrapper** — yes, wrap. See Decision 1.
2. **Navigation: UUIDs vs handles** — support both. UUIDs primary, handles for disambiguation. See Decision 3.
3. **Mapper placement** — separate file, keep domain pure. See Decision 12 (this section).
4. **`refreshGattCache`** — on `AndroidConnectionExtensions`. Confirmed.
5. **`requestConnectionPriority`** — on `AndroidConnectionExtensions`. Confirmed.
6. **iOS handle counter wraparound** — noted; non-issue at Int64.
7. **Phase ordering** — Phase D (handles) last. Confirmed.
8. **Phase D commit granularity** — granular commits, additive-interim included. Confirmed.
