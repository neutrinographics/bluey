# Android Error Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the Kotlin escape hatch so every Android GATT-op error surfaces as a typed `BlueyException` subclass — symmetric with iOS post-PR-#10.

**Architecture:** Introduce a sealed `BlueyAndroidError` hierarchy in Kotlin to replace every raw `IllegalStateException` / `SecurityException` throw. Two context-aware extension helpers translate each case to a `FlutterError` with a known Pigeon code. `BlueyPlugin.kt` wraps every Pigeon-facing method with `try { ... } catch (e: Throwable) { throw e.toClientFlutterError() }` (or the server variant) so nothing leaks untranslated. On the Dart side, add `PlatformPermissionDeniedException` to the platform interface, translate the new `bluey-permission-denied` code in the Android adapter, and translate to the existing `PermissionDeniedException` public class in `_runGattOp`.

**Tech Stack:** Kotlin, Dart 3.7+, Flutter, Pigeon, JUnit (Kotlin unit tests), `flutter_test` + `mocktail`.

**Spec:** `docs/superpowers/specs/2026-04-23-android-error-consistency-design.md`

---

## File map

### New files

```
bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt   (Task 3)
bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt               (Task 4)
bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt           (Task 4)
```

### Modified files

```
bluey_platform_interface/lib/src/exceptions.dart                                         (Task 1)
bluey_platform_interface/test/exceptions_test.dart                                       (Task 1)

bluey/lib/src/connection/bluey_connection.dart                                           (Task 2)
bluey/test/connection/bluey_connection_test.dart                                         (Task 2)

bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt    (Task 5)
bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt              (Task 6)
bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt           (Task 6)
bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt           (Task 7)
bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt          (Task 8)

bluey_android/lib/src/android_connection_manager.dart                                    (Task 9)
bluey_android/test/android_connection_manager_test.dart                                  (Task 9)
```

---

## Task 1: Platform-interface `PlatformPermissionDeniedException`

**Files:**
- Modify: `bluey_platform_interface/lib/src/exceptions.dart` (append after existing four `GattOperation*Exception` classes)
- Modify: `bluey_platform_interface/test/exceptions_test.dart` (append)

Adds the internal platform-interface exception that carries the missing permission name. Mirrors the existing `GattOperationUnknownPlatformException` pattern introduced in PR #10.

- [ ] **Step 1: Write the failing test**

Append to `bluey_platform_interface/test/exceptions_test.dart` inside its `void main()`:

```dart
  group('PlatformPermissionDeniedException', () {
    test('carries operation, permission, and message', () {
      const e = PlatformPermissionDeniedException(
        'writeCharacteristic',
        permission: 'BLUETOOTH_CONNECT',
        message: 'Missing BLUETOOTH_CONNECT permission',
      );
      expect(e.operation, 'writeCharacteristic');
      expect(e.permission, 'BLUETOOTH_CONNECT');
      expect(e.message, 'Missing BLUETOOTH_CONNECT permission');
    });

    test('equality by value', () {
      const a = PlatformPermissionDeniedException('op', permission: 'P');
      const b = PlatformPermissionDeniedException('op', permission: 'P');
      expect(a, equals(b));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd bluey_platform_interface && flutter test test/exceptions_test.dart`
Expected: compile failure — `PlatformPermissionDeniedException` is undefined.

- [ ] **Step 3: Implement the class**

Append to `bluey_platform_interface/lib/src/exceptions.dart`:

```dart
/// A platform operation failed because a required runtime permission was
/// denied. Currently Android-specific — iOS has no runtime-permission
/// equivalent that can fire mid-op (the CBManagerState.unauthorized case
/// is handled via `Bluey.state`).
///
/// Internal platform-interface signal. Not part of the `BlueyException`
/// sealed hierarchy in the `bluey` package; `BlueyConnection` translates
/// this into [PermissionDeniedException] at the public API boundary.
class PlatformPermissionDeniedException implements Exception {
  /// Name of the platform interface method that triggered the check,
  /// e.g. `'writeCharacteristic'`. Used for diagnostics.
  final String operation;

  /// The single missing permission name, e.g. `'BLUETOOTH_CONNECT'`,
  /// as reported by the native layer.
  final String permission;

  /// Optional human-readable message from the native layer.
  final String? message;

  const PlatformPermissionDeniedException(
    this.operation, {
    required this.permission,
    this.message,
  });

  @override
  String toString() =>
      'PlatformPermissionDeniedException: $operation denied '
      '(permission: $permission)${message != null ? ' - $message' : ''}';

  @override
  bool operator ==(Object other) =>
      other is PlatformPermissionDeniedException &&
      other.operation == operation &&
      other.permission == permission &&
      other.message == message;

  @override
  int get hashCode => Object.hash(operation, permission, message);
}
```

