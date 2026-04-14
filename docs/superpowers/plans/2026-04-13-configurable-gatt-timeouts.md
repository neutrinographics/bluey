# Configurable GATT Timeouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GATT operation timeouts configurable through `Bluey.configure()` with sane defaults, flowing from the domain layer through the platform interface to native Android (Kotlin) and iOS (Swift).

**Architecture:** Add a `GattTimeouts` value object to the domain layer. Extend `BlueyConfig` in the platform interface with nullable millisecond fields. Extend `BlueyConfigDto` in both Pigeon definitions and regenerate. Native implementations replace hardcoded constants with mutable fields set from config.

**Tech Stack:** Dart, Flutter, Kotlin, Swift, Pigeon

**Spec:** `docs/superpowers/specs/2026-04-13-configurable-gatt-timeouts-design.md`

---

## Task 1: Create `GattTimeouts` Value Object

**Files:**
- Create: `bluey/test/gatt_timeouts_test.dart`
- Create: `bluey/lib/src/shared/gatt_timeouts.dart`
- Modify: `bluey/lib/bluey.dart` (barrel file)

- [ ] **Step 1: Write failing tests**

Create `bluey/test/gatt_timeouts_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattTimeouts', () {
    test('has sane defaults', () {
      const timeouts = GattTimeouts();

      expect(timeouts.discoverServices, const Duration(seconds: 15));
      expect(timeouts.readCharacteristic, const Duration(seconds: 10));
      expect(timeouts.writeCharacteristic, const Duration(seconds: 10));
      expect(timeouts.readDescriptor, const Duration(seconds: 10));
      expect(timeouts.writeDescriptor, const Duration(seconds: 10));
      expect(timeouts.requestMtu, const Duration(seconds: 10));
      expect(timeouts.readRssi, const Duration(seconds: 5));
    });

    test('allows custom values', () {
      const timeouts = GattTimeouts(
        discoverServices: Duration(seconds: 30),
        readRssi: Duration(seconds: 2),
      );

      expect(timeouts.discoverServices, const Duration(seconds: 30));
      expect(timeouts.readRssi, const Duration(seconds: 2));
      // Others remain at defaults
      expect(timeouts.readCharacteristic, const Duration(seconds: 10));
    });

    test('equality by value', () {
      const t1 = GattTimeouts();
      const t2 = GattTimeouts();
      const t3 = GattTimeouts(discoverServices: Duration(seconds: 30));

      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd bluey && flutter test test/gatt_timeouts_test.dart`
Expected: FAIL — `GattTimeouts` not found.

- [ ] **Step 3: Implement `GattTimeouts`**

Create `bluey/lib/src/shared/gatt_timeouts.dart`:

```dart
import 'package:meta/meta.dart';

/// Configurable timeouts for GATT operations.
///
/// All parameters are optional with sensible defaults. Pass to
/// [Bluey.configure] to customize timeout behavior.
///
/// Note: [requestMtu] only applies on Android. iOS auto-negotiates MTU.
@immutable
class GattTimeouts {
  /// Timeout for service discovery.
  final Duration discoverServices;

  /// Timeout for reading a characteristic value.
  final Duration readCharacteristic;

  /// Timeout for writing a characteristic value (with response).
  final Duration writeCharacteristic;

  /// Timeout for reading a descriptor value.
  final Duration readDescriptor;

  /// Timeout for writing a descriptor value.
  final Duration writeDescriptor;

  /// Timeout for MTU negotiation (Android only).
  final Duration requestMtu;

  /// Timeout for reading RSSI.
  final Duration readRssi;

  const GattTimeouts({
    this.discoverServices = const Duration(seconds: 15),
    this.readCharacteristic = const Duration(seconds: 10),
    this.writeCharacteristic = const Duration(seconds: 10),
    this.readDescriptor = const Duration(seconds: 10),
    this.writeDescriptor = const Duration(seconds: 10),
    this.requestMtu = const Duration(seconds: 10),
    this.readRssi = const Duration(seconds: 5),
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GattTimeouts &&
        other.discoverServices == discoverServices &&
        other.readCharacteristic == readCharacteristic &&
        other.writeCharacteristic == writeCharacteristic &&
        other.readDescriptor == readDescriptor &&
        other.writeDescriptor == writeDescriptor &&
        other.requestMtu == requestMtu &&
        other.readRssi == readRssi;
  }

  @override
  int get hashCode => Object.hash(
        discoverServices,
        readCharacteristic,
        writeCharacteristic,
        readDescriptor,
        writeDescriptor,
        requestMtu,
        readRssi,
      );
}
```

