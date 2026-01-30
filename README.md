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
- ⏳ GATT operations (read/write/notify) - planned
- ⏳ Peripheral role (advertising) - planned

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
- `Device` - Discovered BLE device (entity with ID-based equality)
- `Advertisement` - Broadcast data from peripheral
- `ManufacturerData` - Manufacturer-specific data
- `Capabilities` - Platform feature matrix

**Bounded Contexts:**
1. **Discovery Context** - Scanning and device discovery
2. **Connection Context** - Managing device connections
3. **GATT Client Context** - Service/characteristic operations (planned)
4. **GATT Server Context** - Peripheral role (planned)
5. **Platform Context** - Bluetooth state and permissions

## 🧪 Test-Driven Development

All code built following strict TDD:
- **Red**: Write failing test
- **Green**: Implement minimum code to pass
- **Refactor**: Improve while keeping tests green

### Test Coverage

| Package | Tests | Status |
|---------|-------|--------|
| bluey | 54 | ✅ All passing |
| bluey_platform_interface | 20 | ✅ All passing |
| bluey_android | 2 | ✅ All passing |
| **Total** | **76** | ✅ **All passing** |

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

### Phase 4: GATT Operations
- [ ] Service discovery
- [ ] Characteristic read/write
- [ ] Notifications/indications
- [ ] Descriptor operations
- [ ] MTU negotiation

### Phase 5: Advanced Features
- [ ] Peripheral role (advertising)
- [ ] Bonding/pairing
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
