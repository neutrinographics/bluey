# Bluey - Modern BLE Library for Flutter

A clean, elegant Bluetooth Low Energy library for Flutter following Domain-Driven Design and Clean Architecture principles.

## 🎯 Project Status

**Phase 1: Core Foundation** ✅ COMPLETE  
**Phase 2: Android Platform** ✅ COMPLETE  
**Phase 3: iOS Platform** 🚧 PLANNED  

### Current Capabilities

- ✅ BLE scanning with filters
- ✅ Device discovery with advertisement data
- ✅ Connection management
- ✅ Bluetooth state monitoring
- ✅ Permission handling (Android 12+ and older)
- ✅ Type-safe platform channels (Pigeon)
- ✅ GATT operations (read/write/notify)
- ✅ Peripheral role (advertising)
- ✅ Server request/response handling
- ✅ Notifications and indications
- ✅ Bonding/pairing support
- ✅ PHY (Physical Layer) configuration
- ✅ Connection parameter control

## 📦 Packages

### Core Packages

- **`bluey/`** - Main library with domain models and public API
- **`bluey_platform_interface/`** - Platform abstraction layer
- **`bluey_android/`** - Android platform implementation (Kotlin)
- **`bluey_ios/`** - iOS platform implementation (Swift) - planned

### Example

- **`bluey/example/`** - Cross-platform example app demonstrating scanning and connection

## 🏗️ Architecture

### Clean Architecture Layers

```
┌─────────────────────────────────────────────────┐
│              Application Layer                  │  ← Example App
├─────────────────────────────────────────────────┤
│              Domain Layer                       │  ← bluey package
│  • UUID, Device, Advertisement (value objects)  │
│  • Exceptions (domain-specific)                 │
├─────────────────────────────────────────────────┤
│           Platform Interface                    │  ← bluey_platform_interface
│  • BlueyPlatform (abstract)                     │
│  • Platform types (DTOs)                        │
├─────────────────────────────────────────────────┤
│         Platform Implementations                │  ← bluey_android, bluey_ios
│  • Pigeon-generated bindings                    │
│  • Native code (Kotlin/Swift)                   │
└─────────────────────────────────────────────────┘
```

### Domain-Driven Design

**Value Objects (immutable, equality by value):**
- `UUID` - 128-bit Bluetooth UUID with short-form support
- `Device` - Snapshot of a discovered BLE device (equality by ID)
- `Advertisement` - Broadcast data from peripheral
- `ManufacturerData` - Manufacturer-specific data
- `Capabilities` - Platform feature matrix
- `ConnectionParameters` - BLE connection timing parameters
- `ReadRequest` / `WriteRequest` - GATT server request handling
- `Central` - Connected central device in peripheral role

**Enums:**
- `BondState` - Bonding state (none, bonding, bonded)
- `Phy` - Physical layer (le1m, le2m, leCoded)
- `GattResponseStatus` - GATT operation response codes

**Bounded Contexts:**
1. **Discovery Context** - Scanning and device discovery
2. **Connection Context** - Managing device connections, bonding, PHY
3. **GATT Client Context** - Service/characteristic operations
4. **GATT Server Context** - Peripheral role, request handling
5. **Platform Context** - Bluetooth state and permissions

## 🧪 Test-Driven Development

All code built following strict TDD:
- **Red**: Write failing test
- **Green**: Implement minimum code to pass
- **Refactor**: Improve while keeping tests green

### Test Coverage

| Package | Tests | Status |
|---------|-------|--------|
| bluey | 424 | ✅ All passing |
| bluey_platform_interface | 20 | ✅ All passing |
| bluey_android | 2 | ✅ All passing |
| **Total** | **446** | ✅ **All passing** |

## 🚀 Usage

### Installation

```yaml
dependencies:
  bluey:
    path: path/to/bluey
  bluey_android:
    path: path/to/bluey_android
```

### Register Platform

```dart
import 'package:bluey_android/bluey_android.dart';

void main() {
  BlueyAndroid.registerWith();
  runApp(MyApp());
}
```

### Configuration

Bluey provides configuration options to customize plugin behavior. Call `configure()` early in your app lifecycle.

```dart
import 'package:bluey/bluey.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final bluey = Bluey();
  
  // Configure plugin behavior (optional - defaults are sensible)
  await bluey.configure(
    cleanupOnActivityDestroy: true,  // Default: true
  );
  
  runApp(MyApp());
}
```

#### Configuration Options

| Option | Default | Platform | Description |
|--------|---------|----------|-------------|
| `cleanupOnActivityDestroy` | `true` | Android | Automatically clean up BLE resources when the activity is destroyed |

##### cleanupOnActivityDestroy (Android only)

When `true` (default), the plugin will automatically clean up BLE resources when the Android activity is destroyed:
- Stop advertising
- Close the GATT server  
- Disconnect all connected centrals

This prevents "zombie" BLE connections that persist after the app is closed, which can cause issues when the app is relaunched (battery drain, connection limits, unexpected behavior).

**When to disable:**
- If you need fine-grained control over when cleanup happens
- If you're handling cleanup manually in your app lifecycle callbacks
- If you have a specific use case that requires connections to persist