- [ ] **Step 4: Export from barrel file**

In `bluey/lib/bluey.dart`, add:

```dart
export 'src/shared/gatt_timeouts.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd bluey && flutter test test/gatt_timeouts_test.dart`
Expected: All 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
cd bluey && git add lib/src/shared/gatt_timeouts.dart lib/bluey.dart test/gatt_timeouts_test.dart
git commit -m "feat: add GattTimeouts value object

Configurable timeouts for GATT operations with sane defaults.
All parameters optional — consumers who don't customize get
identical behavior to current hardcoded values.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Update `Bluey.configure()` and Platform Interface

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Modify: `bluey_platform_interface/lib/src/platform_interface.dart`

- [ ] **Step 1: Add timeout fields to `BlueyConfig` in platform interface**

In `bluey_platform_interface/lib/src/platform_interface.dart`, update the `BlueyConfig` class:

```dart
@immutable
class BlueyConfig {
  final bool cleanupOnActivityDestroy;
  final int? discoverServicesTimeoutMs;
  final int? readCharacteristicTimeoutMs;
  final int? writeCharacteristicTimeoutMs;
  final int? readDescriptorTimeoutMs;
  final int? writeDescriptorTimeoutMs;
  final int? requestMtuTimeoutMs;
  final int? readRssiTimeoutMs;

  const BlueyConfig({
    this.cleanupOnActivityDestroy = true,
    this.discoverServicesTimeoutMs,
    this.readCharacteristicTimeoutMs,
    this.writeCharacteristicTimeoutMs,
    this.readDescriptorTimeoutMs,
    this.writeDescriptorTimeoutMs,
    this.requestMtuTimeoutMs,
    this.readRssiTimeoutMs,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BlueyConfig &&
        other.cleanupOnActivityDestroy == cleanupOnActivityDestroy &&
        other.discoverServicesTimeoutMs == discoverServicesTimeoutMs &&
        other.readCharacteristicTimeoutMs == readCharacteristicTimeoutMs &&
        other.writeCharacteristicTimeoutMs == writeCharacteristicTimeoutMs &&
        other.readDescriptorTimeoutMs == readDescriptorTimeoutMs &&
        other.writeDescriptorTimeoutMs == writeDescriptorTimeoutMs &&
        other.requestMtuTimeoutMs == requestMtuTimeoutMs &&
        other.readRssiTimeoutMs == readRssiTimeoutMs;
  }

  @override
  int get hashCode => Object.hash(
        cleanupOnActivityDestroy,
        discoverServicesTimeoutMs,
        readCharacteristicTimeoutMs,
        writeCharacteristicTimeoutMs,
        readDescriptorTimeoutMs,
        writeDescriptorTimeoutMs,
        requestMtuTimeoutMs,
        readRssiTimeoutMs,
      );
}
```

- [ ] **Step 2: Update `Bluey.configure()` to accept `GattTimeouts`**

In `bluey/lib/src/bluey.dart`, update the `configure` method:

```dart
  Future<void> configure({
    bool cleanupOnActivityDestroy = true,
    GattTimeouts gattTimeouts = const GattTimeouts(),
  }) async {
    try {
      await _platform.configure(
        platform.BlueyConfig(
          cleanupOnActivityDestroy: cleanupOnActivityDestroy,
          discoverServicesTimeoutMs: gattTimeouts.discoverServices.inMilliseconds,
          readCharacteristicTimeoutMs: gattTimeouts.readCharacteristic.inMilliseconds,
          writeCharacteristicTimeoutMs: gattTimeouts.writeCharacteristic.inMilliseconds,
          readDescriptorTimeoutMs: gattTimeouts.readDescriptor.inMilliseconds,
          writeDescriptorTimeoutMs: gattTimeouts.writeDescriptor.inMilliseconds,
          requestMtuTimeoutMs: gattTimeouts.requestMtu.inMilliseconds,
          readRssiTimeoutMs: gattTimeouts.readRssi.inMilliseconds,
        ),
      );
    } catch (e) {
      throw _wrapError(e);
    }
  }
```

Add import at top of `bluey/lib/src/bluey.dart`:

```dart
import 'shared/gatt_timeouts.dart';
```

Also update the doc comment example to show the new parameter.

- [ ] **Step 3: Run all tests**

Run: `cd bluey && flutter test`
Expected: All tests pass.

Run: `cd bluey_platform_interface && flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/bluey.dart bluey_platform_interface/lib/src/platform_interface.dart
git commit -m "feat: wire GattTimeouts through configure() to platform interface

Bluey.configure() now accepts GattTimeouts parameter. BlueyConfig
extended with nullable millisecond timeout fields. Domain Duration
values mapped to int? at the platform boundary.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Update Pigeon Definitions and Regenerate

**Files:**
- Modify: `bluey_android/pigeons/messages.dart`
- Modify: `bluey_ios/pigeons/messages.dart`
- Regenerate: `bluey_android/lib/src/messages.g.dart`
- Regenerate: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt`
- Regenerate: `bluey_ios/lib/src/messages.g.dart`
- Regenerate: `bluey_ios/ios/Classes/Messages.g.swift`

- [ ] **Step 1: Update Android Pigeon `BlueyConfigDto`**

In `bluey_android/pigeons/messages.dart`, update the `BlueyConfigDto` class (around line 299):

```dart
/// Configuration options for the Bluey plugin.
class BlueyConfigDto {
  /// Whether to automatically clean up BLE resources when the activity is destroyed.
  final bool cleanupOnActivityDestroy;

  /// GATT operation timeout overrides (in milliseconds). Null means use default.
  final int? discoverServicesTimeoutMs;
  final int? readCharacteristicTimeoutMs;
  final int? writeCharacteristicTimeoutMs;
  final int? readDescriptorTimeoutMs;
  final int? writeDescriptorTimeoutMs;
  final int? requestMtuTimeoutMs;
  final int? readRssiTimeoutMs;

  BlueyConfigDto({
    this.cleanupOnActivityDestroy = true,
    this.discoverServicesTimeoutMs,
    this.readCharacteristicTimeoutMs,
    this.writeCharacteristicTimeoutMs,
    this.readDescriptorTimeoutMs,
    this.writeDescriptorTimeoutMs,
    this.requestMtuTimeoutMs,
    this.readRssiTimeoutMs,
  });
}
```

- [ ] **Step 2: Update iOS Pigeon `BlueyConfigDto`**

In `bluey_ios/pigeons/messages.dart`, update the `BlueyConfigDto` class (around line 273):

```dart
/// Configuration options for the Bluey plugin.
/// Note: cleanupOnActivityDestroy is Android-specific and ignored on iOS.
class BlueyConfigDto {
  /// Ignored on iOS (cleanup is handled automatically by the OS).
  final bool cleanupOnActivityDestroy;

  /// GATT operation timeout overrides (in milliseconds). Null means use default.
  final int? discoverServicesTimeoutMs;
  final int? readCharacteristicTimeoutMs;
  final int? writeCharacteristicTimeoutMs;
  final int? readDescriptorTimeoutMs;
  final int? writeDescriptorTimeoutMs;
  final int? readRssiTimeoutMs;

  BlueyConfigDto({
    this.cleanupOnActivityDestroy = true,
    this.discoverServicesTimeoutMs,
    this.readCharacteristicTimeoutMs,
    this.writeCharacteristicTimeoutMs,
    this.readDescriptorTimeoutMs,
    this.writeDescriptorTimeoutMs,
    this.readRssiTimeoutMs,
  });
}
```