Verify the existing barrel export in `bluey_platform_interface/lib/bluey_platform_interface.dart` (or whichever file is the public entry) re-exports exceptions the same way it does for the existing four. If the existing ones are re-exported via `export 'src/exceptions.dart';`, nothing to add.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey_platform_interface && flutter test test/exceptions_test.dart`
Expected: both new tests pass.

- [ ] **Step 5: Full suite + analyze**

Run: `cd bluey_platform_interface && flutter test`
Expected: all tests pass.

Run: `cd bluey_platform_interface && flutter analyze`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey_platform_interface/lib/src/exceptions.dart \
        bluey_platform_interface/test/exceptions_test.dart
git commit -m "feat(platform-interface): add PlatformPermissionDeniedException"
```

---

## Task 2: Core library — `_runGattOp` translates `PlatformPermissionDeniedException` → `PermissionDeniedException`

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart` (around lines 30–60 where `_runGattOp` lives)
- Modify: `bluey/test/connection/bluey_connection_test.dart` (append)
- Modify: `bluey/test/fakes/fake_platform.dart` (extend if needed)

Translates the new platform-interface exception to the existing user-facing `PermissionDeniedException`. The existing `List<String>` constructor shape is preserved — the single permission from Android is wrapped in a one-element list.

- [ ] **Step 1: Verify FakeBlueyPlatform supports injecting arbitrary read errors**

```bash
cd bluey && grep -n "simulateReadError\|simulateReadPlatformErrorCode" test/fakes/fake_platform.dart
```

Expected: at least one of these hooks already exists from PR #10. If not, extend the fake with:

```dart
// Near other simulate-flags:
Object? _pendingReadError;
void simulateReadError(Object error) {
  _pendingReadError = error;
}

// In readCharacteristic override, at the top:
final pending = _pendingReadError;
if (pending != null) {
  _pendingReadError = null;
  throw pending;
}
```

If the hook already exists, skip this step.

- [ ] **Step 2: Write the failing test**

Append to `bluey/test/connection/bluey_connection_test.dart` inside its `void main()`:

```dart
  group('_runGattOp PlatformPermissionDeniedException translation', () {
    test('wraps PlatformPermissionDeniedException as PermissionDeniedException', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withReadable(TestUuids.customChar1, value: Uint8List.fromList([0x01]))
              .build(),
        ],
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      fakePlatform.simulateReadError(
        const platform.PlatformPermissionDeniedException(
          'readCharacteristic',
          permission: 'BLUETOOTH_CONNECT',
          message: 'Missing BLUETOOTH_CONNECT permission',
        ),
      );

      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        properties: const CharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
      );

      try {
        await char.read();
        fail('expected PermissionDeniedException');
      } on PermissionDeniedException catch (e) {
        expect(e.permissions, ['BLUETOOTH_CONNECT']);
      }
    });
  });
```

Imports to add at the top of the test file if absent:
```dart
import 'package:bluey/src/shared/exceptions.dart' show PermissionDeniedException;
```

- [ ] **Step 3: Run to verify RED**

Run: `cd bluey && flutter test test/connection/bluey_connection_test.dart`
Expected: the new test fails — `PlatformPermissionDeniedException` propagates as itself, not as `PermissionDeniedException`.

- [ ] **Step 4: Add the translation branch to `_runGattOp`**

In `bluey/lib/src/connection/bluey_connection.dart`, find the existing `_runGattOp` function (around line 30). Insert a new `on platform.PlatformPermissionDeniedException` branch BEFORE the existing `on PlatformException catch (e)` backstop:

```dart
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body, {
  void Function()? onSuccess,
}) async {
  try {
    final result = await body();
    onSuccess?.call();
    return result;
  } on platform.GattOperationTimeoutException {
    throw GattTimeoutException(operation);
  } on platform.GattOperationDisconnectedException {
    throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
  } on platform.GattOperationStatusFailedException catch (e) {
    throw GattOperationFailedException(operation, e.status);
  } on platform.GattOperationUnknownPlatformException catch (e) {
    throw BlueyPlatformException(
      e.message ?? 'unknown platform error (${e.code})',
      code: e.code,
      cause: e,
    );
  } on platform.PlatformPermissionDeniedException catch (e) {
    throw PermissionDeniedException([e.permission]);
  } on PlatformException catch (e) {
    throw BlueyPlatformException(
      e.message ?? 'platform error (${e.code})',
      code: e.code,
      cause: e,
    );
  }
}
```

- [ ] **Step 5: Run to verify GREEN**

Run: `cd bluey && flutter test test/connection/bluey_connection_test.dart`
Expected: all tests pass.

- [ ] **Step 6: Full suite + analyze**

Run: `cd bluey && flutter test`
Expected: all tests pass.

Run: `cd bluey && flutter analyze`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/bluey_connection_test.dart \
        bluey/test/fakes/fake_platform.dart
git commit -m "feat(bluey): _runGattOp translates PlatformPermissionDeniedException to PermissionDeniedException"
```

---

## Task 3: Kotlin `BlueyAndroidError` sealed class

**Files:**
- Create: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt`

Adds the sealed hierarchy that replaces `IllegalStateException` / `SecurityException` throws throughout the Kotlin plugin. No tests needed yet — this is pure data; Task 4 exercises it.

- [ ] **Step 1: Create the file**

Create `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt`:

```kotlin
package com.neutrinographics.bluey