**If disabled, you are responsible for calling `server.dispose()` to clean up resources.**

```dart
// Disable automatic cleanup (you manage it manually)
await bluey.configure(cleanupOnActivityDestroy: false);

// Later, when you're done with the server:
await server.dispose();
```

**Note:** On iOS, the OS handles BLE cleanup automatically when the app is terminated, so this option has no effect.

### Scanning for Devices

```dart
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

final bluey = BlueyPlatform.instance;

// Check Bluetooth state
final state = await bluey.getState();
if (state != BluetoothState.on) {
  // Handle disabled Bluetooth
}

// Start scanning
final config = PlatformScanConfig(
  serviceUuids: [], // Filter by service UUIDs (empty = all)
  timeoutMs: 10000, // 10 second timeout
);

bluey.scan(config).listen(
  (device) {
    print('Found: ${device.name ?? "Unknown"} (${device.rssi} dBm)');
  },
  onDone: () => print('Scan complete'),
);
```

### Connecting to Device

```dart
import 'package:bluey/bluey.dart';

final bluey = Bluey();

// Connect to a device (returns a Connection object)
final connection = await bluey.connect(device);

// Listen to connection state changes
connection.stateChanges.listen((state) {
  print('Connection state: $state');
});

// Access GATT services (once connected)
final services = await connection.services;
final service = connection.service(UUID('0000180d-0000-1000-8000-00805f9b34fb'));

// Disconnect when done
await connection.disconnect();
```

### Peripheral Role (GATT Server)

```dart
import 'package:bluey/bluey.dart';

final bluey = Bluey();

// Create a server (peripheral)
final server = bluey.server();

// Add a service with characteristics
server.addService(
  LocalService(
    uuid: UUID('12345678-1234-1234-1234-123456789abc'),
    isPrimary: true,
    characteristics: [
      LocalCharacteristic(
        uuid: UUID('12345678-1234-1234-1234-123456789abd'),
        properties: CharacteristicProperties(
          canRead: true,
          canWrite: true,
          canNotify: true,
        ),
        permissions: [GattPermission.read, GattPermission.write],
      ),
    ],
  ),
);

// Start advertising
await server.startAdvertising(
  name: 'My Device',
  services: [UUID('12345678-1234-1234-1234-123456789abc')],
);

// Listen for central connections
server.connections.listen((central) {
  print('Central connected: ${central.id}');
});

// Send notifications to subscribed centrals
await server.notify(
  UUID('12345678-1234-1234-1234-123456789abd'),
  Uint8List.fromList([0x01, 0x02, 0x03]),
);

// IMPORTANT: Dispose when done to properly close connections
// This is especially important on Android to prevent zombie BLE connections
await server.dispose();
```

### Bonding/Pairing (Android-only)

