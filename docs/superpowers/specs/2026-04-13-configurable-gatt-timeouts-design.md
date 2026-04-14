# Configurable GATT Timeouts — Design Spec

## Goal

Make GATT operation timeouts configurable through the existing `Bluey.configure()` API, with sane defaults matching the current hardcoded values. The connect timeout remains per-call.

## Changes by Layer

### Domain Layer (`bluey`)

**New value object: `GattTimeouts`** in `bluey/lib/src/shared/gatt_timeouts.dart`:

```dart
@immutable
class GattTimeouts {
  final Duration discoverServices;     // default: 15s
  final Duration readCharacteristic;   // default: 10s
  final Duration writeCharacteristic;  // default: 10s
  final Duration readDescriptor;       // default: 10s
  final Duration writeDescriptor;      // default: 10s
  final Duration requestMtu;           // default: 10s (Android only)
  final Duration readRssi;             // default: 5s

  const GattTimeouts({ ... });  // all optional with defaults above
}
```

Immutable, `@immutable`, value equality, `const` constructor. All parameters optional — consumers who don't care get identical behavior to today.

**`Bluey.configure()` update:**

```dart
Future<void> configure({
  bool cleanupOnActivityDestroy = true,
  GattTimeouts gattTimeouts = const GattTimeouts(),
}) async { ... }
```

Maps `GattTimeouts` durations to `BlueyConfig` millisecond values before passing to platform.

**Barrel file** — export `gatt_timeouts.dart`.

### Platform Interface (`bluey_platform_interface`)

**`BlueyConfig` update** — Add nullable `int?` timeout fields:

- `discoverServicesTimeoutMs`
- `readCharacteristicTimeoutMs`
- `writeCharacteristicTimeoutMs`
- `readDescriptorTimeoutMs`
- `writeDescriptorTimeoutMs`
- `requestMtuTimeoutMs`
- `readRssiTimeoutMs`

All nullable — `null` means use platform default.

### Pigeon Definitions (both platforms)

**`BlueyConfigDto` update** — Add the same 7 nullable `int?` fields. Regenerate both platforms:

- `bluey_android/pigeons/messages.dart` → regenerate `Messages.g.kt` + `messages.g.dart`
- `bluey_ios/pigeons/messages.dart` → regenerate `Messages.g.swift` + `messages.g.dart`

### Android Native (`ConnectionManager.kt`)

- Replace `companion object` constants with mutable instance fields (same initial defaults)
- Add `fun configure(config: BlueyConfigDto)` that updates fields from non-null config values
- Existing `handler.postDelayed` calls use instance fields instead of constants
- `BlueyPlugin.kt` forwards config to `ConnectionManager` in its `configure()` method

### iOS Native (`CentralManagerImpl.swift`)

- Replace `BleTimeout` enum constants with mutable stored properties (same initial defaults)
- Add `func configure(config: BlueyConfigDto)` that updates properties from non-nil config values
- Existing `DispatchQueue.main.asyncAfter` calls use stored properties instead of enum constants
- `BlueyIosPlugin.swift` forwards config to `CentralManagerImpl` in its `configure()` method

### Dart Platform Implementations

- `BlueyAndroid.configure()` — pass full `BlueyConfigDto` (already does, just needs the new fields mapped)
- `BlueyIos.configure()` — same

## Consumer API

```dart
// Use defaults (identical to current behavior)
await bluey.configure();

// Customize specific timeouts
await bluey.configure(
  gattTimeouts: GattTimeouts(
    discoverServices: Duration(seconds: 30),
    readCharacteristic: Duration(seconds: 5),
  ),
);
```

## Testing

- **Domain**: Test `GattTimeouts` construction with defaults and custom values
- **Domain**: Test `Bluey.configure()` maps `GattTimeouts` to `BlueyConfig` correctly
- **Platform packages**: Existing Dart tests verify `configure()` calls hostApi — update to verify new fields are passed through

## Out of Scope

- Per-call timeouts on GATT operations (method signature changes)
- Connect timeout changes (stays per-call as-is)
- Timeout behavior changes (same asyncAfter/postDelayed pattern)