/**
 * Plugin-internal error vocabulary. Every site in the Kotlin plugin that
 * would previously throw `IllegalStateException` or `SecurityException`
 * now throws a [BlueyAndroidError] case instead. Two extension helpers
 * in `Errors.kt` translate each case to a [FlutterError] with a known
 * Pigeon code at the FFI boundary — `toClientFlutterError()` for methods
 * dispatched through `ConnectionManager` / `Scanner`, `toServerFlutterError()`
 * for methods dispatched through `GattServer`.
 *
 * Never crosses the Pigeon boundary directly; always translated first.
 */
internal sealed class BlueyAndroidError(message: String) : Exception(message) {

    // --- Client-side preconditions → gatt-disconnected ---

    /** Attempt to operate on a peer we're not currently connected to. */
    object DeviceNotConnected : BlueyAndroidError("Device not connected")

    /** Attempt to enqueue a GATT op with no queue for the connection. */
    object NoQueueForConnection : BlueyAndroidError("No queue for connection")

    /** Peer's cached service layout no longer contains this characteristic. */
    data class CharacteristicNotFound(val uuid: String) :
        BlueyAndroidError("Characteristic not found: $uuid")

    /** Peer's cached service layout no longer contains this descriptor. */
    data class DescriptorNotFound(val uuid: String) :
        BlueyAndroidError("Descriptor not found: $uuid")

    // --- Connect phase → gatt-timeout / bluey-unknown ---

    /** The connect() attempt timed out before STATE_CONNECTED. */
    object ConnectionTimeout : BlueyAndroidError("Connection timeout")

    /** BluetoothDevice.connectGatt returned null or failed synchronously. */
    object GattConnectionCreationFailed : BlueyAndroidError("GATT connection creation failed")

    // --- Sync setNotification reject → gatt-status-failed(0x01) ---

    /** gatt.setCharacteristicNotification() returned false synchronously. */
    data class SetNotificationFailed(val uuid: String) :
        BlueyAndroidError("Failed to set notification: $uuid")

    // --- Server-side request path → gatt-status-failed(0x0A) ---

    /** Peer sent a request referencing a central we haven't tracked. */
    data class CentralNotFound(val id: String) :
        BlueyAndroidError("Central not found: $id")

    // --- Server-side setup → bluey-unknown ---

    /** BluetoothManager.openGattServer returned null. */
    object FailedToOpenGattServer : BlueyAndroidError("Failed to open GATT server")

    /** addService() returned an error status. */
    data class FailedToAddService(val uuid: String) :
        BlueyAndroidError("Failed to add service: $uuid")

    // --- System state → bluey-unknown ---

    object BluetoothAdapterUnavailable : BlueyAndroidError("Bluetooth adapter unavailable")
    object BluetoothNotAvailableOrDisabled : BlueyAndroidError("Bluetooth not available or disabled")
    object BleScannerNotAvailable : BlueyAndroidError("BLE scanner not available")
    object BleAdvertisingNotSupported : BlueyAndroidError("BLE advertising not supported")

    data class InvalidDeviceAddress(val address: String) :
        BlueyAndroidError("Invalid device address: $address")

    /** onStartFailure() from AdvertiseCallback. */
    data class AdvertisingStartFailed(val reason: String) : BlueyAndroidError(reason)

    /** Plugin component accessed before initialize() was called. */
    data class NotInitialized(val component: String) :
        BlueyAndroidError("$component not initialized")

    // --- Permission → bluey-permission-denied ---

    /** Runtime permission missing (BLUETOOTH_CONNECT / BLUETOOTH_SCAN / BLUETOOTH_ADVERTISE). */
    data class PermissionDenied(val permission: String) :
        BlueyAndroidError("Missing $permission permission")
}
```

- [ ] **Step 2: Verify the file compiles**

```bash
cd bluey_android/android && ./gradlew compileDebugKotlin 2>&1 | tail -10
```

Expected: `BUILD SUCCESSFUL`. If the task file says "compileDebugKotlin" isn't right, try `./gradlew build -x lint -x test 2>&1 | tail -10` (this varies by Android gradle plugin version).

- [ ] **Step 3: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt
git commit -m "feat(bluey_android): add BlueyAndroidError sealed hierarchy"
```

---

## Task 4: Kotlin `Errors.kt` extensions + `ErrorsTest.kt`

**Files:**
- Create: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`
- Create: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt`

Adds the two context-aware extension helpers that translate `BlueyAndroidError` (plus any `Throwable` fallback) into `FlutterError` with a known Pigeon code. Kotlin TDD — failing test file first.

- [ ] **Step 1: Write the failing test file**

Create `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt`:

```kotlin
package com.neutrinographics.bluey

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ErrorsTest {

    // --- Client-side mappings ---

    @Test
    fun `DeviceNotConnected → gatt-disconnected (client)`() {
        val e = BlueyAndroidError.DeviceNotConnected.toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `NoQueueForConnection → gatt-disconnected (client)`() {
        val e = BlueyAndroidError.NoQueueForConnection.toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `CharacteristicNotFound → gatt-disconnected (client)`() {
        val e = BlueyAndroidError.CharacteristicNotFound("abc").toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `DescriptorNotFound → gatt-disconnected (client)`() {
        val e = BlueyAndroidError.DescriptorNotFound("abc").toClientFlutterError()
        assertEquals("gatt-disconnected", e.code)
    }

    @Test
    fun `ConnectionTimeout → gatt-timeout (client)`() {
        val e = BlueyAndroidError.ConnectionTimeout.toClientFlutterError()
        assertEquals("gatt-timeout", e.code)
    }

    @Test
    fun `GattConnectionCreationFailed → bluey-unknown (client)`() {
        val e = BlueyAndroidError.GattConnectionCreationFailed.toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `SetNotificationFailed → gatt-status-failed(0x01) (client)`() {
        val e = BlueyAndroidError.SetNotificationFailed("abc").toClientFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x01, e.details)
    }

    @Test
    fun `BluetoothAdapterUnavailable → bluey-unknown (client)`() {
        val e = BlueyAndroidError.BluetoothAdapterUnavailable.toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `PermissionDenied → bluey-permission-denied with details=permission (client)`() {
        val e = BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT").toClientFlutterError()
        assertEquals("bluey-permission-denied", e.code)
        assertEquals("BLUETOOTH_CONNECT", e.details)
    }

    @Test
    fun `NotInitialized → bluey-unknown (client)`() {
        val e = BlueyAndroidError.NotInitialized("scanner").toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    // --- Server-side mappings ---

    @Test
    fun `CharacteristicNotFound → gatt-status-failed(0x0A) (server)`() {
        val e = BlueyAndroidError.CharacteristicNotFound("abc").toServerFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0A, e.details)
    }

    @Test
    fun `CentralNotFound → gatt-status-failed(0x0A) (server)`() {
        val e = BlueyAndroidError.CentralNotFound("central-1").toServerFlutterError()
        assertEquals("gatt-status-failed", e.code)
        assertEquals(0x0A, e.details)
    }

    @Test
    fun `FailedToOpenGattServer → bluey-unknown (server)`() {
        val e = BlueyAndroidError.FailedToOpenGattServer.toServerFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `FailedToAddService → bluey-unknown (server)`() {
        val e = BlueyAndroidError.FailedToAddService("abc").toServerFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `PermissionDenied → bluey-permission-denied (server)`() {
        val e = BlueyAndroidError.PermissionDenied("BLUETOOTH_ADVERTISE").toServerFlutterError()
        assertEquals("bluey-permission-denied", e.code)
        assertEquals("BLUETOOTH_ADVERTISE", e.details)
    }

    // --- Regression guard for context-sensitive mapping ---

    @Test
    fun `CharacteristicNotFound server-side does NOT map to gatt-disconnected`() {
        val e = BlueyAndroidError.CharacteristicNotFound("abc").toServerFlutterError()
        assertNotEquals(
            "Server-side notFound must not look like a disconnect",
            "gatt-disconnected",
            e.code
        )
    }

    // --- Catch-all for random Throwables ---

    @Test
    fun `random RuntimeException → bluey-unknown with class name (client)`() {
        val e = RuntimeException("kaboom").toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `random RuntimeException → bluey-unknown with class name (server)`() {
        val e = RuntimeException("kaboom").toServerFlutterError()
        assertEquals("bluey-unknown", e.code)
    }

    @Test
    fun `null-message Throwable falls back to class name (client)`() {
        val thrown: Throwable = object : RuntimeException() {}
        val e = thrown.toClientFlutterError()
        assertEquals("bluey-unknown", e.code)
        // message should not be null — it falls back to javaClass.simpleName
        assertEquals(thrown.javaClass.simpleName, e.message)
    }
}
```

- [ ] **Step 2: Run test to verify RED**

```bash
cd bluey_android/android && ./gradlew test --tests com.neutrinographics.bluey.ErrorsTest 2>&1 | tail -15
```

Expected: compile failure — `toClientFlutterError()` and `toServerFlutterError()` are undefined.

- [ ] **Step 3: Implement `Errors.kt`**

Create `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`:

```kotlin
package com.neutrinographics.bluey

/**
 * Translates a throwable raised by the Kotlin plugin into a [FlutterError]
 * with one of the well-known Pigeon codes the Dart adapter knows how to
 * handle. Use the *client* variant at call sites dispatched through
 * `ConnectionManager` / `Scanner` (client-role); use the *server* variant
 * at call sites dispatched through `GattServer` / `Advertiser` (server-role).
 *
 * The context split matters for [BlueyAndroidError.CharacteristicNotFound]:
 * client-side means the peer's cached service layout was invalidated (akin
 * to a disconnect), server-side means the user's hosted service didn't
 * register that attribute (a programming error, not a disconnect).
 *
 * Anything that isn't a [BlueyAndroidError] falls through to the
 * `bluey-unknown` code with the throwable's message (or class name, if
 * the message is null) so user code never sees raw `PlatformException`
 * regardless of what surfaces.
 */
internal fun Throwable.toClientFlutterError(): FlutterError = when (this) {
    is BlueyAndroidError.PermissionDenied ->
        FlutterError("bluey-permission-denied", message, permission)
    is BlueyAndroidError.DeviceNotConnected,
    is BlueyAndroidError.NoQueueForConnection,
    is BlueyAndroidError.CharacteristicNotFound,
    is BlueyAndroidError.DescriptorNotFound ->
        FlutterError("gatt-disconnected", message, null)
    is BlueyAndroidError.ConnectionTimeout ->
        FlutterError("gatt-timeout", message, null)
    is BlueyAndroidError.SetNotificationFailed ->
        FlutterError("gatt-status-failed", message, 0x01)
    is BlueyAndroidError ->
        FlutterError("bluey-unknown", message, null)
    else ->
        FlutterError("bluey-unknown", message ?: javaClass.simpleName, null)
}

internal fun Throwable.toServerFlutterError(): FlutterError = when (this) {
    is BlueyAndroidError.PermissionDenied ->
        FlutterError("bluey-permission-denied", message, permission)
    is BlueyAndroidError.CharacteristicNotFound,
    is BlueyAndroidError.CentralNotFound ->
        FlutterError("gatt-status-failed", message, 0x0A)
    is BlueyAndroidError ->
        FlutterError("bluey-unknown", message, null)
    else ->
        FlutterError("bluey-unknown", message ?: javaClass.simpleName, null)
}
```

- [ ] **Step 4: Run test to verify GREEN**

```bash
cd bluey_android/android && ./gradlew test --tests com.neutrinographics.bluey.ErrorsTest 2>&1 | tail -15
```

Expected: all ErrorsTest cases pass.

- [ ] **Step 5: Run full Kotlin test suite to verify no regressions**

```bash
cd bluey_android/android && ./gradlew test 2>&1 | tail -10
```

Expected: all existing Kotlin tests (`GattOpQueueTest`, `ConnectionManagerQueueTest`, `GattServerTest`, `BlueyPluginTest`) still pass.

- [ ] **Step 6: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt
git commit -m "feat(bluey_android): add Errors.kt context-aware FlutterError translation"
```

---

## Task 5: Replace `IllegalStateException` throws in `ConnectionManager.kt` with `BlueyAndroidError`

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`

Mechanical rewrite: every `throw IllegalStateException("X")` → `throw BlueyAndroidError.X`. Also `SecurityException` → `BlueyAndroidError.PermissionDenied`.

- [ ] **Step 1: Enumerate current throws**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt
```

Expected ~17 matches including:
- `"Device not connected"` (multiple)
- `"No queue for connection"` (multiple)
- `"Characteristic not found: $uuid"` (a few)
- `"Descriptor not found: $uuid"` (a few)
- `"Connection timeout"` (line ~156)
- `"GATT connection creation failed"` (line ~165)
- `"Failed to set notification"` (line ~299)
- `"Bluetooth adapter unavailable"` (line ~109)
- `"Invalid device address"` (line ~117)
- `SecurityException("Missing BLUETOOTH_CONNECT permission")` (line ~96, possibly 318)

- [ ] **Step 2: Replace each throw**

Edit each site one at a time (use `Edit` tool, NOT a blind `perl -pi -e`). Map per the sealed hierarchy:

| Old throw | New throw |
|---|---|
| `throw IllegalStateException("Device not connected")` | `throw BlueyAndroidError.DeviceNotConnected` |
| `throw IllegalStateException("No queue for connection")` | `throw BlueyAndroidError.NoQueueForConnection` |
| `throw IllegalStateException("Characteristic not found: $uuid")` | `throw BlueyAndroidError.CharacteristicNotFound(uuid)` |
| `throw IllegalStateException("Descriptor not found: $uuid")` | `throw BlueyAndroidError.DescriptorNotFound(uuid)` |
| `throw IllegalStateException("Connection timeout")` | `throw BlueyAndroidError.ConnectionTimeout` |
| `throw IllegalStateException("GATT connection creation failed")` | `throw BlueyAndroidError.GattConnectionCreationFailed` |
| `throw IllegalStateException("Failed to set notification")` | `throw BlueyAndroidError.SetNotificationFailed(uuid)` |
| `throw IllegalStateException("Bluetooth adapter unavailable")` | `throw BlueyAndroidError.BluetoothAdapterUnavailable` |
| `throw IllegalStateException("Invalid device address: $address")` | `throw BlueyAndroidError.InvalidDeviceAddress(address)` |
| `throw SecurityException("Missing BLUETOOTH_CONNECT permission")` | `throw BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")` |

Where the old throw had a string-interpolated UUID / address, pass it as the data-class field.

- [ ] **Step 3: Verify no old-pattern throws remain in this file**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt
```
Expected: empty output.

```bash
grep -c "throw BlueyAndroidError\." bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt
```
Expected: matches the count from Step 1.

- [ ] **Step 4: Build to verify compilation**

```bash
cd bluey_android/android && ./gradlew compileDebugKotlin 2>&1 | tail -10
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Run existing Kotlin tests**