Note: iOS does not include `requestMtuTimeoutMs` since iOS doesn't support `requestMtu`.

- [ ] **Step 3: Regenerate Android Pigeon bindings**

Run: `cd bluey_android && dart run pigeon --input pigeons/messages.dart`
Expected: Regenerates `lib/src/messages.g.dart` and `android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt`.

- [ ] **Step 4: Regenerate iOS Pigeon bindings**

Run: `cd bluey_ios && dart run pigeon --input pigeons/messages.dart`
Expected: Regenerates `lib/src/messages.g.dart` and `ios/Classes/Messages.g.swift`.

- [ ] **Step 5: Update Android `BlueyAndroid.configure()` to pass new fields**

In `bluey_android/lib/src/bluey_android.dart`, update the `configure` method to map the new fields:

```dart
  @override
  Future<void> configure(BlueyConfig config) async {
    _ensureInitialized();
    final dto = BlueyConfigDto(
      cleanupOnActivityDestroy: config.cleanupOnActivityDestroy,
      discoverServicesTimeoutMs: config.discoverServicesTimeoutMs,
      readCharacteristicTimeoutMs: config.readCharacteristicTimeoutMs,
      writeCharacteristicTimeoutMs: config.writeCharacteristicTimeoutMs,
      readDescriptorTimeoutMs: config.readDescriptorTimeoutMs,
      writeDescriptorTimeoutMs: config.writeDescriptorTimeoutMs,
      requestMtuTimeoutMs: config.requestMtuTimeoutMs,
      readRssiTimeoutMs: config.readRssiTimeoutMs,
    );
    await _hostApi.configure(dto);
  }
```

- [ ] **Step 6: Update iOS `BlueyIos.configure()` to pass new fields**

In `bluey_ios/lib/src/bluey_ios.dart`, update the `configure` method:

```dart
  @override
  Future<void> configure(BlueyConfig config) async {
    _ensureInitialized();
    final dto = BlueyConfigDto(
      cleanupOnActivityDestroy: config.cleanupOnActivityDestroy,
      discoverServicesTimeoutMs: config.discoverServicesTimeoutMs,
      readCharacteristicTimeoutMs: config.readCharacteristicTimeoutMs,
      writeCharacteristicTimeoutMs: config.writeCharacteristicTimeoutMs,
      readDescriptorTimeoutMs: config.readDescriptorTimeoutMs,
      writeDescriptorTimeoutMs: config.writeDescriptorTimeoutMs,
      readRssiTimeoutMs: config.readRssiTimeoutMs,
    );
    await _hostApi.configure(dto);
  }
```

- [ ] **Step 7: Run tests for all packages**

Run: `cd bluey && flutter test`
Run: `cd bluey_android && flutter test`
Run: `cd bluey_ios && flutter test`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add bluey_android/pigeons/messages.dart bluey_android/lib/src/messages.g.dart bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt bluey_android/lib/src/bluey_android.dart bluey_ios/pigeons/messages.dart bluey_ios/lib/src/messages.g.dart bluey_ios/ios/Classes/Messages.g.swift bluey_ios/lib/src/bluey_ios.dart
git commit -m "feat: add timeout fields to Pigeon config DTOs and regenerate

Extend BlueyConfigDto with nullable timeout overrides on both platforms.
Regenerate Pigeon bindings. Update Dart configure() to pass new fields.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Android Native — Configurable Timeouts

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt`

- [ ] **Step 1: Replace companion constants with mutable instance fields**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`:

Replace the companion object timeout constants:

```kotlin
    companion object {
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
```

(Remove the 7 timeout constants from the companion object.)

Add mutable instance fields after the existing field declarations (after the `pendingRssiReads` line):

