# Bluey Architecture Document

> A modern, elegant Bluetooth Low Energy library for Flutter

## Table of Contents

1. [Vision & Goals](#vision--goals)
2. [Design Principles](#design-principles)
3. [Ubiquitous Language](#ubiquitous-language)
4. [Architecture Overview](#architecture-overview)
5. [Bounded Contexts](#bounded-contexts)
6. [Domain Model](#domain-model)
7. [Public API Design](#public-api-design)
8. [Platform Abstraction](#platform-abstraction)
9. [Error Handling](#error-handling)
10. [Testing Strategy](#testing-strategy)
11. [Migration Path](#migration-path)
12. [Package Structure](#package-structure)
13. [Example App](#example-app)
14. [Implementation Roadmap](#implementation-roadmap)

---

## Vision & Goals

### Vision

Bluey aims to be the most intuitive and developer-friendly Bluetooth Low Energy library for Flutter. It should feel as natural as working with HTTP or WebSockets - hiding complexity while exposing power when needed.

### Goals

1. **Simplicity First** - Common tasks should require minimal code
2. **Discoverable API** - IDE autocomplete guides developers naturally
3. **Type Safety** - Compile-time guarantees over runtime errors
4. **Resource Safety** - Automatic cleanup, no memory leaks
5. **Testability** - Easy mocking and simulation
6. **Platform Parity** - Consistent behavior across iOS, Android, macOS, Windows, Linux
7. **Performance** - Minimal overhead, efficient memory usage
8. **Extensibility** - Support for custom codecs, protocols, and extensions

### Non-Goals

- Supporting Bluetooth Classic (BR/EDR)
- Implementing specific BLE profiles (those belong in separate packages)
- Background execution (platform-specific, documented but not abstracted)

---

## Design Principles

### Mandatory Development Practices

This project **strictly adheres** to the following methodologies. These are not guidelines—they are requirements.

#### Domain-Driven Design (DDD)

All code must follow DDD principles:

- **Ubiquitous Language**: Use the defined terminology consistently in code, documentation, and communication
- **Bounded Contexts**: Respect context boundaries; do not leak domain concepts across boundaries
- **Aggregates**: All mutations go through aggregate roots; enforce invariants at the aggregate level
- **Value Objects**: Immutable data with equality by value, not identity
- **Entities**: Objects with identity that persists across state changes
- **Domain Events**: Use events for cross-aggregate communication

#### Clean Architecture (CA)

All code must follow Clean Architecture layering:

```
┌─────────────────────────────────────────────────┐
│              Frameworks & Drivers               │  ← Platform code (Kotlin, Swift, etc.)
├─────────────────────────────────────────────────┤
│            Interface Adapters                   │  ← Pigeon APIs, Stream adapters
├─────────────────────────────────────────────────┤
│              Application Layer                  │  ← Use cases, orchestration
├─────────────────────────────────────────────────┤
│                Domain Layer                     │  ← Entities, Value Objects, Domain Services
└─────────────────────────────────────────────────┘
```

- **Dependency Rule**: Dependencies point inward only. Inner layers know nothing about outer layers.
- **Entities and Use Cases** are the core; they have no dependencies on frameworks or platforms
- **Interface Adapters** convert data between domain and external formats
- **Frameworks & Drivers** are implementation details that can be swapped

#### Test-Driven Development (TDD)

All development must follow the TDD cycle:

1. **Red**: Write a failing test that defines the expected behavior
2. **Green**: Write the minimum code to make the test pass
3. **Refactor**: Improve the code while keeping tests green

Requirements:
- No production code without a failing test first
- Tests must be written before implementation
- Each bounded context must have comprehensive unit tests
- Integration tests must cover platform interactions
- Code coverage targets: minimum 90% for domain layer, 80% overall

### 1. Connection-Centric Architecture

The `Connection` is the primary abstraction, not the "Manager". Users think in terms of:
- "I want to connect to this device"
- "I want to read this value"
- "I want to receive notifications"

Not:
- "I need a CentralManager to scan"
- "I need to discover services before reading"

### 2. Progressive Disclosure

Simple things are simple, complex things are possible:

```dart
// Simple: One-liner to read a value
final value = await device.connect().then((c) => c.read(charUUID));

// Complex: Full control when needed
final connection = await device.connect(
  timeout: Duration(seconds: 10),
  mtu: 512,
  priority: ConnectionPriority.high,
  autoReconnect: ReconnectPolicy.exponentialBackoff(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 1),
  ),
);
```

### 3. Streams Over Callbacks

All asynchronous events use Dart Streams:

```dart
// Not callbacks
manager.onDeviceDiscovered = (device) { ... };  // Bad

// Streams compose naturally
bluey.scan()
  .where((d) => d.name?.contains('Sensor') ?? false)
  .take(5)
  .listen((device) { ... });  // Good
```

### 4. Immutable Data, Mutable Connections

Data objects (Device, Advertisement, Service definitions) are immutable.
Connection state is mutable but observable.

```dart
// Immutable - can be cached, compared, serialized
final device = Device(id: uuid, name: 'Sensor');
final service = ServiceDefinition(uuid: uuid, characteristics: [...]);

// Mutable - state changes over time
connection.state; // connected -> disconnecting -> disconnected
```

### 5. Explicit Over Implicit

No hidden state or magic behavior:

```dart
// Bad: Implicit singleton
CentralManager(); // Returns cached instance? New instance? Who knows.

// Good: Explicit lifecycle
final bluey = Bluey();
// ... use bluey ...
await bluey.dispose();
```

### 6. Fail Fast, Fail Clearly

Errors should be specific, actionable, and caught at the earliest possible point:

```dart
// Bad: Generic error
throw Exception('Operation failed');

// Good: Specific, actionable error
throw BluetoothDisabledException(
  message: 'Bluetooth is turned off',
  action: 'Call bluey.requestEnable() or direct user to Settings',
);
```

---

## Ubiquitous Language

These terms are used consistently throughout the codebase, documentation, and API:

| Term | Definition | Example |
|------|------------|---------|
| **Bluey** | The main entry point to the library | `final bluey = Bluey();` |
| **Device** | A discovered BLE peripheral with advertisement data | `device.name`, `device.rssi` |
| **Connection** | An active link to a device with GATT access | `await device.connect()` |
| **Server** | Local GATT server for peripheral role | `bluey.server()` |
| **Service** | A collection of related characteristics | `connection.service(uuid)` |
| **Characteristic** | A readable/writable/notifiable data point | `char.read()`, `char.write(data)` |
| **Descriptor** | Metadata about a characteristic | `char.descriptor(uuid)` |
| **Scanner** | Discovers nearby advertising devices | `bluey.scan()` |
| **Advertisement** | Broadcast data from a peripheral | `device.advertisement.serviceUuids` |
| **Notification** | Server-pushed value update | `char.notifications.listen(...)` |
| **MTU** | Maximum transmission unit (packet size) | `connection.mtu` |
| **RSSI** | Signal strength indicator (proximity) | `device.rssi` |
| **UUID** | Unique identifier for services/characteristics | `UUID('180D')` |

### Terms We Avoid

| Avoid | Use Instead | Reason |
|-------|-------------|--------|
| CentralManager | `Bluey`, `Scanner` | Too low-level |
| PeripheralManager | `Server` | Clearer intent |
| GATT | (implicit) | Implementation detail |
| CBPeripheral / BluetoothDevice | `Device` | Platform-specific |
| Discover services | (automatic) | Hidden complexity |
| Event / EventArgs | (typed streams) | More idiomatic Dart |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         APPLICATION LAYER                           │
│                     (Your Flutter App Code)                         │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          BLUEY PUBLIC API                           │
│  ┌─────────┐  ┌────────────┐  ┌────────┐  ┌───────────────────┐    │
│  │  Bluey  │  │   Device   │  │ Server │  │    Connection     │    │
│  │         │  │            │  │        │  │                   │    │
│  │ scan()  │  │ connect()  │  │ add()  │  │ service(uuid)     │    │
│  │ server()│  │ rssi       │  │ start()│  │ read()/write()    │    │
│  │ state   │  │ name       │  │ notify()│ │ notifications     │    │
│  └─────────┘  └────────────┘  └────────┘  └───────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           CORE LAYER                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │  State Machine  │  │   GATT Cache    │  │  Stream Manager │     │
│  │                 │  │                 │  │                 │     │
│  │ Connection      │  │ Service tree    │  │ Broadcast       │     │
│  │ lifecycle       │  │ Lazy discovery  │  │ Subscription    │     │
│  │ transitions     │  │ Value caching   │  │ management      │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │      UUID       │  │     Codec       │  │   Capability    │     │
│  │                 │  │                 │  │                 │     │
│  │ Parsing         │  │ Value encoding  │  │ Platform        │     │
│  │ Short/Long form │  │ Type conversion │  │ feature matrix  │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      PLATFORM INTERFACE                             │
│                                                                     │
│  abstract class BlueyPlatform {                                     │
│    Stream<DeviceEvent> scan(ScanConfig config);                     │
│    Future<PlatformConnection> connect(String id, ConnectConfig);    │
│    Future<void> disconnect(String id);                              │
│    // ... etc                                                       │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
┌─────────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│   bluey_android     │ │   bluey_darwin  │ │   bluey_windows     │
│                     │ │                 │ │                     │
│ Kotlin + Pigeon     │ │ Swift + Pigeon  │ │ C++ + WinRT         │
│ BluetoothGatt       │ │ CoreBluetooth   │ │ Windows.Devices.BLE │
└─────────────────────┘ └─────────────────┘ └─────────────────────┘
                                              ┌─────────────────────┐
                                              │    bluey_linux      │
                                              │                     │
                                              │ Dart + BlueZ DBus   │
                                              └─────────────────────┘
```

---

## Bounded Contexts

### 1. Discovery Context

**Responsibility:** Finding and identifying nearby BLE devices.

**Entities:**
- `Scanner` - Orchestrates the scanning process
- `Device` - Aggregate root representing a discovered peripheral
- `Advertisement` - Value object containing broadcast data

**Operations:**
- Start/stop scanning
- Filter by service UUIDs, name, RSSI
- Deduplicate and track device updates

**Boundaries:**
- Input: Scan configuration (filters, timeout)
- Output: Stream of Device objects
- No knowledge of connections or GATT

```dart
// Discovery context API
final scanner = bluey.scan(
  services: [heartRateServiceUUID],
  timeout: Duration(seconds: 30),
);

await for (final device in scanner) {
  print('${device.name}: ${device.rssi} dBm');
}
```

### 2. Connection Context

**Responsibility:** Establishing and maintaining links to devices.

**Entities:**
- `Connection` - Aggregate root representing an active link
- `ConnectionState` - Value object (connecting, connected, disconnecting, disconnected)

**Operations:**
- Connect with configuration (timeout, MTU, priority)
- Disconnect gracefully
- Monitor connection state changes
- Auto-reconnect policies

**Boundaries:**
- Input: Device reference, connection configuration
- Output: Connection object with state stream
- Owns the link lifecycle, provides access to GATT context

```dart
// Connection context API
final connection = await device.connect(
  timeout: Duration(seconds: 10),
  mtu: 512,
);

connection.state.listen((state) {
  print('Connection state: $state');
});

await connection.disconnect();
```

### 3. GATT Client Context

**Responsibility:** Reading, writing, and subscribing to remote device attributes.

**Entities:**
- `RemoteService` - Service on a connected device
- `RemoteCharacteristic` - Characteristic with read/write/notify operations
- `RemoteDescriptor` - Descriptor for characteristic metadata

**Operations:**
- Lazy service discovery (on first access)
- Read/write characteristic values
- Subscribe/unsubscribe to notifications
- Read/write descriptors

**Boundaries:**
- Input: Connection reference, UUIDs
- Output: Values, notification streams
- Accessed through Connection aggregate

```dart
// GATT client context API
final heartRate = connection
  .service(heartRateServiceUUID)
  .characteristic(heartRateMeasurementUUID);

// Read
final value = await heartRate.read();

// Write
await heartRate.write([0x01], withResponse: true);

// Subscribe
await for (final data in heartRate.notifications) {
  print('Heart rate: ${data[1]} bpm');
}
```

### 4. GATT Server Context

**Responsibility:** Publishing local services and responding to remote requests.

**Entities:**
- `Server` - Aggregate root for peripheral role
- `LocalService` - Published service definition
- `LocalCharacteristic` - Characteristic with handlers
- `Subscriber` - Remote device subscribed to notifications

**Operations:**
- Define and publish services
- Handle read/write requests
- Push notifications to subscribers
- Start/stop advertising

**Boundaries:**
- Input: Service definitions, advertisement configuration
- Output: Request streams, subscriber management
- Independent of client context (device can be both)

```dart
// GATT server context API
final server = bluey.server();

server.addService(
  LocalService(
    uuid: myServiceUUID,
    characteristics: [
      LocalCharacteristic.readable(
        uuid: myCharUUID,
        onRead: () => Uint8List.fromList([42]),
      ),
      LocalCharacteristic.notifiable(
        uuid: myNotifyUUID,
      ),
    ],
  ),
);

await server.startAdvertising(name: 'My Device');

// Push notification to all subscribers
await server.notify(myNotifyUUID, data: newValue);
```

### 5. Platform Context

**Responsibility:** System-level Bluetooth capabilities and permissions.

**Entities:**
- `BluetoothState` - Adapter power state
- `Permissions` - Authorization status
- `Capabilities` - Platform feature matrix

**Operations:**
- Query Bluetooth state
- Request permissions
- Enable/disable Bluetooth (where supported)
- Query platform capabilities

**Boundaries:**
- Input: None (reflects system state)
- Output: State streams, capability queries
- Affects all other contexts (gating operations)

```dart
// Platform context API
// State monitoring
bluey.state.listen((state) {
  switch (state) {
    case BluetoothState.on:
      startMyBleFeature();
    case BluetoothState.off:
      showEnableBluetoothPrompt();
    case BluetoothState.unauthorized:
      requestPermissions();
  }
});

// Capability checking
if (bluey.capabilities.supportsServer) {
  startPeripheralMode();
}
```

---

## Domain Model

### Aggregates

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DEVICE AGGREGATE                             │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Device (Aggregate Root)                                      │   │
│  │                                                              │   │
│  │ - id: UUID                    Identity                       │   │
│  │ - name: String?               From advertisement             │   │
│  │ - rssi: int                   Signal strength                │   │
│  │ - advertisement: Advertisement                               │   │
│  │                                                              │   │
│  │ + connect(): Future<Connection>                              │   │
│  │ + equals(): Uses id only                                     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Advertisement (Value Object)                                 │   │
│  │                                                              │   │
│  │ - serviceUuids: List<UUID>                                   │   │
│  │ - serviceData: Map<UUID, Uint8List>                          │   │
│  │ - manufacturerData: ManufacturerData?                        │   │
│  │ - txPowerLevel: int?                                         │   │
│  │ - isConnectable: bool                                        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      CONNECTION AGGREGATE                           │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Connection (Aggregate Root)                                  │   │
│  │                                                              │   │
│  │ - deviceId: UUID              Reference to Device            │   │
│  │ - state: ConnectionState      Observable                     │   │
│  │ - mtu: int                    Negotiated MTU                 │   │
│  │ - services: List<RemoteService>  Lazy-loaded                 │   │
│  │                                                              │   │
│  │ + service(uuid): RemoteService                               │   │
│  │ + disconnect(): Future<void>                                 │   │
│  │ + requestMtu(int): Future<int>                               │   │
│  │                                                              │   │
│  │ Invariants:                                                  │   │
│  │ - GATT access only when state == connected                   │   │
│  │ - Services discovered lazily on first access                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│         ┌────────────────────┼────────────────────┐                │
│         ▼                    ▼                    ▼                │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐        │
│  │RemoteService│      │RemoteService│      │RemoteService│        │
│  │             │      │             │      │             │        │
│  │ uuid        │      │ uuid        │      │ uuid        │        │
│  │ characteristics    │ ...         │      │ ...         │        │
│  └──────┬──────┘      └─────────────┘      └─────────────┘        │
│         │                                                          │
│         ▼                                                          │
│  ┌──────────────────┐                                              │
│  │RemoteCharacteristic                                             │
│  │                  │                                              │
│  │ uuid             │                                              │
│  │ properties       │                                              │
│  │ descriptors      │                                              │
│  │                  │                                              │
│  │ + read()         │                                              │
│  │ + write(data)    │                                              │
│  │ + notifications  │  Stream<Uint8List>                           │
│  └──────────────────┘                                              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        SERVER AGGREGATE                             │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Server (Aggregate Root)                                      │   │
│  │                                                              │   │
│  │ - isAdvertising: bool                                        │   │
│  │ - services: List<LocalService>                               │   │
│  │ - subscribers: Map<UUID, Set<Subscriber>>                    │   │
│  │                                                              │   │
│  │ + addService(LocalService)                                   │   │
│  │ + removeService(UUID)                                        │   │
│  │ + startAdvertising(AdvertiseConfig)                          │   │
│  │ + stopAdvertising()                                          │   │
│  │ + notify(UUID, Uint8List)                                    │   │
│  │                                                              │   │
│  │ Invariants:                                                  │   │
│  │ - Cannot modify services while advertising                   │   │
│  │ - Notifications only to subscribed characteristics           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│         ┌────────────────────┼────────────────────┐                │
│         ▼                    ▼                    ▼                │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐        │
│  │LocalService │      │LocalService │      │LocalService │        │
│  │             │      │             │      │             │        │
│  │ uuid        │      │ uuid        │      │ uuid        │        │
│  │ characteristics    │             │      │             │        │
│  └──────┬──────┘      └─────────────┘      └─────────────┘        │
│         │                                                          │
│         ▼                                                          │
│  ┌────────────────────────────────────────┐                        │
│  │ LocalCharacteristic                    │                        │
│  │                                        │                        │
│  │ uuid                                   │                        │
│  │ properties                             │                        │
│  │ permissions                            │                        │
│  │ onRead: () => Uint8List                │                        │
│  │ onWrite: (Uint8List) => GattStatus     │                        │
│  └────────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Value Objects

```dart
/// 128-bit Bluetooth UUID with short-form support
@immutable
class UUID {
  final Uint8List bytes; // Always 16 bytes
  
  /// Create from full UUID string: '0000180d-0000-1000-8000-00805f9b34fb'
  factory UUID(String value);
  
  /// Create from short (16-bit) form: '180D' or 0x180D
  factory UUID.short(int value);
  
  /// Well-known service UUIDs
  static const heartRate = UUID.short(0x180D);
  static const battery = UUID.short(0x180F);
  static const deviceInfo = UUID.short(0x180A);
  
  bool get isShort; // True if standard Bluetooth base UUID
  String get shortString; // '180D' or full string if not short
  
  @override
  bool operator ==(Object other);
  
  @override
  int get hashCode;
}

/// Connection state machine
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting;
  
  bool get isActive => this == connecting || this == connected;
}

/// Bluetooth adapter state
enum BluetoothState {
  unknown,      // Initial state before platform reports
  unsupported,  // Device doesn't support BLE
  unauthorized, // Permission not granted
  off,          // Bluetooth disabled
  on;           // Ready to use
  
  bool get isReady => this == on;
}

/// Characteristic properties (flags)
class CharacteristicProperties {
  final bool canRead;
  final bool canWrite;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;
  
  const CharacteristicProperties({...});
  
  factory CharacteristicProperties.fromFlags(int flags);
}

/// Manufacturer-specific advertisement data
@immutable
class ManufacturerData {
  final int companyId;  // Bluetooth SIG assigned
  final Uint8List data;
  
  const ManufacturerData(this.companyId, this.data);
  
  /// Well-known company IDs
  static const int apple = 0x004C;
  static const int google = 0x00E0;
  static const int microsoft = 0x0006;
}
```

---

## Public API Design

### Main Entry Point

```dart
/// The main entry point to Bluey
class Bluey {
  /// Create a new Bluey instance
  /// 
  /// Typically, create one instance and reuse it throughout your app.
  /// Call [dispose] when done to release resources.
  factory Bluey() => Bluey._();
  
  /// Current Bluetooth state
  /// 
  /// Emits immediately with current state, then on every change.
  Stream<BluetoothState> get state;
  
  /// Current state synchronously (may be [BluetoothState.unknown] initially)
  BluetoothState get currentState;
  
  /// Platform capabilities
  Capabilities get capabilities;
  
  /// Ensure Bluetooth is ready to use
  /// 
  /// Throws [BluetoothUnavailableException] if Bluetooth cannot be enabled.
  /// Throws [PermissionDeniedException] if permissions are not granted.
  Future<void> ensureReady();
  
  /// Request the user to enable Bluetooth
  /// 
  /// Returns true if Bluetooth was enabled, false if user declined.
  /// Throws [UnsupportedOperationException] on platforms that don't support this.
  Future<bool> requestEnable();
  
  /// Open system Bluetooth settings
  Future<void> openSettings();
  
  /// Scan for nearby BLE devices
  /// 
  /// Returns a stream of discovered [Device]s. The stream completes when
  /// scanning stops (timeout, [ScanHandle.stop], or error).
  /// 
  /// Example:
  /// ```dart
  /// await for (final device in bluey.scan()) {
  ///   print('Found: ${device.name}');
  /// }
  /// ```
  ScanStream scan({
    List<UUID>? services,
    Duration? timeout,
    ScanMode mode = ScanMode.balanced,
  });
  
  /// Create a GATT server for peripheral role
  /// 
  /// Returns null on platforms that don't support peripheral role.
  Server? server();
  
  /// Release all resources
  /// 
  /// After calling dispose, this instance cannot be used.
  Future<void> dispose();
}
```

### Scanning API

```dart
/// A stream of discovered devices with scan control
abstract class ScanStream extends Stream<Device> {
  /// Stop scanning
  Future<void> stop();
  
  /// Whether scanning is currently active
  bool get isScanning;
}

/// Scan mode affects power usage and latency
enum ScanMode {
  /// Balanced power and latency (default)
  balanced,
  
  /// Lower latency, higher power usage
  lowLatency,
  
  /// Lower power usage, higher latency
  lowPower,
}

/// A discovered BLE device
@immutable
class Device {
  /// Unique identifier (platform-specific format)
  final UUID id;
  
  /// Advertised device name, if available
  final String? name;
  
  /// Signal strength in dBm (typically -30 to -100)
  final int rssi;
  
  /// Full advertisement data
  final Advertisement advertisement;
  
  /// When this device was last seen
  final DateTime lastSeen;
  
  /// Connect to this device
  /// 
  /// Returns a [Connection] for GATT operations.
  /// Throws [ConnectionException] if connection fails.
  Future<Connection> connect({
    Duration timeout = const Duration(seconds: 10),
    int? mtu,
    ConnectionPriority priority = ConnectionPriority.balanced,
  });
  
  @override
  bool operator ==(Object other) => other is Device && other.id == id;
  
  @override
  int get hashCode => id.hashCode;
}
```

### Connection API

```dart
/// An active connection to a BLE device
abstract class Connection {
  /// The connected device's ID
  UUID get deviceId;
  
  /// Current connection state
  ConnectionState get state;
  
  /// Stream of connection state changes
  Stream<ConnectionState> get stateChanges;
  
  /// Current MTU (maximum transmission unit)
  int get mtu;
  
  /// Get a service by UUID
  /// 
  /// Services are discovered lazily on first access.
  /// Throws [ServiceNotFoundException] if not found.
  RemoteService service(UUID uuid);
  
  /// Get all services
  /// 
  /// Triggers service discovery if not already done.
  Future<List<RemoteService>> get services;
  
  /// Check if a service exists
  Future<bool> hasService(UUID uuid);
  
  /// Request a specific MTU
  /// 
  /// Returns the negotiated MTU (may be different from requested).
  Future<int> requestMtu(int mtu);
  
  /// Read the current RSSI
  Future<int> readRssi();
  
  /// Disconnect from the device
  Future<void> disconnect();
}

/// A service on a connected device
abstract class RemoteService {
  UUID get uuid;
  
  /// Get a characteristic by UUID
  RemoteCharacteristic characteristic(UUID uuid);
  
  /// All characteristics in this service
  List<RemoteCharacteristic> get characteristics;
  
  /// Included services
  List<RemoteService> get includedServices;
}

/// A characteristic on a connected device
abstract class RemoteCharacteristic {
  UUID get uuid;
  
  /// Characteristic properties
  CharacteristicProperties get properties;
  
  /// Read the current value
  /// 
  /// Throws [GattException] if read fails or not supported.
  Future<Uint8List> read();
  
  /// Write a value
  /// 
  /// Set [withResponse] to false for write-without-response.
  /// Throws [GattException] if write fails or not supported.
  Future<void> write(Uint8List value, {bool withResponse = true});
  
  /// Stream of notification/indication values
  /// 
  /// Subscribing to this stream enables notifications.
  /// Unsubscribing disables notifications.
  Stream<Uint8List> get notifications;
  
  /// Get a descriptor by UUID
  RemoteDescriptor descriptor(UUID uuid);
  
  /// All descriptors
  List<RemoteDescriptor> get descriptors;
}

/// A descriptor on a connected device
abstract class RemoteDescriptor {
  UUID get uuid;
  
  Future<Uint8List> read();
  Future<void> write(Uint8List value);
}
```

### Server API (Peripheral Role)

```dart
/// GATT server for peripheral role
abstract class Server {
  /// Whether advertising is currently active
  bool get isAdvertising;
  
  /// Stream of connected central devices
  Stream<Central> get connections;
  
  /// Currently connected centrals
  List<Central> get connectedCentrals;
  
  /// Add a service to the GATT database
  /// 
  /// Must be called before [startAdvertising].
  void addService(LocalService service);
  
  /// Remove a service by UUID
  /// 
  /// Cannot be called while advertising.
  void removeService(UUID uuid);
  
  /// Start advertising
  /// 
  /// Throws [AdvertisingException] if advertising fails.
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  });
  
  /// Stop advertising
  Future<void> stopAdvertising();
  
  /// Send a notification to all subscribed centrals
  /// 
  /// Returns after the notification is sent (with flow control).
  Future<void> notify(UUID characteristic, {required Uint8List data});
  
  /// Send a notification to a specific central
  Future<void> notifyTo(
    Central central,
    UUID characteristic, {
    required Uint8List data,
  });
  
  /// Dispose the server and release resources
  Future<void> dispose();
}

/// A connected central device (from server perspective)
abstract class Central {
  UUID get id;
  int get mtu;
  
  /// Disconnect this central
  Future<void> disconnect();
}

/// Service definition for the GATT server
class LocalService {
  final UUID uuid;
  final bool isPrimary;
  final List<LocalCharacteristic> characteristics;
  final List<LocalService> includedServices;
  
  const LocalService({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
    this.includedServices = const [],
  });
}

/// Characteristic definition for the GATT server
class LocalCharacteristic {
  final UUID uuid;
  final CharacteristicProperties properties;
  final List<GattPermission> permissions;
  final ReadHandler? onRead;
  final WriteHandler? onWrite;
  final List<LocalDescriptor> descriptors;
  
  const LocalCharacteristic({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.onRead,
    this.onWrite,
    this.descriptors = const [],
  });
  
  /// Create a read-only characteristic
  factory LocalCharacteristic.readable({
    required UUID uuid,
    required ReadHandler onRead,
  });
  
  /// Create a writable characteristic
  factory LocalCharacteristic.writable({
    required UUID uuid,
    required WriteHandler onWrite,
  });
  
  /// Create a notifiable characteristic
  factory LocalCharacteristic.notifiable({
    required UUID uuid,
  });
}

/// Handler for read requests
typedef ReadHandler = FutureOr<Uint8List> Function(Central central);

/// Handler for write requests
typedef WriteHandler = FutureOr<GattStatus> Function(
  Central central,
  Uint8List value,
);

/// GATT operation status codes
enum GattStatus {
  success,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  invalidAttributeLength,
  insufficientAuthentication,
  insufficientEncryption,
  requestNotSupported,
}
```

---

## Platform Abstraction

### Platform Interface

```dart
/// Platform-specific implementation interface
/// 
/// Each platform (Android, iOS, etc.) implements this interface.
/// The core Bluey library delegates to the registered implementation.
abstract class BlueyPlatform {
  /// Register a platform implementation
  static set instance(BlueyPlatform value);
  
  /// Get the registered implementation
  static BlueyPlatform get instance;
  
  /// Platform capabilities
  Capabilities get capabilities;
  
  // === State ===
  
  Stream<BluetoothState> get stateStream;
  Future<BluetoothState> getState();
  Future<bool> requestEnable();
  Future<void> openSettings();
  
  // === Scanning ===
  
  Stream<PlatformDevice> scan(PlatformScanConfig config);
  Future<void> stopScan();
  
  // === Connection ===
  
  Future<PlatformConnection> connect(
    String deviceId,
    PlatformConnectConfig config,
  );
  Future<void> disconnect(String deviceId);
  
  // === GATT Client ===
  
  Future<List<PlatformService>> discoverServices(String deviceId);
  Future<Uint8List> readCharacteristic(String deviceId, int handle);
  Future<void> writeCharacteristic(
    String deviceId,
    int handle,
    Uint8List value,
    bool withResponse,
  );
  Future<void> setNotification(String deviceId, int handle, bool enable);
  Stream<PlatformNotification> get notificationStream;
  
  // === GATT Server ===
  
  Future<void> addService(PlatformServiceDefinition service);
  Future<void> removeService(String uuid);
  Future<void> startAdvertising(PlatformAdvertiseConfig config);
  Future<void> stopAdvertising();
  Future<void> sendNotification(
    String characteristicUuid,
    Uint8List value,
    String? centralId,
  );
  Stream<PlatformGattRequest> get gattRequestStream;
  Future<void> respondToRequest(int requestId, GattStatus status, Uint8List? value);
  
  // === Lifecycle ===
  
  Future<void> dispose();
}
```

### Capabilities

```dart
/// Platform capability matrix
class Capabilities {
  /// Whether scanning is supported
  final bool canScan;
  
  /// Whether connecting to devices is supported
  final bool canConnect;
  
  /// Whether peripheral (server) role is supported
  final bool canAdvertise;
  
  /// Whether MTU negotiation is supported
  final bool canRequestMtu;
  
  /// Maximum supported MTU
  final int maxMtu;
  
  /// Whether background scanning is supported
  final bool canScanInBackground;
  
  /// Whether background peripheral role is supported
  final bool canAdvertiseInBackground;
  
  /// Whether pairing/bonding is supported
  final bool canBond;
  
  /// Whether Bluetooth can be enabled programmatically
  final bool canRequestEnable;
  
  const Capabilities({
    this.canScan = true,
    this.canConnect = true,
    this.canAdvertise = false,
    this.canRequestMtu = false,
    this.maxMtu = 23,
    this.canScanInBackground = false,
    this.canAdvertiseInBackground = false,
    this.canBond = false,
    this.canRequestEnable = false,
  });
  
  /// Android capabilities
  static const android = Capabilities(
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
    canBond: true,
    canRequestEnable: true,
  );
  
  /// iOS capabilities
  static const iOS = Capabilities(
    canAdvertise: true,
    maxMtu: 185,
    canScanInBackground: true,
    canAdvertiseInBackground: true,
  );
  
  /// macOS capabilities
  static const macOS = Capabilities(
    canAdvertise: true,
    maxMtu: 185,
  );
  
  /// Windows capabilities
  static const windows = Capabilities(
    canRequestMtu: true,
    maxMtu: 517,
  );
  
  /// Linux capabilities
  static const linux = Capabilities(
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
  );
}
```

### Platform Implementation Pattern

```dart
// === Android Implementation ===

class BlueyAndroid extends BlueyPlatform {
  final _api = BlueyAndroidApi(); // Pigeon-generated
  
  @override
  Capabilities get capabilities => Capabilities.android;
  
  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final controller = StreamController<PlatformDevice>();
    
    _api.startScan(config.toApi()).then((_) {
      // Scanning started
    }).catchError((e) {
      controller.addError(e);
      controller.close();
    });
    
    _scanSubscription = _api.scanResults.listen(
      (result) => controller.add(result.toPlatform()),
      onError: controller.addError,
      onDone: controller.close,
    );
    
    return controller.stream;
  }
  
  // ... other implementations
}

// === Registration ===

// In bluey_android/lib/bluey_android.dart
class BlueyAndroidPlugin {
  static void registerWith() {
    BlueyPlatform.instance = BlueyAndroid();
  }
}
```

---

## Error Handling

### Exception Hierarchy

```dart
/// Base class for all Bluey exceptions
sealed class BlueyException implements Exception {
  final String message;
  final String? action; // Suggested action to resolve
  final Object? cause;  // Underlying error
  
  const BlueyException(this.message, {this.action, this.cause});
  
  @override
  String toString() => 'BlueyException: $message';
}

// === State Exceptions ===

/// Bluetooth is not available on this device
class BluetoothUnavailableException extends BlueyException {
  const BluetoothUnavailableException()
    : super(
        'Bluetooth is not available on this device',
        action: 'This device does not support Bluetooth LE',
      );
}

/// Bluetooth is turned off
class BluetoothDisabledException extends BlueyException {
  const BluetoothDisabledException()
    : super(
        'Bluetooth is turned off',
        action: 'Call bluey.requestEnable() or direct user to Settings',
      );
}

/// Required permissions not granted
class PermissionDeniedException extends BlueyException {
  final List<String> permissions;
  
  const PermissionDeniedException(this.permissions)
    : super(
        'Required permissions not granted: ${permissions.join(", ")}',
        action: 'Request permissions or direct user to Settings',
      );
}

// === Connection Exceptions ===

/// Failed to connect to device
class ConnectionException extends BlueyException {
  final UUID deviceId;
  final ConnectionFailureReason reason;
  
  const ConnectionException(this.deviceId, this.reason)
    : super('Failed to connect to device: $reason');
}

enum ConnectionFailureReason {
  timeout,
  deviceNotFound,
  deviceNotConnectable,
  pairingFailed,
  connectionLimitReached,
  unknown,
}

/// Connection was lost unexpectedly
class DisconnectedException extends BlueyException {
  final UUID deviceId;
  final DisconnectReason reason;
  
  const DisconnectedException(this.deviceId, this.reason)
    : super('Device disconnected: $reason');
}

enum DisconnectReason {
  requested,         // disconnect() was called
  remoteDisconnect,  // Remote device disconnected
  linkLoss,          // Connection lost (out of range, etc.)
  timeout,           // Operation timeout
  unknown,
}

// === GATT Exceptions ===

/// Service not found on device
class ServiceNotFoundException extends BlueyException {
  final UUID serviceUuid;
  
  const ServiceNotFoundException(this.serviceUuid)
    : super('Service not found: $serviceUuid');
}

/// Characteristic not found in service
class CharacteristicNotFoundException extends BlueyException {
  final UUID characteristicUuid;
  
  const CharacteristicNotFoundException(this.characteristicUuid)
    : super('Characteristic not found: $characteristicUuid');
}

/// GATT operation failed
class GattException extends BlueyException {
  final GattStatus status;
  
  const GattException(this.status)
    : super('GATT operation failed: $status');
}

/// Operation not supported by this characteristic
class OperationNotSupportedException extends BlueyException {
  final String operation; // 'read', 'write', 'notify'
  
  const OperationNotSupportedException(this.operation)
    : super(
        'Operation "$operation" not supported by this characteristic',
        action: 'Check characteristic properties before calling',
      );
}

// === Server Exceptions ===

/// Failed to start advertising
class AdvertisingException extends BlueyException {
  final AdvertisingFailureReason reason;
  
  const AdvertisingException(this.reason)
    : super('Failed to start advertising: $reason');
}

enum AdvertisingFailureReason {
  alreadyAdvertising,
  dataTooBig,
  notSupported,
  hardwareError,
  unknown,
}

// === Platform Exceptions ===

/// Operation not supported on this platform
class UnsupportedOperationException extends BlueyException {
  final String operation;
  final String platform;
  
  const UnsupportedOperationException(this.operation, this.platform)
    : super(
        'Operation "$operation" is not supported on $platform',
        action: 'Check bluey.capabilities before calling',
      );
}
```

### Error Handling Patterns

```dart
// === Pattern 1: Check capabilities first ===

if (bluey.capabilities.canRequestMtu) {
  final mtu = await connection.requestMtu(512);
  print('MTU: $mtu');
} else {
  print('MTU negotiation not supported, using default');
}

// === Pattern 2: Catch specific exceptions ===

try {
  await device.connect();
} on BluetoothDisabledException {
  final enabled = await bluey.requestEnable();
  if (enabled) {
    await device.connect(); // Retry
  }
} on ConnectionException catch (e) {
  if (e.reason == ConnectionFailureReason.timeout) {
    showError('Connection timed out. Make sure device is nearby.');
  }
}

// === Pattern 3: Handle disconnection gracefully ===

connection.stateChanges.listen((state) {
  if (state == ConnectionState.disconnected) {
    cleanupUI();
    // Optionally reconnect
  }
});

// === Pattern 4: Stream error handling ===

characteristic.notifications
  .handleError((error) {
    if (error is DisconnectedException) {
      // Expected during disconnect
      return;
    }
    logError(error);
  })
  .listen((value) {
    updateUI(value);
  });
```

---

## Testing Strategy

### Test Doubles

```dart
/// Mock implementation for testing
class MockBluey implements Bluey {
  final _stateController = StreamController<BluetoothState>.broadcast();
  final List<Device> _mockDevices = [];
  
  BluetoothState _state = BluetoothState.on;
  
  @override
  Stream<BluetoothState> get state => _stateController.stream;
  
  @override
  BluetoothState get currentState => _state;
  
  /// Set the mock Bluetooth state
  void setMockState(BluetoothState state) {
    _state = state;
    _stateController.add(state);
  }
  
  /// Add a mock device to be discovered
  void addMockDevice(Device device) {
    _mockDevices.add(device);
  }
  
  @override
  ScanStream scan({...}) {
    return MockScanStream(_mockDevices);
  }
  
  // ... other mock implementations
}

/// Mock connection for testing GATT operations
class MockConnection implements Connection {
  final Map<UUID, MockRemoteService> _services = {};
  final _stateController = StreamController<ConnectionState>.broadcast();
  
  ConnectionState _state = ConnectionState.connected;
  
  /// Add a mock service
  void addMockService(MockRemoteService service) {
    _services[service.uuid] = service;
  }
  
  @override
  RemoteService service(UUID uuid) {
    return _services[uuid] ?? (throw ServiceNotFoundException(uuid));
  }
  
  // ... other mock implementations
}
```

### Testing Patterns

```dart
// === Unit Test: Scanning ===

void main() {
  group('Scanning', () {
    late MockBluey bluey;
    
    setUp(() {
      bluey = MockBluey();
    });
    
    test('emits discovered devices', () async {
      final device = Device(
        id: UUID('test-device'),
        name: 'Test',
        rssi: -50,
        advertisement: Advertisement.empty(),
      );
      bluey.addMockDevice(device);
      
      final devices = await bluey.scan().toList();
      
      expect(devices, contains(device));
    });
    
    test('throws when Bluetooth is off', () async {
      bluey.setMockState(BluetoothState.off);
      
      expect(
        () => bluey.scan().first,
        throwsA(isA<BluetoothDisabledException>()),
      );
    });
  });
}

// === Integration Test: Real Device ===

void main() {
  group('Integration', () {
    late Bluey bluey;
    
    setUpAll(() async {
      bluey = Bluey();
      await bluey.ensureReady();
    });
    
    tearDownAll(() async {
      await bluey.dispose();
    });
    
    test('can scan and connect', () async {
      // Find a device
      final device = await bluey.scan(
        services: [heartRateServiceUUID],
        timeout: Duration(seconds: 10),
      ).first;
      
      // Connect
      final connection = await device.connect();
      expect(connection.state, ConnectionState.connected);
      
      // Read a value
      final batteryLevel = await connection
        .service(batteryServiceUUID)
        .characteristic(batteryLevelUUID)
        .read();
      
      expect(batteryLevel.length, 1);
      expect(batteryLevel[0], inInclusiveRange(0, 100));
      
      // Cleanup
      await connection.disconnect();
    }, timeout: Timeout(Duration(minutes: 1)));
  });
}

// === Widget Test with Mock ===

void main() {
  testWidgets('shows device list', (tester) async {
    final mockBluey = MockBluey();
    mockBluey.addMockDevice(Device(
      id: UUID('device-1'),
      name: 'Heart Rate Monitor',
      rssi: -60,
      advertisement: Advertisement.empty(),
    ));
    
    await tester.pumpWidget(
      BlueyProvider(
        bluey: mockBluey,
        child: DeviceListScreen(),
      ),
    );
    
    // Trigger scan
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    
    // Verify device appears
    expect(find.text('Heart Rate Monitor'), findsOneWidget);
  });
}
```

### Simulated Devices

```dart
/// Simulated heart rate monitor for testing
class SimulatedHeartRateMonitor {
  late final MockConnection _connection;
  Timer? _notificationTimer;
  int _heartRate = 72;
  
  SimulatedHeartRateMonitor() {
    _connection = MockConnection();
    
    final heartRateChar = MockRemoteCharacteristic(
      uuid: heartRateMeasurementUUID,
      properties: CharacteristicProperties(canNotify: true),
    );
    
    heartRateChar.onNotificationSubscribed = () {
      _notificationTimer = Timer.periodic(
        Duration(seconds: 1),
        (_) {
          // Simulate realistic heart rate variation
          _heartRate += Random().nextInt(5) - 2;
          _heartRate = _heartRate.clamp(60, 100);
          
          heartRateChar.emitNotification(
            Uint8List.fromList([0x00, _heartRate]),
          );
        },
      );
    };
    
    heartRateChar.onNotificationUnsubscribed = () {
      _notificationTimer?.cancel();
    };
    
    _connection.addMockService(MockRemoteService(
      uuid: heartRateServiceUUID,
      characteristics: [heartRateChar],
    ));
  }
  
  Connection get connection => _connection;
}
```

---

## Migration Path

### From bluetooth_low_energy to Bluey

```dart
// === BEFORE (bluetooth_low_energy) ===

final centralManager = CentralManager();

// Check state
final state = await centralManager.getState();
if (state != BluetoothLowEnergyState.on) {
  await centralManager.authorize();
}

// Scan
centralManager.stateChanged.listen((event) { ... });
await centralManager.startDiscovery();

centralManager.discovered.listen((event) {
  final peripheral = event.peripheral;
  final rssi = event.rssi;
  
  // Connect
  await centralManager.connect(peripheral);
  
  // Discover services
  final services = await centralManager.discoverServices(peripheral);
  
  // Find characteristic
  final service = services.firstWhere((s) => s.uuid == serviceUUID);
  final char = service.characteristics.firstWhere((c) => c.uuid == charUUID);
  
  // Read
  final value = await centralManager.readCharacteristic(char);
  
  // Subscribe
  await centralManager.setCharacteristicNotifyState(char, state: true);
  centralManager.characteristicNotified.listen((event) {
    if (event.characteristic == char) {
      final value = event.value;
    }
  });
});

// === AFTER (Bluey) ===

final bluey = Bluey();

// Check state (simpler)
await bluey.ensureReady(); // Handles auth, state check

// Scan (stream-based)
await for (final device in bluey.scan(services: [serviceUUID])) {
  // Connect (on device, not manager)
  final connection = await device.connect();
  
  // Read (no discover step, fluent API)
  final value = await connection
    .service(serviceUUID)
    .characteristic(charUUID)
    .read();
  
  // Subscribe (just use the stream)
  await for (final value in connection
    .service(serviceUUID)
    .characteristic(charUUID)
    .notifications) {
    // Handle notification
  }
}
```

### Migration Checklist

1. **Replace Managers with Bluey**
   - `CentralManager()` → `Bluey()`
   - `PeripheralManager()` → `bluey.server()`

2. **Replace Event Streams**
   - `discovered.listen()` → `await for (final device in scan())`
   - `stateChanged.listen()` → `state.listen()`
   - `characteristicNotified.listen()` → `characteristic.notifications.listen()`

3. **Simplify Connection Flow**
   - Remove explicit `discoverServices()` calls
   - Access services directly via `connection.service(uuid)`

4. **Update Error Handling**
   - Replace generic exceptions with typed Bluey exceptions
   - Use capability checks instead of catching `UnsupportedError`

5. **Update Peripheral Role**
   - Replace `GATTService`/`GATTCharacteristic` constructors with builders
   - Use `LocalService`/`LocalCharacteristic` for server definitions

---

## Package Structure

The initial release targets Android and iOS only. Desktop platforms (macOS, Windows, Linux) will be added in future releases.

```
bluey/                              # Main package (facade)
├── lib/
│   ├── bluey.dart                  # Public API exports
│   └── src/
│       ├── bluey.dart              # Main Bluey class
│       ├── device.dart             # Device, Advertisement
│       ├── connection.dart         # Connection, RemoteService, etc.
│       ├── server.dart             # Server, LocalService, etc.
│       ├── uuid.dart               # UUID class
│       └── exceptions.dart         # Exception hierarchy
├── example/                        # Cross-platform example app
│   ├── lib/
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
├── test/
│   ├── bluey_test.dart
│   ├── connection_test.dart
│   └── mocks/
│       └── mock_bluey.dart
└── pubspec.yaml

bluey_platform_interface/           # Platform abstraction
├── lib/
│   ├── bluey_platform_interface.dart
│   └── src/
│       ├── platform_interface.dart # BlueyPlatform abstract class
│       ├── capabilities.dart       # Platform capabilities
│       └── types/                  # Platform-level types
│           ├── platform_device.dart
│           ├── platform_connection.dart
│           └── ...
└── pubspec.yaml

bluey_android/                      # Android implementation
├── lib/
│   ├── bluey_android.dart
│   └── src/
│       ├── bluey_android.dart      # BlueyAndroid implementation
│       └── api.g.dart              # Pigeon-generated
├── android/
│   └── src/main/kotlin/
│       └── com/example/bluey/
│           ├── BlueyPlugin.kt
│           ├── Scanner.kt
│           ├── Connection.kt
│           └── Server.kt
├── pigeons/
│   └── api.dart                    # Pigeon definition
└── pubspec.yaml

bluey_ios/                          # iOS implementation
├── lib/
│   ├── bluey_ios.dart
│   └── src/
│       ├── bluey_ios.dart
│       └── api.g.dart
├── ios/Classes/
│   ├── BlueyPlugin.swift
│   ├── Scanner.swift
│   ├── Connection.swift
│   └── Server.swift
├── pigeons/
│   └── api.dart
└── pubspec.yaml

# Future packages (post-1.0):
# bluey_macos/                      # macOS implementation
# bluey_windows/                    # Windows implementation  
# bluey_linux/                      # Linux implementation
```

---

## Example App

The example app lives at `bluey/example/` and serves as both documentation and validation of the API design.

### Structure

```
bluey/
└── example/
    ├── lib/
    │   ├── main.dart
    │   ├── app.dart
    │   ├── router.dart
    │   │
    │   ├── features/
    │   │   ├── scanner/
    │   │   │   ├── scanner_screen.dart
    │   │   │   └── scanner_view_model.dart
    │   │   │
    │   │   ├── connection/
    │   │   │   ├── connection_screen.dart
    │   │   │   ├── service_screen.dart
    │   │   │   ├── characteristic_screen.dart
    │   │   │   └── connection_view_model.dart
    │   │   │
    │   │   └── server/
    │   │       ├── server_screen.dart
    │   │       └── server_view_model.dart
    │   │
    │   ├── widgets/
    │   │   ├── device_card.dart
    │   │   ├── service_card.dart
    │   │   ├── characteristic_tile.dart
    │   │   ├── value_display.dart
    │   │   └── bluetooth_state_banner.dart
    │   │
    │   └── utils/
    │       ├── uuid_names.dart          # Friendly names for well-known UUIDs
    │       └── hex_formatter.dart
    │
    ├── android/
    ├── ios/
    ├── macos/
    ├── windows/
    ├── linux/
    └── pubspec.yaml
```

### Features to Demonstrate

#### 1. Scanner Feature

- Start/stop scanning with visual feedback
- Filter by service UUIDs
- Display device name, RSSI signal strength indicator
- Show advertisement data (service UUIDs, manufacturer data)
- Tap to connect

#### 2. Connection Feature

- Connection state visualization (connecting, connected, disconnected)
- Automatic service discovery display
- Drill-down navigation: Device → Service → Characteristic
- For each characteristic:
  - Read value (with hex/text toggle)
  - Write value (with hex/text input)
  - Subscribe/unsubscribe to notifications
  - Real-time notification log
- Descriptor viewing
- MTU display and negotiation (where supported)
- RSSI reading
- Graceful disconnection handling

#### 3. Server Feature

- Define and publish custom services
- Start/stop advertising
- Display connected centrals
- Send notifications with flow control feedback
- Handle read/write requests with logging

### Design Principles for the Example

1. **Showcase the API**: Every major Bluey API should be exercised and visible
2. **Real-world patterns**: Demonstrate proper error handling, reconnection, and lifecycle management
3. **Clean code**: The example itself follows DDD/CA principles with ViewModels
4. **Cross-platform**: Single codebase runs on all supported platforms
5. **Accessible**: Clear UI that helps developers understand BLE concepts

### Example Code Snippets

The example should include inline comments showing idiomatic usage:

```dart
// scanner_view_model.dart
class ScannerViewModel extends ChangeNotifier {
  final Bluey _bluey;
  final List<Device> _devices = [];
  bool _isScanning = false;
  StreamSubscription? _scanSubscription;

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;

  Future<void> startScan() async {
    // Ensure Bluetooth is ready before scanning
    await _bluey.ensureReady();
    
    _devices.clear();
    _isScanning = true;
    notifyListeners();

    // Scan returns a stream - devices arrive as discovered
    _scanSubscription = _bluey.scan(
      timeout: const Duration(seconds: 30),
    ).listen(
      (device) {
        // Update existing device or add new one
        final index = _devices.indexWhere((d) => d.id == device.id);
        if (index >= 0) {
          _devices[index] = device;
        } else {
          _devices.add(device);
        }
        notifyListeners();
      },
      onDone: () {
        _isScanning = false;
        notifyListeners();
      },
      onError: (error) {
        _isScanning = false;
        notifyListeners();
        // Handle error appropriately
      },
    );
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _isScanning = false;
    notifyListeners();
  }
}
```

```dart
// characteristic_screen.dart (excerpt)
class _CharacteristicScreenState extends State<CharacteristicScreen> {
  final List<LogEntry> _log = [];
  StreamSubscription? _notificationSub;

  Future<void> _read() async {
    try {
      final value = await widget.characteristic.read();
      _addLog('Read', value);
    } on GattException catch (e) {
      _addLog('Read failed', null, error: e.message);
    }
  }

  Future<void> _subscribe() async {
    // Simply listening to the stream enables notifications
    _notificationSub = widget.characteristic.notifications.listen(
      (value) => _addLog('Notify', value),
      onError: (e) => _addLog('Notify error', null, error: e.toString()),
    );
    setState(() {});
  }

  Future<void> _unsubscribe() async {
    // Canceling the subscription disables notifications
    await _notificationSub?.cancel();
    _notificationSub = null;
    setState(() {});
  }
}
```

---

## Implementation Roadmap

### Phase 1: Core Domain 🚧 IN PROGRESS

Complete the entire domain layer before platform implementations.

**Foundation (Complete):**
- [x] Define public API interfaces (Bluey facade class)
- [x] Implement UUID class with full test coverage
- [x] Implement Device entity and Advertisement/ManufacturerData value objects
- [x] Create exception hierarchy (sealed BlueyException with subclasses)
- [x] Set up platform interface package (BlueyPlatform, Capabilities, DTOs)
- [x] Define Pigeon API contracts

**GATT Client Domain (Complete):**
- [x] ConnectionState enum with isActive, isConnected getters
- [x] BluetoothState enum with isReady, canBeEnabled getters
- [x] CharacteristicProperties value object with fromFlags
- [x] Connection abstract class (aggregate root)
- [x] RemoteService, RemoteCharacteristic, RemoteDescriptor interfaces
- [x] ScanStream abstract class and ScanMode enum
- [x] Bluey facade with scan/connect/state/currentState

**Server Domain (Peripheral Role):**
- [ ] Server abstract class (aggregate root for peripheral role)
- [ ] Central class (connected central device)
- [ ] LocalService, LocalCharacteristic, LocalDescriptor classes
- [ ] GattPermission enum
- [ ] ReadHandler/WriteHandler typedefs
- [ ] Well-known UUIDs (Services, Characteristics, Descriptors classes)

**Test Coverage:** 156 unit tests passing

### Phase 2: Android Implementation

Complete Android platform with full GATT client and server support.

**Setup (Complete):**
- [x] Set up bluey_android package with Pigeon code generation
- [x] Implement BlueyAndroid platform class (Dart side)
- [x] Implement BlueyPlugin (Kotlin - FlutterPlugin, ActivityAware)

**Scanning & Connection (Complete):**
- [x] Implement Scanner (Kotlin - BluetoothLeScanner integration)
- [x] Implement ConnectionManager (Kotlin - BluetoothGatt integration)

**GATT Client:**
- [ ] Implement Bluetooth state monitoring (BroadcastReceiver)
- [ ] Implement service discovery
- [ ] Implement characteristic read/write
- [ ] Implement notifications/indications
- [ ] Implement descriptor read/write
- [ ] Implement MTU negotiation
- [ ] Implement RSSI reading

**Server (Peripheral Role):**
- [ ] Implement BluetoothGattServer integration
- [ ] Implement advertising (BluetoothLeAdvertiser)
- [ ] Implement read/write request handling
- [ ] Implement notification sending

**Testing:**
- [ ] Unit tests for all components
- [ ] Integration tests on real devices

### Phase 3: Example App

Validate the Android implementation with a complete example app.

- [x] Create example app scaffold (bluey/example)
- [ ] Implement scanner screen with device list
- [ ] Implement connection screen with state display
- [ ] Implement GATT explorer (services/characteristics/descriptors)
- [ ] Implement characteristic read/write UI
- [ ] Implement notification subscription UI
- [ ] Implement server demo (advertising as peripheral)
- [ ] Material Design 3 theming

### Phase 4: iOS Implementation

Mirror the Android implementation for iOS.

- [ ] Set up bluey_ios package with Pigeon code generation
- [ ] Implement BlueyIOS platform class (Dart side)
- [ ] Implement Swift plugin (CBCentralManager integration)
- [ ] Implement scanning
- [ ] Implement connection management
- [ ] Implement GATT client operations (read/write/notify)
- [ ] Implement CBPeripheralManager for server role
- [ ] Integration tests on real devices

### Phase 5: Documentation & Release

- [ ] Comprehensive API documentation
- [ ] Migration guide from bluetooth_low_energy
- [ ] Performance optimization
- [ ] Publish to pub.dev

### Future Phases (Post-1.0)

- [ ] macOS implementation
- [ ] Windows implementation
- [ ] Linux implementation (BlueZ D-Bus)
- [ ] Platform capability documentation for desktop

---

## Appendix: Well-Known UUIDs

```dart
/// Standard Bluetooth SIG service UUIDs
class Services {
  static const genericAccess = UUID.short(0x1800);
  static const genericAttribute = UUID.short(0x1801);
  static const immediateAlert = UUID.short(0x1802);
  static const linkLoss = UUID.short(0x1803);
  static const txPower = UUID.short(0x1804);
  static const currentTime = UUID.short(0x1805);
  static const healthThermometer = UUID.short(0x1809);
  static const deviceInformation = UUID.short(0x180A);
  static const heartRate = UUID.short(0x180D);
  static const battery = UUID.short(0x180F);
  static const bloodPressure = UUID.short(0x1810);
  static const runningSpeedAndCadence = UUID.short(0x1814);
  static const cyclingSpeedAndCadence = UUID.short(0x1816);
  static const cyclingPower = UUID.short(0x1818);
  static const locationAndNavigation = UUID.short(0x1819);
  static const environmentalSensing = UUID.short(0x181A);
  static const fitnessMachine = UUID.short(0x1826);
}

/// Standard Bluetooth SIG characteristic UUIDs
class Characteristics {
  static const deviceName = UUID.short(0x2A00);
  static const appearance = UUID.short(0x2A01);
  static const batteryLevel = UUID.short(0x2A19);
  static const systemId = UUID.short(0x2A23);
  static const modelNumber = UUID.short(0x2A24);
  static const serialNumber = UUID.short(0x2A25);
  static const firmwareRevision = UUID.short(0x2A26);
  static const hardwareRevision = UUID.short(0x2A27);
  static const softwareRevision = UUID.short(0x2A28);
  static const manufacturerName = UUID.short(0x2A29);
  static const heartRateMeasurement = UUID.short(0x2A37);
  static const bodySensorLocation = UUID.short(0x2A38);
}

/// Standard Bluetooth SIG descriptor UUIDs
class Descriptors {
  static const characteristicExtendedProperties = UUID.short(0x2900);
  static const characteristicUserDescription = UUID.short(0x2901);
  static const clientCharacteristicConfiguration = UUID.short(0x2902);
  static const serverCharacteristicConfiguration = UUID.short(0x2903);
  static const characteristicPresentationFormat = UUID.short(0x2904);
}
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2026-01-30 | Claude | Initial architecture document |
| 0.2.0 | 2026-01-30 | Claude | Updated roadmap with Phase 1 complete, Phase 2 in progress |

---

*This document is a living specification. As implementation progresses, details may be refined based on practical learnings.*