```bash
cd bluey_android/android && ./gradlew test 2>&1 | tail -10
```
Expected: all tests pass (existing `ConnectionManagerQueueTest` may assert on exception *types*; if any test still asserts `IllegalStateException`, update it to assert `BlueyAndroidError` subclass instead).

- [ ] **Step 6: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ConnectionManagerQueueTest.kt
git commit -m "refactor(bluey_android): ConnectionManager throws use BlueyAndroidError hierarchy"
```

(Only add `ConnectionManagerQueueTest.kt` to the commit if Step 5 required test updates. Otherwise omit it.)

---

## Task 6: Replace throws in `Scanner.kt` + `Advertiser.kt`

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt`
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt`

Same mechanical rewrite pattern. These files have fewer throw sites (~7 combined).

- [ ] **Step 1: Enumerate throws in both files**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" \
  bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt \
  bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt
```

Expected in Scanner.kt:
- `SecurityException("Missing required permissions")` (line ~43)
- `IllegalStateException("Bluetooth not available or disabled")` (line ~51)
- `IllegalStateException("BLE scanner not available")` (line ~61)

Expected in Advertiser.kt:
- `SecurityException("Missing required permissions")` (line ~43)
- `IllegalStateException("Bluetooth adapter not available")` (line ~54)
- `IllegalStateException("BLE advertising not supported")` (line ~60)
- `IllegalStateException(errorMessage)` (line ~146, from onStartFailure callback)

- [ ] **Step 2: Replace Scanner.kt throws**

| Old | New |
|---|---|
| `throw SecurityException("Missing required permissions")` | `throw BlueyAndroidError.PermissionDenied("BLUETOOTH_SCAN")` |
| `throw IllegalStateException("Bluetooth not available or disabled")` | `throw BlueyAndroidError.BluetoothNotAvailableOrDisabled` |
| `throw IllegalStateException("BLE scanner not available")` | `throw BlueyAndroidError.BleScannerNotAvailable` |

(Note: the `SecurityException` message "Missing required permissions" in the current code is generic. If the permission check in Scanner.kt is specifically `BLUETOOTH_SCAN`, use that. Verify by reading the surrounding code — if the permission name is dynamic, pass it via the field: `BlueyAndroidError.PermissionDenied(permName)`.)

- [ ] **Step 3: Replace Advertiser.kt throws**

| Old | New |
|---|---|
| `throw SecurityException("Missing required permissions")` | `throw BlueyAndroidError.PermissionDenied("BLUETOOTH_ADVERTISE")` |
| `throw IllegalStateException("Bluetooth adapter not available")` | `throw BlueyAndroidError.BluetoothAdapterUnavailable` |
| `throw IllegalStateException("BLE advertising not supported")` | `throw BlueyAndroidError.BleAdvertisingNotSupported` |
| `throw IllegalStateException(errorMessage)` (onStartFailure) | `throw BlueyAndroidError.AdvertisingStartFailed(errorMessage)` |

- [ ] **Step 4: Verify no old-pattern throws remain**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" \
  bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt \
  bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt
```
Expected: empty output.

- [ ] **Step 5: Build + test**

```bash
cd bluey_android/android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```
Expected: `BUILD SUCCESSFUL`.

```bash
cd bluey_android/android && ./gradlew test 2>&1 | tail -5
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt \
        bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt
git commit -m "refactor(bluey_android): Scanner + Advertiser throws use BlueyAndroidError hierarchy"
```

---

## Task 7: Replace throws in `GattServer.kt`

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt`

Server-side throws. Same rewrite pattern.

- [ ] **Step 1: Enumerate throws**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt
```

Expected (~8 sites):
- `SecurityException("Missing required permissions")` (line ~67)
- `IllegalStateException("Failed to open GATT server")` (line ~75)
- `IllegalStateException("Failed to add service")` (line ~87)
- `IllegalStateException` for server/characteristic/central lookup failures (lines ~126, 134, 169, 176)
- `IllegalStateException("Failed to add service, status: $status")` (line ~399, from onServiceAdded)

- [ ] **Step 2: Replace each throw**

| Old | New |
|---|---|
| `throw SecurityException("Missing required permissions")` | `throw BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")` (or whichever permission is checked — verify from surrounding code) |
| `throw IllegalStateException("Failed to open GATT server")` | `throw BlueyAndroidError.FailedToOpenGattServer` |
| `throw IllegalStateException("Failed to add service")` | `throw BlueyAndroidError.FailedToAddService(serviceUuid)` (pass the UUID being added) |
| `throw IllegalStateException("Failed to add service, status: $status")` | `throw BlueyAndroidError.FailedToAddService(serviceUuid)` (drop the status field — if the status is useful context, include it in the message via overriding the data class) |
| `throw IllegalStateException("Characteristic not found: $uuid")` | `throw BlueyAndroidError.CharacteristicNotFound(uuid)` |
| `throw IllegalStateException("Central not found: $id")` | `throw BlueyAndroidError.CentralNotFound(id)` |

Any `IllegalStateException("GATT server not initialized")` / similar → `BlueyAndroidError.NotInitialized("GattServer")`.