```kotlin
    // Configurable timeout values — set via configure(), defaults match previous hardcoded values
    private var discoverServicesTimeoutMs = 15_000L
    private var readCharacteristicTimeoutMs = 10_000L
    private var writeCharacteristicTimeoutMs = 10_000L
    private var readDescriptorTimeoutMs = 10_000L
    private var writeDescriptorTimeoutMs = 10_000L
    private var requestMtuTimeoutMs = 10_000L
    private var readRssiTimeoutMs = 5_000L
```

Add a `configure` method:

```kotlin
    fun configure(config: BlueyConfigDto) {
        config.discoverServicesTimeoutMs?.let { discoverServicesTimeoutMs = it }
        config.readCharacteristicTimeoutMs?.let { readCharacteristicTimeoutMs = it }
        config.writeCharacteristicTimeoutMs?.let { writeCharacteristicTimeoutMs = it }
        config.readDescriptorTimeoutMs?.let { readDescriptorTimeoutMs = it }
        config.writeDescriptorTimeoutMs?.let { writeDescriptorTimeoutMs = it }
        config.requestMtuTimeoutMs?.let { requestMtuTimeoutMs = it }
        config.readRssiTimeoutMs?.let { readRssiTimeoutMs = it }
    }
```

Then replace all references to the old companion constants with the instance fields. There are 7 replacements:

- `DISCOVER_SERVICES_TIMEOUT_MS` → `discoverServicesTimeoutMs`
- `READ_CHARACTERISTIC_TIMEOUT_MS` → `readCharacteristicTimeoutMs`
- `WRITE_CHARACTERISTIC_TIMEOUT_MS` → `writeCharacteristicTimeoutMs`
- `READ_DESCRIPTOR_TIMEOUT_MS` → `readDescriptorTimeoutMs`
- `WRITE_DESCRIPTOR_TIMEOUT_MS` → `writeDescriptorTimeoutMs`
- `MTU_REQUEST_TIMEOUT_MS` → `requestMtuTimeoutMs`
- `READ_RSSI_TIMEOUT_MS` → `readRssiTimeoutMs`

- [ ] **Step 2: Forward config to ConnectionManager from BlueyPlugin**

In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt`, update the `configure` method:

```kotlin
    override fun configure(config: BlueyConfigDto, callback: (Result<Unit>) -> Unit) {
        cleanupOnActivityDestroy = config.cleanupOnActivityDestroy
        connectionManager?.configure(config)
        android.util.Log.d("BlueyPlugin", "Configured: cleanupOnActivityDestroy=$cleanupOnActivityDestroy")
        callback(Result.success(Unit))
    }
```

- [ ] **Step 3: Run Android tests**

Run: `cd bluey_android && flutter test`
Expected: All 54 tests pass.

- [ ] **Step 4: Commit**

```bash
cd bluey_android && git add android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt
git commit -m "feat: make Android GATT timeouts configurable via configure()

Replace hardcoded companion object constants with mutable instance
fields in ConnectionManager. BlueyPlugin forwards config to
ConnectionManager. Null config values preserve defaults.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: iOS Native — Configurable Timeouts

**Files:**
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift`
- Modify: `bluey_ios/ios/Classes/BlueyIosPlugin.swift`

- [ ] **Step 1: Replace `BleTimeout` enum with mutable stored properties**

In `bluey_ios/ios/Classes/CentralManagerImpl.swift`:

Remove the `BleTimeout` enum at the top of the file:

```swift
private enum BleTimeout {
    static let connect: TimeInterval = 30.0
    static let discoverServices: TimeInterval = 15.0
    static let readCharacteristic: TimeInterval = 10.0
    static let writeCharacteristic: TimeInterval = 10.0
    static let readDescriptor: TimeInterval = 10.0
    static let writeDescriptor: TimeInterval = 10.0
    static let readRssi: TimeInterval = 5.0
}
```

Add mutable stored properties to the `CentralManagerImpl` class, after the existing property declarations:

```swift
    // Configurable timeout values — set via configure(), defaults match previous hardcoded values
    private var connectTimeout: TimeInterval = 30.0
    private var discoverServicesTimeout: TimeInterval = 15.0
    private var readCharacteristicTimeout: TimeInterval = 10.0
    private var writeCharacteristicTimeout: TimeInterval = 10.0
    private var readDescriptorTimeout: TimeInterval = 10.0
    private var writeDescriptorTimeout: TimeInterval = 10.0
    private var readRssiTimeout: TimeInterval = 5.0