Bonding, PHY, and connection parameters are Android-only — iOS does not expose
central-side APIs for these (per Apple's CoreBluetooth design). Access them
via `connection.android?` on connections; the accessor is `null` on iOS.

```dart
// Check bond state (null on iOS)
print('Bond state: ${connection.android?.bondState}'); // none, bonding, bonded

// Listen for bond state changes (no events on iOS)
connection.android?.bondStateChanges.listen((state) {
  print('Bond state changed: $state');
});

// Initiate bonding (no-op on iOS)
await connection.android?.bond();

// Remove bond (no-op on iOS)
await connection.android?.removeBond();

// Get all bonded devices
final bondedDevices = await bluey.bondedDevices;
for (final device in bondedDevices) {
  print('Bonded: ${device.name}');
}
```

### PHY (Physical Layer) Configuration (Android-only)

```dart
// Check current PHY (null on iOS)
print('TX PHY: ${connection.android?.txPhy}'); // le1m, le2m, leCoded
print('RX PHY: ${connection.android?.rxPhy}');

// Listen for PHY changes (no events on iOS)
connection.android?.phyChanges.listen((phy) {
  print('PHY changed - TX: ${phy.tx}, RX: ${phy.rx}');
});

// Request faster PHY (2 Mbps) for higher throughput
await connection.android?.requestPhy(txPhy: Phy.le2m, rxPhy: Phy.le2m);

// Request coded PHY for longer range
await connection.android?.requestPhy(txPhy: Phy.leCoded, rxPhy: Phy.leCoded);
```

### Connection Parameters (Android-only)

```dart
// Check current connection parameters (null on iOS)
final params = connection.android?.connectionParameters;
if (params != null) {
  print('Interval: ${params.interval.milliseconds}ms');
  print('Latency: ${params.latency.events}');
  print('Timeout: ${params.timeout.milliseconds}ms');
}

// Request faster connection parameters (lower latency)
await connection.android?.requestConnectionParameters(
  ConnectionParameters(
    interval: ConnectionInterval(7.5),  // Minimum interval for low latency
    latency: PeripheralLatency(0),      // No skipped events
    timeout: SupervisionTimeout(4000),  // 4 second timeout
  ),
);

// Request power-saving parameters
await connection.android?.requestConnectionParameters(
  ConnectionParameters(
    interval: ConnectionInterval(100), // Longer interval saves power
    latency: PeripheralLatency(4),     // Allow skipping 4 events
    timeout: SupervisionTimeout(6000), // Longer timeout
  ),
);
```

### Logging

Bluey emits structured log events from both the Dart domain layer and the
native (Android/iOS) sides. Events flow through a single broadcast stream
filtered by a level you set; setting the level also pushes the filter down
to the native side, so no Pigeon traffic is incurred for filtered events.

```dart
final bluey = Bluey();
bluey.setLogLevel(BlueyLogLevel.debug);
bluey.logEvents.listen((event) {
  print('${event.timestamp.toIso8601String()} '
        '[${event.level.name}] ${event.context}: ${event.message} '
        '${event.data}');
});
```

Levels: `trace`, `debug`, `info` (default), `warn`, `error`. Native logs
also tee to `Logcat` (Android) and `os_log` (iOS) for native-side debugging.

#### Server Cleanup

By default, Bluey automatically cleans up BLE resources when the Android activity is destroyed.
This prevents "zombie" connections that persist after the app closes.

If you need manual control, you can disable automatic cleanup (see [Configuration](#configuration))
and handle cleanup yourself:

```dart
// In your widget's dispose method
@override
void dispose() {
  _server?.dispose();  // Clean up BLE resources
  super.dispose();
}
```

## 🛠️ Implementation Details

### Android Platform

**Key Components:**

- **BlueyPlugin.kt** - Main plugin coordinating lifecycle
- **Scanner.kt** - BLE scanning with Android BluetoothLeScanner
- **ConnectionManager.kt** - GATT connection management

**Features:**
- Android 12+ permission handling (BLUETOOTH_SCAN, BLUETOOTH_CONNECT)
- Legacy permission support (ACCESS_FINE_LOCATION for Android < 12)
- Scan filtering by service UUIDs
- Connection timeout handling
- Resource cleanup on plugin detach

**Permissions Required:**

```xml
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android < 12 -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### Code Generation with Pigeon

Pigeon generates type-safe platform channel code:

```dart
// Define once in pigeons/messages.dart
class DeviceDto {
  final String id;
  final String? name;
  final int rssi;
  // ...
}

@HostApi()
abstract class BlueyHostApi {
  @async
  void startScan(ScanConfigDto config);
}
```

Generates:
- `lib/src/messages.g.dart` - Dart bindings
- `android/.../Messages.g.kt` - Kotlin bindings

No manual MethodChannel code needed!

## 📋 Design Principles

### 1. Ubiquitous Language

Consistent terminology across codebase:
- **Device** (not Peripheral)
- **Scan** (not Discovery)
- **Connection** (not Link)
- **Advertisement** (not ScanRecord)

### 2. Single Responsibility

Each class has one reason to change:
- `Scanner` - only handles scanning
- `ConnectionManager` - only handles connections
- `BlueyPlugin` - only coordinates lifecycle

### 3. Dependency Inversion

Platform implementations depend on abstractions:
- `BlueyAndroid implements BlueyPlatform`
- Domain layer has no platform dependencies
- Interfaces defined by domain needs, not platform capabilities

## 🎨 Example App

The example app demonstrates:
- ✅ Bluetooth state monitoring with visual indicator
- ✅ Start/stop scanning with timeout
- ✅ Device list with RSSI and service info
- ✅ Connection to discovered devices
- ✅ Material Design 3 UI

Run it:
```bash
cd bluey/example
flutter run
```

## 🔜 Roadmap

### Phase 3: iOS Platform (Next)
- [ ] Set up Pigeon for iOS
- [ ] Implement BlueyIOS platform class
- [ ] Implement Swift plugin with CoreBluetooth
- [ ] iOS scanner and connection manager
- [ ] Integration tests

### Phase 4: GATT Operations ✅ COMPLETE
- [x] Service discovery
- [x] Characteristic read/write
- [x] Notifications/indications
- [x] Descriptor operations
- [x] MTU negotiation

### Phase 5: Advanced Features ✅ COMPLETE
- [x] Peripheral role (advertising)
- [x] Bonding/pairing
- [x] PHY (Physical Layer) configuration
- [x] Connection parameter control
- [x] Server request/response handling
- [ ] Background operation support
- [ ] Connection pooling
- [ ] Reconnection strategies

### Phase 6: Desktop Platforms
- [ ] macOS support
- [ ] Windows support
- [ ] Linux support (BlueZ)

## 📚 Documentation

- [Architecture Document](BLUEY_ARCHITECTURE.md) - Comprehensive design documentation
- [Migration Guide](BLUEY_ARCHITECTURE.md#migration-path) - From bluetooth_low_energy

## 🤝 Contributing

This project follows:
- **TDD**: All features must have tests first
- **DDD**: Respect bounded contexts and domain model
- **Clean Architecture**: Dependencies point inward only

## 📄 License

[Your license here]

## 🙏 Acknowledgments

Built with inspiration from:
- Domain-Driven Design by Eric Evans
- Clean Architecture by Robert C. Martin
- The bluetooth_low_energy package (reference implementation)