- [ ] **Step 3: Verify no old-pattern throws remain**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt
```
Expected: empty output.

- [ ] **Step 4: Build + test**

```bash
cd bluey_android/android && ./gradlew test 2>&1 | tail -10
```
Expected: all tests pass. `GattServerTest.kt` may have assertions against `IllegalStateException` — update those to assert the new `BlueyAndroidError` types.

- [ ] **Step 5: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt
git commit -m "refactor(bluey_android): GattServer throws use BlueyAndroidError hierarchy"
```

(Only add the test file to the commit if Step 4 required test updates.)

---

## Task 8: Wrap Pigeon-facing methods in `BlueyPlugin.kt` + replace "not initialized" throws

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt`

Every method in `BlueyPlugin.kt` that implements a Pigeon API method gets wrapped with `try { ... } catch (e: Throwable) { throw e.toClientFlutterError() }` (client-role methods) or `.toServerFlutterError()` (server-role methods dispatching to `GattServer` / `Advertiser`). Also, replace the file's `IllegalStateException("X not initialized")` throws with `BlueyAndroidError.NotInitialized("X")`.

- [ ] **Step 1: Replace "not initialized" throws**

```bash
grep -n "throw IllegalStateException.*not initialized" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt
```
Expected: ~10 matches.

Replace each `throw IllegalStateException("X not initialized")` with `throw BlueyAndroidError.NotInitialized("X")`.

- [ ] **Step 2: Identify client-role vs server-role Pigeon methods**

Pigeon methods that dispatch to `connectionManager` / `scanner` / discovery are client-role. Methods that dispatch to `gattServer` / `advertiser` are server-role.

Read `BlueyPlugin.kt` end-to-end. For each method that overrides a Pigeon host API method, categorise by which backing component it delegates to:
- `connectionManager.xxx(...)` → client-role
- `scanner.xxx(...)` → client-role (Scanner lives in the discovery layer, but the user-facing "central scanning for peers" role is conceptually client)
- `gattServer.xxx(...)` → server-role
- `advertiser.xxx(...)` → server-role
- State query methods (`getBluetoothState`, capability checks) → client-role (these read adapter state, same context)

- [ ] **Step 3: Wrap each method with try/catch**

For every client-role method:

Before:
```kotlin
override fun writeCharacteristic(deviceId: String, characteristicUuid: String, value: ByteArray, withResponse: Boolean, callback: (Result<Unit>) -> Unit) {
    connectionManager?.writeCharacteristic(deviceId, characteristicUuid, value, withResponse, callback)
        ?: callback(Result.failure(BlueyAndroidError.NotInitialized("ConnectionManager")))
}
```

After:
```kotlin
override fun writeCharacteristic(deviceId: String, characteristicUuid: String, value: ByteArray, withResponse: Boolean, callback: (Result<Unit>) -> Unit) {
    try {
        val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
        cm.writeCharacteristic(deviceId, characteristicUuid, value, withResponse) { result ->
            // Translate any thrown exception inside the callback path too.
            callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
        }
    } catch (e: Throwable) {
        callback(Result.failure(e.toClientFlutterError()))
    }
}
```

For server-role methods, use `.toServerFlutterError()` in both the sync catch and the callback recovery.

**Note on callback-style methods:** Pigeon generates async methods with `callback: (Result<T>) -> Unit` parameters. The translation needs to happen in both the synchronous body (pre-dispatch preconditions) AND the callback path (async errors from `GattOpQueue` etc.). The `result.recoverCatching { e -> throw e.toClientFlutterError() }` idiom converts a `Result.failure` carrying any exception into a `Result.failure` carrying a `FlutterError`.

**For synchronous Pigeon methods** (no callback parameter), the pattern is simpler:

Before:
```kotlin
override fun isEnabled(): Boolean {
    return bluetoothAdapter?.isEnabled
        ?: throw IllegalStateException("BluetoothAdapter not initialized")
}
```

After:
```kotlin
override fun isEnabled(): Boolean {
    try {
        return bluetoothAdapter?.isEnabled
            ?: throw BlueyAndroidError.NotInitialized("BluetoothAdapter")
    } catch (e: Throwable) {
        throw e.toClientFlutterError()
    }
}
```

Work through every overridden Pigeon method one at a time. Verify each compiles before moving to the next.

- [ ] **Step 4: Verify the whole file**

```bash
grep -n "throw IllegalStateException\|throw SecurityException" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt
```
Expected: empty output.

```bash
grep -c "toClientFlutterError\|toServerFlutterError" bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt
```
Expected: roughly 2× the number of Pigeon methods (one sync catch + one callback recovery per async method; one catch per sync method).

- [ ] **Step 5: Build + test**

```bash
cd bluey_android/android && ./gradlew test 2>&1 | tail -10
```
Expected: all tests pass. `BlueyPluginTest.kt` may have assertions against specific exception types — update to the new `BlueyAndroidError` / `FlutterError` types.

- [ ] **Step 6: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt \
        bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/BlueyPluginTest.kt
git commit -m "refactor(bluey_android): BlueyPlugin wraps Pigeon methods with FlutterError translation"
```

---