```

Add a `configure` method:

```swift
    func configure(config: BlueyConfigDto) {
        if let ms = config.discoverServicesTimeoutMs {
            discoverServicesTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.readCharacteristicTimeoutMs {
            readCharacteristicTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.writeCharacteristicTimeoutMs {
            writeCharacteristicTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.readDescriptorTimeoutMs {
            readDescriptorTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.writeDescriptorTimeoutMs {
            writeDescriptorTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.readRssiTimeoutMs {
            readRssiTimeout = TimeInterval(ms) / 1000.0
        }
    }
```

Then replace all references to the old `BleTimeout` enum with the instance properties. There are 7 replacements:

- `BleTimeout.connect` → `connectTimeout`
- `BleTimeout.discoverServices` → `discoverServicesTimeout`
- `BleTimeout.readCharacteristic` → `readCharacteristicTimeout`
- `BleTimeout.writeCharacteristic` → `writeCharacteristicTimeout`
- `BleTimeout.readDescriptor` → `readDescriptorTimeout`
- `BleTimeout.writeDescriptor` → `writeDescriptorTimeout`
- `BleTimeout.readRssi` → `readRssiTimeout`

- [ ] **Step 2: Forward config to CentralManagerImpl from BlueyIosPlugin**

In `bluey_ios/ios/Classes/BlueyIosPlugin.swift`, update the `configure` method:

```swift
    func configure(config: BlueyConfigDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.configure(config: config)
        completion(.success(()))
    }
```

- [ ] **Step 3: Run iOS tests**

Run: `cd bluey_ios && flutter test`
Expected: All 73 tests pass.

- [ ] **Step 4: Commit**

```bash
cd bluey_ios && git add ios/Classes/CentralManagerImpl.swift ios/Classes/BlueyIosPlugin.swift
git commit -m "feat: make iOS GATT timeouts configurable via configure()

Replace BleTimeout enum constants with mutable stored properties in
CentralManagerImpl. BlueyIosPlugin forwards config to CentralManagerImpl.
Nil config values preserve defaults.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Final Verification

**Files:** None modified.

- [ ] **Step 1: Run all package tests**

Run: `cd bluey && flutter test`
Expected: All ~450 tests pass.

Run: `cd bluey_android && flutter test`
Expected: All 54 tests pass.

Run: `cd bluey_ios && flutter test`
Expected: All 73 tests pass.

Run: `cd bluey_platform_interface && flutter test`
Expected: All 8 tests pass (2 pre-existing failures from stale mock are expected).

- [ ] **Step 2: Verify `GattTimeouts` is exported**

Run: `grep "gatt_timeouts" bluey/lib/bluey.dart`
Expected: Shows the export line.

- [ ] **Step 3: Verify no hardcoded timeout constants remain**

Run: `grep -n "DISCOVER_SERVICES_TIMEOUT\|READ_CHARACTERISTIC_TIMEOUT\|WRITE_CHARACTERISTIC_TIMEOUT\|READ_DESCRIPTOR_TIMEOUT\|WRITE_DESCRIPTOR_TIMEOUT\|MTU_REQUEST_TIMEOUT\|READ_RSSI_TIMEOUT" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`
Expected: No output (all replaced with instance fields).

Run: `grep -n "BleTimeout" bluey_ios/ios/Classes/CentralManagerImpl.swift`
Expected: No output (enum removed, replaced with stored properties).

- [ ] **Step 4: Verify configure flows end-to-end**

Run: `grep -n "fun configure\|func configure" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt bluey_ios/ios/Classes/CentralManagerImpl.swift bluey_ios/ios/Classes/BlueyIosPlugin.swift`
Expected: Shows configure methods in all 4 native files.