## Task 9: Dart adapter — `bluey-permission-denied` translation

**Files:**
- Modify: `bluey_android/lib/src/android_connection_manager.dart`
- Modify: `bluey_android/test/android_connection_manager_test.dart`

One-line addition to the adapter's translation switch mirroring the existing `gatt-*` cases. Plus one new test.

- [ ] **Step 1: Write the failing test**

Append to `bluey_android/test/android_connection_manager_test.dart` inside its `void main()`. Look at the existing `gatt-timeout` test first to match its style:

```bash
grep -n "bluey-unknown\|gatt-timeout\|PlatformException" bluey_android/test/android_connection_manager_test.dart | head -10
```

Append (adjust variable names to match the existing test file's conventions):

```dart
  group('bluey-permission-denied code translation', () {
    test('writeCharacteristic translates PlatformException(bluey-permission-denied) '
        'to PlatformPermissionDeniedException', () async {
      final hostApi = _MockHostApi();
      final manager = AndroidConnectionManager(hostApi);

      when(() => hostApi.writeCharacteristic(any(), any(), any(), any()))
          .thenThrow(
        PlatformException(
          code: 'bluey-permission-denied',
          message: 'Missing BLUETOOTH_CONNECT permission',
          details: 'BLUETOOTH_CONNECT',
        ),
      );

      await expectLater(
        () => manager.writeCharacteristic(
          'device-1',
          'char-uuid',
          Uint8List.fromList([0x01]),
          true,
        ),
        throwsA(
          isA<PlatformPermissionDeniedException>()
              .having((e) => e.permission, 'permission', 'BLUETOOTH_CONNECT')
              .having((e) => e.operation, 'operation', 'writeCharacteristic'),
        ),
      );
    });
  });
```

If the existing adapter's helper is named differently (e.g. `_translateGattPlatformError`), and the class name differs (e.g. `AndroidConnectionManager` vs `ConnectionManager`), match the existing names.

- [ ] **Step 2: Run to verify RED**

Run: `cd bluey_android && flutter test test/android_connection_manager_test.dart`
Expected: the new test fails — `bluey-permission-denied` isn't matched; the raw `PlatformException` rethrows.

- [ ] **Step 3: Add the translation case**

In `bluey_android/lib/src/android_connection_manager.dart`, find the existing translation helper (search for `gatt-timeout` to locate it). Add a new branch for `bluey-permission-denied` before the final `rethrow`:

```dart
if (e.code == 'bluey-permission-denied') {
  final permission = e.details is String ? e.details as String : 'unknown';
  throw PlatformPermissionDeniedException(
    operation,
    permission: permission,
    message: e.message,
  );
}
```

- [ ] **Step 4: Run to verify GREEN**

Run: `cd bluey_android && flutter test test/android_connection_manager_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Full suites + analyze**

Run: `cd bluey_android && flutter test`
Expected: all tests pass.

Run: `cd bluey && flutter test`
Expected: all tests pass.

Run: `cd bluey_platform_interface && flutter test`
Expected: all tests pass.

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey_android/lib/src/android_connection_manager.dart \
        bluey_android/test/android_connection_manager_test.dart
git commit -m "feat(bluey_android): translate bluey-permission-denied to PlatformPermissionDeniedException"
```

---

## Self-review

After writing the plan, checked against the spec:

| Spec section | Plan task | Coverage |
|---|---|---|
| `PlatformPermissionDeniedException` on platform interface | Task 1 | ✓ |
| `_runGattOp` translates to `PermissionDeniedException` | Task 2 | ✓ |
| `BlueyAndroidError` sealed hierarchy | Task 3 | ✓ |
| `Errors.kt` context-aware extensions | Task 4 | ✓ |
| Every client-side throw → `BlueyAndroidError` (ConnectionManager) | Task 5 | ✓ |
| Every client-side throw → `BlueyAndroidError` (Scanner, Advertiser) | Task 6 | ✓ |
| Every server-side throw → `BlueyAndroidError` (GattServer) | Task 7 | ✓ |
| `BlueyPlugin.kt` wraps Pigeon methods | Task 8 | ✓ |
| `BlueyPlugin.kt` "not initialized" throws | Task 8 | ✓ |
| Dart adapter `bluey-permission-denied` case | Task 9 | ✓ |
| Kotlin unit tests for mappings | Task 4 (ErrorsTest) | ✓ |
| Dart test for new Pigeon code | Task 9 | ✓ |
| Dart test for `_runGattOp` translation | Task 2 | ✓ |
| Regression guard (server `CharacteristicNotFound` ≠ `gatt-disconnected`) | Task 4 (one of the ErrorsTest cases) | ✓ |

No spec requirement unaddressed. No placeholder code. Method / type names (`toClientFlutterError`, `toServerFlutterError`, `BlueyAndroidError.X`, `PlatformPermissionDeniedException`, `PermissionDeniedException`) consistent across tasks.

## Out of scope (per spec)

- iOS changes (done in PR #10).
- Example-app UI changes.
- iOS-client → Android-server stress-test hang investigation.
- Typed exceptions for Bluetooth-adapter-state changes.
