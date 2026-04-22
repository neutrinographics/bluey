# iOS Error Consistency + Stress-Test MTU Prologue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the iOS-specific escape hatch so raw `PlatformException` never reaches user code from any GATT op, and add an MTU prologue to stress tests so first-run bursts don't fail before MTU auto-negotiates up.

**Architecture:** Every iOS error path (both `BlueyError` enum cases and `CBATTErrorDomain` NSError codes) is translated to a `PigeonError` with one of the well-known `gatt-*` codes on the Swift side. The Dart platform adapter gets one new case for `bluey-unknown`. The core library extends `BlueyPlatformException` with a `code` field and adds a defensive `PlatformException` catch-all in `_runGattOp`. The example app's stress tests gain an MTU prologue and surface the platform code in the failure breakdown.

**Tech Stack:** Swift 5 (CoreBluetooth, Pigeon), Dart 3.7+, Flutter, XCTest (iOS native tests), `flutter_test`, `mocktail`.

**Spec:** `docs/superpowers/specs/2026-04-23-ios-error-consistency-and-mtu-prologue-design.md`

---

## File map

### New files

```
bluey_ios/ios/Classes/NSError+Pigeon.swift                              (Task 4)
bluey_ios/example/ios/RunnerTests/BlueyErrorPigeonTests.swift           (Task 3)
bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift              (Task 4)
bluey_ios/example/ios/RunnerTests/PeripheralManagerErrorTests.swift     (Task 6)
```

### Modified files

```
bluey/lib/src/shared/exceptions.dart                                    (Task 1)
bluey/test/shared/exceptions_test.dart                                  (Task 1)

bluey/lib/src/connection/bluey_connection.dart                          (Task 2)
bluey/test/connection/bluey_connection_test.dart                        (Task 2)

bluey_ios/ios/Classes/BlueyError.swift                                  (Task 3)

bluey_ios/ios/Classes/CentralManagerImpl.swift                          (Task 5)

bluey_ios/ios/Classes/PeripheralManagerImpl.swift                       (Task 6)

bluey_ios/lib/src/ios_connection_manager.dart                           (Task 7)
bluey_ios/test/ios_connection_manager_test.dart                         (Task 7)

bluey/lib/src/connection/lifecycle_client.dart                          (Task 8)
bluey/test/connection/lifecycle_client_test.dart                        (Task 8)

bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart  (Task 9)
```

---

## Task 1: Extend `BlueyPlatformException` with `code` field

**Files:**
- Modify: `bluey/lib/src/shared/exceptions.dart` (around line 255)
- Modify: `bluey/test/shared/exceptions_test.dart` (append)

Adds an optional `code` parameter so callers can disambiguate platform errors without introducing new exception subtypes. Backwards compatible — existing positional-message callers keep working.

- [ ] **Step 1: Write the failing test**

Append to `bluey/test/shared/exceptions_test.dart`:

```dart
// Add to the end of the file, inside the same `void main() { ... }` block.

  group('BlueyPlatformException', () {
    test('exposes message, code, and cause', () {
      final cause = Exception('underlying');
      final e = BlueyPlatformException('boom', code: 'widget-broke', cause: cause);
      expect(e.message, 'boom');
      expect(e.code, 'widget-broke');
      expect(e.cause, same(cause));
    });

    test('code is optional and defaults to null', () {
      final e = BlueyPlatformException('boom');
      expect(e.code, isNull);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd bluey && flutter test test/shared/exceptions_test.dart`
Expected: compile failure — named parameter `code` not defined on `BlueyPlatformException`.

- [ ] **Step 3: Extend `BlueyPlatformException` with the `code` field**

Replace the class at `bluey/lib/src/shared/exceptions.dart:254-258`:

```dart
/// Generic platform exception for errors that don't fit other categories.
///
/// [code] is the platform-originated error code (e.g. a Pigeon error code
/// like `'bluey-unknown'`, or an iOS `NSError`/`PlatformException` code
/// pass-through from the defensive catch-all in `_runGattOp`). Null when
/// the exception is constructed without a known code.
class BlueyPlatformException extends BlueyException {
  final String? code;

  BlueyPlatformException(String message, {this.code, Object? cause})
    : super(message, cause: cause);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd bluey && flutter test test/shared/exceptions_test.dart`
Expected: all tests pass, including the two new ones.

- [ ] **Step 5: Full-suite smoke**

Run: `cd bluey && flutter test`
Expected: all tests pass (existing callers use the positional constructor which still works).

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/shared/exceptions.dart bluey/test/shared/exceptions_test.dart
git commit -m "feat(bluey): BlueyPlatformException gains optional code field"
```

---

## Task 2: `_runGattOp` defensive `PlatformException` catch-all

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart` (around line 30–47)
- Modify: `bluey/test/connection/bluey_connection_test.dart` (append)

Adds a final `on PlatformException catch (e)` that wraps any residual `PlatformException` as `BlueyPlatformException(code, cause)`. This is the backstop: even if the platform adapter or Swift mapper misses a case, the user never sees raw `PlatformException`.

- [ ] **Step 1: Add the failing test**

Find the end of `bluey/test/connection/bluey_connection_test.dart` and look for its `void main()` block. Append inside `void main()`:

```dart
  group('_runGattOp defensive PlatformException catch-all', () {
    test('wraps untranslated PlatformException as BlueyPlatformException', () async {
      final platform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = platform;

      platform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withReadable(TestUuids.customChar1, value: Uint8List.fromList([0x01]))
              .build(),
        ],
      );
      await platform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      // Inject a raw PlatformException that won't match any gatt-* code.
      platform.simulateReadError(
        PlatformException(code: 'fictitious-code', message: 'fake platform error'),
      );

      final char = BlueyRemoteCharacteristic(
        platform: platform,
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
        fail('expected BlueyPlatformException');
      } on BlueyPlatformException catch (e) {
        expect(e.code, 'fictitious-code');
        expect(e.message, contains('fake platform error'));
      }
    });
  });
```

Imports to add at the top of the test file if not already present:

```dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show PlatformException;
import 'package:bluey/src/shared/exceptions.dart';
```

Verify the `FakeBlueyPlatform` has a `simulateReadError(Object error)` hook. If not, add it. Search first:

```bash
cd bluey && grep -n "simulateReadError\|simulateWriteTimeout\|simulateWriteError" test/fakes/fake_platform.dart
```

If `simulateReadError` doesn't exist but the fake has a similar hook pattern (e.g. `simulateWriteTimeout`), add this minimal sibling — there's already precedent for a simulator-error flag. Extend `FakeBlueyPlatform` so its `readCharacteristic` implementation:

```dart
// Inside FakeBlueyPlatform, alongside existing simulate flags:
Object? _pendingReadError;

/// Next readCharacteristic call throws this error; then the flag clears.
void simulateReadError(Object error) {
  _pendingReadError = error;
}

// In the existing readCharacteristic override:
@override
Future<Uint8List> readCharacteristic(String deviceId, String characteristicUuid) async {
  final pending = _pendingReadError;
  if (pending != null) {
    _pendingReadError = null;
    throw pending;
  }
  // ... existing logic ...
}
```

- [ ] **Step 2: Run to verify RED**

Run: `cd bluey && flutter test test/connection/bluey_connection_test.dart`
Expected: the new test fails because `PlatformException(code:'fictitious-code')` propagates unchanged (user sees raw `PlatformException`, not `BlueyPlatformException`).

- [ ] **Step 3: Add the catch-all to `_runGattOp`**

In `bluey/lib/src/connection/bluey_connection.dart`, replace the body of `_runGattOp` (starts around line 30) with:

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
  } on PlatformException catch (e) {
    // Defensive backstop: any PlatformException that wasn't translated by
    // the platform adapter (e.g. a new native error code we haven't yet
    // mapped) gets wrapped so user code only ever catches BlueyException.
    throw BlueyPlatformException(
      e.message ?? 'platform error (${e.code})',
      code: e.code,
      cause: e,
    );
  }
}
```

Add the import at the top if missing:

```dart
import 'package:flutter/services.dart' show PlatformException;
```

- [ ] **Step 4: Run to verify GREEN**

Run: `cd bluey && flutter test test/connection/bluey_connection_test.dart`
Expected: the new test passes.

- [ ] **Step 5: Full-suite smoke + analyze**

Run: `cd bluey && flutter test`
Expected: all tests pass.

Run: `cd bluey && flutter analyze`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/bluey_connection.dart \
        bluey/test/connection/bluey_connection_test.dart \
        bluey/test/fakes/fake_platform.dart
git commit -m "feat(bluey): _runGattOp wraps untranslated PlatformException as BlueyPlatformException"
```

---

## Task 3: Swift `BlueyError` Pigeon translation helpers

**Files:**
- Modify: `bluey_ios/ios/Classes/BlueyError.swift`
- Create: `bluey_ios/example/ios/RunnerTests/BlueyErrorPigeonTests.swift`

Adds `toClientPigeonError()` and `toServerPigeonError()` extension methods on `BlueyError`. Removes the unused `.illegalArgument` case. Every call site in the two Impl files will adopt these in Tasks 5 and 6.

- [ ] **Step 1: Write the failing Swift test**

Create `bluey_ios/example/ios/RunnerTests/BlueyErrorPigeonTests.swift`:

```swift
import XCTest
@testable import bluey_ios

final class BlueyErrorPigeonTests: XCTestCase {

  // MARK: - Client-side mappings

  func testNotFound_asClient_mapsToGattDisconnected() {
    let err = BlueyError.notFound.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-disconnected")
  }

  func testNotConnected_asClient_mapsToGattDisconnected() {
    let err = BlueyError.notConnected.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-disconnected")
  }

  func testUnsupported_asClient_mapsToGattStatusFailed0x06() {
    let err = BlueyError.unsupported.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x06)
  }

  func testTimeout_asClient_mapsToGattTimeout() {
    let err = BlueyError.timeout.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-timeout")
  }

  func testUnknown_asClient_mapsToBlueyUnknown() {
    let err = BlueyError.unknown.toClientPigeonError()
    XCTAssertEqual(err.code, "bluey-unknown")
  }

  // MARK: - Server-side mappings

  func testNotFound_asServer_mapsToGattStatusFailed0x0A() {
    let err = BlueyError.notFound.toServerPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x0A)
  }

  func testNotConnected_asServer_mapsToGattStatusFailed0x0A() {
    let err = BlueyError.notConnected.toServerPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x0A)
  }

  func testUnsupported_asServer_mapsToGattStatusFailed0x06() {
    let err = BlueyError.unsupported.toServerPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x06)
  }

  func testUnknown_asServer_mapsToBlueyUnknown() {
    let err = BlueyError.unknown.toServerPigeonError()
    XCTAssertEqual(err.code, "bluey-unknown")
  }
}
```

Add the test file to the Xcode project's `RunnerTests` target. If you are working in a headless environment and cannot open Xcode, edit `bluey_ios/example/ios/Runner.xcodeproj/project.pbxproj` to register the new file:

1. Open Xcode: `open bluey_ios/example/ios/Runner.xcworkspace`
2. Right-click the `RunnerTests` group → Add Files to "Runner"... → pick the new `BlueyErrorPigeonTests.swift` → Make sure only `RunnerTests` target is checked.
3. Save.

If Xcode is unavailable and you must edit `project.pbxproj` by hand: follow the same pattern as `RunnerTests.swift` (search for its PBXFileReference and PBXBuildFile entries, duplicate them for the new file, and add the file reference to the `RunnerTests` PBXSourcesBuildPhase `files = (...)` list). This is mechanical but error-prone; if you cannot verify the edit, report BLOCKED and let the human handle the Xcode edit.

- [ ] **Step 2: Run the Swift tests to verify RED**

Run:
```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/BlueyErrorPigeonTests 2>&1 | tail -30
```

Expected: compile failure — `toClientPigeonError()` and `toServerPigeonError()` are not defined.

If `iPhone 15` isn't available, substitute any running simulator name from `xcrun simctl list devices available | grep iPhone`.

- [ ] **Step 3: Implement the translation extension**

Replace `bluey_ios/ios/Classes/BlueyError.swift` with:

```swift
import Foundation

/// Swift-internal error vocabulary for the Bluey iOS plugin. Never crosses
/// the Pigeon FFI boundary — use `toClientPigeonError()` or
/// `toServerPigeonError()` at the call site to translate into one of the
/// well-known Pigeon error codes Dart knows how to handle.
enum BlueyError: Error {
    case unknown
    case unsupported
    case notConnected
    case notFound
    case timeout
}

extension BlueyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred"
        case .unsupported:
            return "Operation not supported"
        case .notConnected:
            return "Device not connected"
        case .notFound:
            return "Resource not found"
        case .timeout:
            return "Operation timed out"
        }
    }
}

extension BlueyError {
    /// Client-side translation (used by `CentralManagerImpl`). `notFound`
    /// and `notConnected` signal a vanished peer on the client side
    /// (iOS invalidates cached handles synchronously on disconnect), so
    /// they map to `gatt-disconnected` which the Dart lifecycle layer
    /// treats as a dead-peer signal.
    func toClientPigeonError() -> PigeonError {
        switch self {
        case .notFound, .notConnected:
            return PigeonError(code: "gatt-disconnected",
                               message: self.errorDescription,
                               details: nil)
        case .unsupported:
            return PigeonError(code: "gatt-status-failed",
                               message: self.errorDescription,
                               details: 0x06)
        case .timeout:
            return PigeonError(code: "gatt-timeout",
                               message: self.errorDescription,
                               details: nil)
        case .unknown:
            return PigeonError(code: "bluey-unknown",
                               message: self.errorDescription,
                               details: nil)
        }
    }

    /// Server-side translation (used by `PeripheralManagerImpl`). On the
    /// server side, `notFound`/`notConnected` mean "attribute the peer
    /// requested wasn't registered" — a programming error in the user's
    /// hosted-service setup, NOT a disconnect. Map to ATT
    /// ATTRIBUTE_NOT_FOUND (0x0A) so callers see a typed status-failed
    /// exception rather than a fake disconnect.
    func toServerPigeonError() -> PigeonError {
        switch self {
        case .notFound, .notConnected:
            return PigeonError(code: "gatt-status-failed",
                               message: self.errorDescription,
                               details: 0x0A)
        case .unsupported:
            return PigeonError(code: "gatt-status-failed",
                               message: self.errorDescription,
                               details: 0x06)
        case .timeout:
            return PigeonError(code: "gatt-timeout",
                               message: self.errorDescription,
                               details: nil)
        case .unknown:
            return PigeonError(code: "bluey-unknown",
                               message: self.errorDescription,
                               details: nil)
        }
    }
}
```

Note: `PigeonError` is already generated by Pigeon and is visible to this file because `Messages.g.swift` is in the same module. If the compiler complains, add `import Flutter` at the top (it shouldn't be needed — Messages.g.swift already imports it).

- [ ] **Step 4: Run Swift tests to verify GREEN**

Run:
```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/BlueyErrorPigeonTests 2>&1 | tail -10
```

Expected: 9 tests pass.

- [ ] **Step 5: Verify no Dart regressions**

Run: `cd bluey && flutter test`
Expected: all tests pass (no Dart changes yet).

- [ ] **Step 6: Commit**

```bash
git add bluey_ios/ios/Classes/BlueyError.swift \
        bluey_ios/example/ios/RunnerTests/BlueyErrorPigeonTests.swift \
        bluey_ios/example/ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat(bluey_ios): BlueyError gains client/server Pigeon translation helpers

Removes the unused .illegalArgument case and adds two extension methods
that translate each BlueyError into a well-known gatt-* Pigeon code the
Dart adapter already handles. Client-side uses gatt-disconnected for
notFound/notConnected (iOS invalidates cached handles on disconnect);
server-side uses gatt-status-failed(0x0A) (attribute not registered is
a programming error, not a disconnect)."
```

---

## Task 4: Swift `NSError` → `PigeonError` extension for `CBATTErrorDomain`

**Files:**
- Create: `bluey_ios/ios/Classes/NSError+Pigeon.swift`
- Create: `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift`

Translates every `NSError` from CoreBluetooth's `CBATTErrorDomain` to a `gatt-status-failed` `PigeonError` carrying the BLE ATT status byte. Unknown domains/codes fall through to `bluey-unknown`.

- [ ] **Step 1: Write the failing Swift test**

Create `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift`:

```swift
import XCTest
import CoreBluetooth
@testable import bluey_ios

final class CBErrorPigeonTests: XCTestCase {

  private func makeError(code: Int) -> NSError {
    return NSError(domain: CBATTErrorDomain, code: code, userInfo: nil)
  }

  // MARK: - CBATTErrorDomain mapping

  func testInvalidHandle_mapsToStatus0x01() {
    let pe = makeError(code: CBATTError.invalidHandle.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x01)
  }

  func testReadNotPermitted_mapsToStatus0x02() {
    let pe = makeError(code: CBATTError.readNotPermitted.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x02)
  }

  func testWriteNotPermitted_mapsToStatus0x03() {
    let pe = makeError(code: CBATTError.writeNotPermitted.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x03)
  }

  func testInvalidPdu_mapsToStatus0x04() {
    let pe = makeError(code: CBATTError.invalidPdu.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x04)
  }

  func testInsufficientAuthentication_mapsToStatus0x05() {
    let pe = makeError(code: CBATTError.insufficientAuthentication.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x05)
  }

  func testRequestNotSupported_mapsToStatus0x06() {
    let pe = makeError(code: CBATTError.requestNotSupported.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x06)
  }

  func testInvalidOffset_mapsToStatus0x07() {
    let pe = makeError(code: CBATTError.invalidOffset.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x07)
  }

  func testInsufficientAuthorization_mapsToStatus0x08() {
    let pe = makeError(code: CBATTError.insufficientAuthorization.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x08)
  }

  func testAttributeNotFound_mapsToStatus0x0A() {
    let pe = makeError(code: CBATTError.attributeNotFound.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0A)
  }

  func testAttributeNotLong_mapsToStatus0x0B() {
    let pe = makeError(code: CBATTError.attributeNotLong.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0B)
  }

  func testInvalidAttributeValueLength_mapsToStatus0x0D() {
    let pe = makeError(code: CBATTError.invalidAttributeValueLength.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0D)
  }

  func testInsufficientEncryption_mapsToStatus0x0F() {
    let pe = makeError(code: CBATTError.insufficientEncryption.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0F)
  }

  func testInsufficientResources_mapsToStatus0x11() {
    let pe = makeError(code: CBATTError.insufficientResources.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x11)
  }

  // MARK: - Unknown domain/code

  func testUnknownDomain_mapsToBlueyUnknown() {
    let err = NSError(domain: "org.example.Unknown", code: 42, userInfo: nil)
    let pe = err.toPigeonError()
    XCTAssertEqual(pe.code, "bluey-unknown")
  }

  func testUnknownCBATTErrorCode_mapsToBlueyUnknown() {
    // CBATTError code that isn't mapped in our table.
    let err = NSError(domain: CBATTErrorDomain, code: 0xFF, userInfo: nil)
    let pe = err.toPigeonError()
    XCTAssertEqual(pe.code, "bluey-unknown")
  }
}
```

Register the file with the `RunnerTests` target the same way as in Task 3 Step 1 (Xcode GUI or manual `project.pbxproj` edit).

- [ ] **Step 2: Run to verify RED**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/CBErrorPigeonTests 2>&1 | tail -30
```
Expected: compile failure — `toPigeonError()` is not defined on `NSError`.

- [ ] **Step 3: Implement the extension**

Create `bluey_ios/ios/Classes/NSError+Pigeon.swift`:

```swift
import Foundation
import CoreBluetooth

extension NSError {
    /// Translates a CoreBluetooth `NSError` to a `PigeonError` the Dart
    /// adapter already knows how to handle. `CBATTErrorDomain` codes map
    /// to `gatt-status-failed` with the corresponding BLE ATT status
    /// byte (Bluetooth Core Spec v5.3 Vol 3 Part F §3.4.1.1). Any other
    /// domain — or a `CBATTErrorDomain` code we don't recognise — falls
    /// through to `bluey-unknown` so the user still never sees raw
    /// `PlatformException`.
    func toPigeonError() -> PigeonError {
        if self.domain == CBATTErrorDomain, let status = NSError.attStatusByte(for: self.code) {
            return PigeonError(code: "gatt-status-failed",
                               message: self.localizedDescription,
                               details: status)
        }
        return PigeonError(code: "bluey-unknown",
                           message: self.localizedDescription,
                           details: nil)
    }

    /// Maps a `CBATTError` code to its BLE ATT status byte. Returns nil
    /// for codes we don't explicitly recognise so the caller can fall
    /// through to `bluey-unknown`.
    private static func attStatusByte(for code: Int) -> Int? {
        switch code {
        case CBATTError.invalidHandle.rawValue:               return 0x01
        case CBATTError.readNotPermitted.rawValue:            return 0x02
        case CBATTError.writeNotPermitted.rawValue:           return 0x03
        case CBATTError.invalidPdu.rawValue:                  return 0x04
        case CBATTError.insufficientAuthentication.rawValue:  return 0x05
        case CBATTError.requestNotSupported.rawValue:         return 0x06
        case CBATTError.invalidOffset.rawValue:               return 0x07
        case CBATTError.insufficientAuthorization.rawValue:   return 0x08
        case CBATTError.attributeNotFound.rawValue:           return 0x0A
        case CBATTError.attributeNotLong.rawValue:            return 0x0B
        case CBATTError.invalidAttributeValueLength.rawValue: return 0x0D
        case CBATTError.insufficientEncryption.rawValue:      return 0x0F
        case CBATTError.insufficientResources.rawValue:       return 0x11
        default:                                               return nil
        }
    }
}
```

- [ ] **Step 4: Run to verify GREEN**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/CBErrorPigeonTests 2>&1 | tail -10
```
Expected: 15 tests pass.

- [ ] **Step 5: Verify no Dart regressions**

Run: `cd bluey && flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add bluey_ios/ios/Classes/NSError+Pigeon.swift \
        bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift \
        bluey_ios/example/ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat(bluey_ios): NSError.toPigeonError maps CBATTError to gatt-status-failed"
```

---

## Task 5: Wire `CentralManagerImpl.swift` to use the translation helpers

**Files:**
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift`

Replace every `completion(.failure(BlueyError.X))` with `completion(.failure(BlueyError.X.toClientPigeonError()))`. Replace every `completion(.failure(error))` where `error` is an `NSError` from CoreBluetooth with `completion(.failure(error.toPigeonError()))`.

- [ ] **Step 1: Identify every `BlueyError` failure site**

Run:
```bash
grep -n "completion(.failure(BlueyError\." bluey_ios/ios/Classes/CentralManagerImpl.swift
```

Expected output (approximate):
```
123:            completion(.failure(BlueyError.unknown))
130:                completion(.failure(BlueyError.unknown))
134:        completion(.failure(BlueyError.unsupported))
157:            completion(.failure(BlueyError.notFound))
181:                pendingCompletion(.failure(BlueyError.timeout))
190:            completion(.failure(BlueyError.notFound))
202:            completion(.failure(BlueyError.notFound))
207:            completion(.failure(BlueyError.notConnected))
233:            completion(.failure(BlueyError.notFound))
238:            completion(.failure(BlueyError.notConnected))
261:            completion(.failure(BlueyError.notFound))
266:            completion(.failure(BlueyError.notConnected))
298:            completion(.failure(BlueyError.notFound))
303:            completion(.failure(BlueyError.notConnected))
342:            completion(.failure(BlueyError.notFound))
347:            completion(.failure(BlueyError.notConnected))
370:            completion(.failure(BlueyError.notFound))
375:            completion(.failure(BlueyError.notConnected))
```

- [ ] **Step 2: Mechanical replacement**

For every line above, replace e.g. `BlueyError.notFound` with `BlueyError.notFound.toClientPigeonError()`, and `pendingCompletion(.failure(BlueyError.timeout))` with `pendingCompletion(.failure(BlueyError.timeout.toClientPigeonError()))`.

Use a single sed-style pass, verifying each hit:

```bash
cd bluey_ios/ios/Classes
perl -pi -e 's/BlueyError\.([a-zA-Z]+)\)\)/BlueyError.$1.toClientPigeonError()))/g' CentralManagerImpl.swift
```

Expected: each call site becomes `completion(.failure(BlueyError.X.toClientPigeonError()))`. Verify with the same grep as Step 1 — there should now be zero matches of the old pattern:

```bash
grep -n "completion(.failure(BlueyError\." bluey_ios/ios/Classes/CentralManagerImpl.swift
```
Expected: empty output.

```bash
grep -n "BlueyError\.\w*\.toClientPigeonError" bluey_ios/ios/Classes/CentralManagerImpl.swift | wc -l
```
Expected: 18 (or whatever the Step 1 count was).

- [ ] **Step 3: Identify every NSError completion passthrough**

Run:
```bash
grep -n "completion(.failure(error" bluey_ios/ios/Classes/CentralManagerImpl.swift
```

Expected matches (approximate):
```
166:                completion(.failure(error))
492:            completion(.failure(error ?? BlueyError.unknown))
509:        clearPendingCompletions(for: deviceId, error: error ?? BlueyError.unknown)
518:                completion(.failure(error))
538:            completion?(.failure(error))
671:                completion(.failure(error))
705:            completion(.failure(error))
720:            completion(.failure(error))
738:            completion(.failure(error))
768:            completion(.failure(error))
796:            completion(.failure(error))
```

Most are paths where a delegate callback's `error` (type `Error?`) is forwarded. These need to be cast to `NSError` and translated. Note: `error` may be nil on the success path; only the failure branches are relevant. Only transform sites that are unambiguously inside a failure branch — when in doubt, read the surrounding 3 lines.

- [ ] **Step 4: Wrap each NSError completion site**

For each `completion(.failure(error))` site, wrap the error with a nil-guarded conversion. Example transformation:

Before:
```swift
if let error = error {
    completion(.failure(error))
    return
}
```

After:
```swift
if let error = error {
    completion(.failure((error as NSError).toPigeonError()))
    return
}
```

For the combined `error ?? BlueyError.unknown` sites (lines ~492, ~509):

Before:
```swift
completion(.failure(error ?? BlueyError.unknown))
```

After:
```swift
if let nsError = error as NSError? {
    completion(.failure(nsError.toPigeonError()))
} else {
    completion(.failure(BlueyError.unknown.toClientPigeonError()))
}
```

Do this one hit at a time, reading each surrounding block to confirm the transformation preserves semantics. Do NOT use a blind `perl -pi -e`.

- [ ] **Step 5: Build the workspace**

```bash
cd bluey_ios/example/ios && xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Run existing Swift tests**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests 2>&1 | tail -10
```

Expected: all tests pass (9 + 15 = 24 so far).

- [ ] **Step 7: Dart regression smoke**

Run: `cd bluey && flutter test`
Expected: all tests pass (no Dart changes yet, but the integration test harness is unaffected — Dart tests run against `FakeBlueyPlatform`, not real Swift code).

- [ ] **Step 8: Commit**

```bash
git add bluey_ios/ios/Classes/CentralManagerImpl.swift
git commit -m "refactor(bluey_ios): CentralManagerImpl funnels errors through Pigeon translation

Every BlueyError completion now uses toClientPigeonError(); every
CoreBluetooth NSError completion uses NSError.toPigeonError(). Raw
BlueyError and NSError no longer cross the Pigeon FFI boundary from
the central (client) side."
```

---

## Task 6: Wire `PeripheralManagerImpl.swift` + server-side regression test

**Files:**
- Modify: `bluey_ios/ios/Classes/PeripheralManagerImpl.swift`
- Create: `bluey_ios/example/ios/RunnerTests/PeripheralManagerErrorTests.swift`

Same treatment as Task 5 but with `toServerPigeonError()`. Adds a regression test asserting a server-side `BlueyError.notFound` does NOT surface as `gatt-disconnected`.

- [ ] **Step 1: Write the failing regression test**

Create `bluey_ios/example/ios/RunnerTests/PeripheralManagerErrorTests.swift`:

```swift
import XCTest
@testable import bluey_ios

final class PeripheralManagerErrorTests: XCTestCase {

  /// Server-side notFound must map to gatt-status-failed(0x0A), NOT
  /// gatt-disconnected. Mapping it to gatt-disconnected would mean a
  /// server programming error (e.g. responding to a request for an
  /// unregistered characteristic) looks like a peer disappearance on
  /// the Dart side, which confuses the caller and could (if any code
  /// path ever fed such an error into a client-side heartbeat write)
  /// trip LifecycleClient's dead-peer counter.
  func testNotFound_onServerSide_doesNotMapToDisconnected() {
    let pe = BlueyError.notFound.toServerPigeonError()
    XCTAssertNotEqual(pe.code, "gatt-disconnected",
                      "Server-side notFound must not look like a disconnect")
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0A)
  }

  func testNotConnected_onServerSide_doesNotMapToDisconnected() {
    let pe = BlueyError.notConnected.toServerPigeonError()
    XCTAssertNotEqual(pe.code, "gatt-disconnected")
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0A)
  }
}
```

Register with the `RunnerTests` target (see Task 3 Step 1 for instructions).

- [ ] **Step 2: Run to verify GREEN (already)**

The translation helpers were added in Task 3, so these tests should already pass against the current (post-Task-3) code:

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests/PeripheralManagerErrorTests 2>&1 | tail -10
```
Expected: both tests pass. (Note this test exists primarily as a regression guard — it locks the mapping down so nobody accidentally conflates client/server translation in a future refactor.)

- [ ] **Step 3: Identify every failure site in `PeripheralManagerImpl.swift`**

```bash
grep -n "completion(.failure(BlueyError\." bluey_ios/ios/Classes/PeripheralManagerImpl.swift
```

Expected (approximate):
```
66:            completion(.failure(BlueyError.notFound))
114:            completion(.failure(BlueyError.notFound))
124:            completion(.failure(BlueyError.unknown))
131:            completion(.failure(BlueyError.notFound))
136:            completion(.failure(BlueyError.notFound))
144:            completion(.failure(BlueyError.unknown))
152:            completion(.failure(BlueyError.notFound))
166:            completion(.failure(BlueyError.notFound))
```

- [ ] **Step 4: Mechanical replacement**

```bash
cd bluey_ios/ios/Classes
perl -pi -e 's/BlueyError\.([a-zA-Z]+)\)\)/BlueyError.$1.toServerPigeonError()))/g' PeripheralManagerImpl.swift
```

Verify with:
```bash
grep -n "completion(.failure(BlueyError\." bluey_ios/ios/Classes/PeripheralManagerImpl.swift
```
Expected: empty output.

```bash
grep -n "BlueyError\.\w*\.toServerPigeonError" bluey_ios/ios/Classes/PeripheralManagerImpl.swift | wc -l
```
Expected: matches the count from Step 3 (~8).

- [ ] **Step 5: Identify NSError passthrough sites**

```bash
grep -n "completion(.failure(error" bluey_ios/ios/Classes/PeripheralManagerImpl.swift
```

If there are any, wrap with the same pattern as Task 5 Step 4 but using `toPigeonError()` (not `toServerPigeonError()` — `NSError.toPigeonError()` is context-free). Peripheral manager historically has fewer NSError paths than central; confirm each one before editing.

- [ ] **Step 6: Build**

```bash
cd bluey_ios/example/ios && xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Run all Swift tests**

```bash
cd bluey_ios/example/ios && xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:RunnerTests 2>&1 | tail -10
```
Expected: all tests pass (24 + 2 = 26).

- [ ] **Step 8: Dart regression smoke**

Run: `cd bluey && flutter test`
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add bluey_ios/ios/Classes/PeripheralManagerImpl.swift \
        bluey_ios/example/ios/RunnerTests/PeripheralManagerErrorTests.swift \
        bluey_ios/example/ios/Runner.xcodeproj/project.pbxproj
git commit -m "refactor(bluey_ios): PeripheralManagerImpl funnels errors through server Pigeon translation

Server-side BlueyError.notFound / notConnected now surface as
gatt-status-failed(0x0A) rather than gatt-disconnected so a server
programming error (e.g. responding to an unregistered characteristic)
does not look like a peer disconnect on the Dart side. Regression test
locks the client/server mapping distinction down."
```

---

## Task 7: Dart adapter — `bluey-unknown` translation

**Files:**
- Modify: `bluey_ios/lib/src/ios_connection_manager.dart` (around line 30–46)
- Modify: `bluey_ios/test/ios_connection_manager_test.dart` (append)

One-line addition to the existing translation switch so `bluey-unknown` from Swift surfaces as a typed `BlueyPlatformException` (via the core library's adapter layer) rather than leaking as raw `PlatformException`.

- [ ] **Step 1: Write the failing test**

Append to `bluey_ios/test/ios_connection_manager_test.dart` (inside the existing `void main()`):

```dart
  group('bluey-unknown code translation', () {
    test('writeCharacteristic translates PlatformException(bluey-unknown) '
        'to BlueyPlatformException', () async {
      final hostApi = _MockHostApi();
      final manager = IosConnectionManager(hostApi);

      when(() => hostApi.writeCharacteristic(any(), any(), any(), any()))
          .thenThrow(
        PlatformException(code: 'bluey-unknown', message: 'opaque native error'),
      );

      await expectLater(
        () => manager.writeCharacteristic(
          'device-1',
          'char-uuid',
          Uint8List.fromList([0x01]),
          true,
        ),
        throwsA(
          isA<BlueyPlatformException>()
              .having((e) => e.code, 'code', 'unknown')
              .having((e) => e.message, 'message', contains('opaque native error')),
        ),
      );
    });
  });
```

Imports (add to the top of the test file if absent):

```dart
import 'package:bluey/src/shared/exceptions.dart' show BlueyPlatformException;
```

If the test file uses a different mocking setup (search for existing `_MockHostApi` or the pattern used by the existing `gatt-timeout` tests in the file), match the existing style.

- [ ] **Step 2: Run to verify RED**

Run: `cd bluey_ios && flutter test test/ios_connection_manager_test.dart`
Expected: the new test fails — `bluey-unknown` isn't handled by the switch, so the raw `PlatformException` rethrows and the `isA<BlueyPlatformException>()` match fails.

- [ ] **Step 3: Add the translation case**

In `bluey_ios/lib/src/ios_connection_manager.dart`, locate `_translateGattPlatformError` (starts around line 27). Update the body to include a new case before the `rethrow`:

```dart
Future<T> _translateGattPlatformError<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-timeout') {
      throw GattOperationTimeoutException(operation);
    }
    if (e.code == 'gatt-disconnected') {
      throw GattOperationDisconnectedException(operation);
    }
    if (e.code == 'gatt-status-failed') {
      final status = e.details is int ? e.details as int : -1;
      throw GattOperationStatusFailedException(operation, status);
    }
    if (e.code == 'bluey-unknown') {
      throw BlueyPlatformException(
        e.message ?? 'unknown iOS error',
        code: 'unknown',
        cause: e,
      );
    }
    rethrow;
  }
}
```

Add the import at the top of the file:

```dart
import 'package:bluey/src/shared/exceptions.dart' show BlueyPlatformException;
```

- [ ] **Step 4: Run to verify GREEN**

Run: `cd bluey_ios && flutter test test/ios_connection_manager_test.dart`
Expected: all tests pass including the new one.

- [ ] **Step 5: Full suites + analyze**

Run: `cd bluey && flutter test`
Expected: all tests pass.

Run: `cd bluey_ios && flutter test`
Expected: all tests pass.

Run: `flutter analyze bluey_ios`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add bluey_ios/lib/src/ios_connection_manager.dart \
        bluey_ios/test/ios_connection_manager_test.dart
git commit -m "feat(bluey_ios): translate bluey-unknown Pigeon code to BlueyPlatformException"
```

---

## Task 8: Remove legacy `_isDeadPeerSignal` `PlatformException` branches

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart` (around line 210)
- Modify: `bluey/test/connection/lifecycle_client_test.dart` (remove obsolete tests)

After the Swift fix, iOS-side `BlueyError.notFound` / `notConnected` arrive as `GattOperationDisconnectedException` (via `gatt-disconnected`), which is already caught by the existing branch. The legacy `PlatformException(code:'notFound'|'notConnected')` branch is dead — removing it prevents a future bug where someone types `PlatformException(code:'notFound')` into a test and accidentally trips the heartbeat dead-peer counter.

- [ ] **Step 1: Locate the obsolete tests**

```bash
cd bluey && grep -n "PlatformException.*notFound\|PlatformException.*notConnected" test/connection/lifecycle_client_test.dart
```

Expected (approximate):
```
<some line>:            error: PlatformException(code: 'notFound', message: '...'),
<some line>:            error: PlatformException(code: 'notConnected', message: '...'),
```

Identify the surrounding `test('...', ...)` blocks and the group they belong to.

- [ ] **Step 2: Remove the obsolete tests**

Delete the two `test('...')` blocks that feed `PlatformException(code:'notFound')` or `PlatformException(code:'notConnected')` as the simulated error. The existing `GattOperationDisconnectedException` tests (search for `GattOperationDisconnectedException trips onServerUnreachable` or similar) already cover the same functional path post-Swift-fix.

Use `Edit` to remove each `test(...)` block cleanly — be careful with trailing semicolons / commas to keep the enclosing group syntactically valid.

- [ ] **Step 3: Run `lifecycle_client_test.dart` to verify the deletion is clean**

Run: `cd bluey && flutter test test/connection/lifecycle_client_test.dart`
Expected: all remaining tests pass (you just removed two; expect test count to drop by exactly 2).

- [ ] **Step 4: Locate the `_isDeadPeerSignal` legacy branch**

```bash
cd bluey && grep -n "notFound\|notConnected" lib/src/connection/lifecycle_client.dart
```

Expected approximate output:
```
<some line>:    if (error is PlatformException &&
<some line>:        (error.code == 'notFound' || error.code == 'notConnected')) {
<some line>:      return true;
<some line>:    }
```

- [ ] **Step 5: Remove the legacy branch**

Replace the `_isDeadPeerSignal` method body so it no longer matches on `PlatformException` codes:

```dart
  /// Whether [error] is evidence that the peer is no longer reachable.
  ///
  /// Treated as dead-peer signals:
  ///
  /// * [platform.GattOperationTimeoutException] — the peer stopped
  ///   acknowledging within the per-op timeout.
  /// * [platform.GattOperationDisconnectedException] — drained on link
  ///   drop. iOS maps `BlueyError.notFound` / `notConnected` through
  ///   `gatt-disconnected` to this exception so the translation below
  ///   is unchanged from Android's behaviour.
  /// * [platform.GattOperationStatusFailedException] — Android-client→
  ///   iOS-server force-kill path: iOS fires a Service Changed
  ///   indication on the way out, invalidating Android's cached handle;
  ///   every subsequent heartbeat write returns GATT_INVALID_HANDLE
  ///   (0x01). Also covers iOS client→iOS server ATT errors now that
  ///   `CBATTErrorDomain` NSErrors surface as typed.
  bool _isDeadPeerSignal(Object error) {
    if (error is platform.GattOperationTimeoutException) return true;
    if (error is platform.GattOperationDisconnectedException) return true;
    if (error is platform.GattOperationStatusFailedException) return true;
    return false;
  }
```

Also remove any now-unused imports at the top of the file (specifically `import 'package:flutter/services.dart' show PlatformException;` if the only reference was the branch we just deleted — verify with `grep PlatformException bluey/lib/src/connection/lifecycle_client.dart`).

- [ ] **Step 6: Run the full suite**

Run: `cd bluey && flutter test`
Expected: all tests pass (count down by 2 vs. Task 2 baseline).

Run: `cd bluey && flutter analyze`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart \
        bluey/test/connection/lifecycle_client_test.dart
git commit -m "refactor(bluey): remove dead legacy PlatformException branches from _isDeadPeerSignal

iOS now emits gatt-disconnected for BlueyError.notFound / notConnected
via the Swift translation helpers introduced in PR-<this>, so those
codes arrive as GattOperationDisconnectedException (already caught)
rather than raw PlatformException. Drop the legacy branch and the two
tests that exercised the now-unreachable path."
```

---

## Task 9: Stress-test MTU prologue + `BlueyPlatformException` typename display

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`

Extracts the reset prologue into a `_prologue(connection)` helper that first calls `connection.requestMtu(247)` (swallowing failure) then writes `ResetCommand`. Every `run*` method uses the helper. Also updates the failure-recording path to include the platform code in the typename when the exception is `BlueyPlatformException`, so the UI's existing `failuresByType` display shows `BlueyPlatformException(unknown) × N` rather than opaque `BlueyPlatformException × N`.

- [ ] **Step 1: Map the existing prologue shape**

Read `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart` end to end. Every `run*` method (there are 7) has an identical opening pattern:

```dart
final stressChar = await _resolveStressChar(connection);

try {
  await stressChar.write(
      const ResetCommand().encode(), withResponse: true);
} on Object {
  if (!cancelled && !controller.isClosed) {
    controller
        .add(StressTestResult.initial().finished(elapsed: Duration.zero));
  }
  if (!controller.isClosed) await controller.close();
  return;
}
```

- [ ] **Step 2: Add `_prologue` helper**

Inside the `StressTestRunner` class, below the `run*` methods (or above — wherever private helpers live — search for an existing `_resolveStressChar` private method and place the new helper next to it), add:

```dart
  /// Shared prologue for every stress test. Requests a higher MTU so
  /// first-run bursts with >20-byte payloads don't fail before auto-MTU
  /// negotiation completes, then sends `ResetCommand` to zero the
  /// server-side counters. MTU failure is swallowed — not every peer
  /// honours a higher MTU and that's fine; the test still runs (at the
  /// peer's default payload limit).
  ///
  /// Returns true if the reset succeeded; false if the reset failed,
  /// in which case the caller should emit a zero-elapsed final snapshot
  /// and close its stream.
  Future<bool> _prologue(
    Connection connection,
    RemoteCharacteristic stressChar,
  ) async {
    try {
      await connection.requestMtu(247);
    } catch (_) {
      // Swallow — MTU upgrade is best-effort.
    }

    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
      return true;
    } on Object {
      return false;
    }
  }
```

- [ ] **Step 3: Update every `run*` method to use the helper**

For each of the seven `run*` methods (`runBurstWrite`, `runMixedOps`, `runSoak`, `runTimeoutProbe`, `runFailureInjection`, `runMtuProbe`, `runNotificationThroughput`), replace the existing reset prologue (the `try { await stressChar.write(const ResetCommand().encode(), ...) } on Object { ... return; }` block) with:

```dart
          final stressChar = await _resolveStressChar(connection);

          if (!await _prologue(connection, stressChar)) {
            if (!cancelled && !controller.isClosed) {
              controller
                  .add(StressTestResult.initial().finished(elapsed: Duration.zero));
            }
            if (!controller.isClosed) await controller.close();
            return;
          }
```

Do this one method at a time and verify each method compiles before moving on. Do not bulk-edit blindly — the surrounding context per method varies slightly.

**Special case — `runMtuProbe`**: this test already calls `connection.requestMtu(config.requestedMtu)` as part of its measurement. Calling `_prologue` would double the MTU request. Decide in-line: either (a) skip `requestMtu(247)` inside `_prologue` when the caller is `runMtuProbe`, or (b) have `runMtuProbe` not use `_prologue` (call `_resolveStressChar` + the `ResetCommand` write directly).

Go with (b): for `runMtuProbe` only, inline the prologue WITHOUT the MTU bump. Its existing reset-command block stays as-is.

- [ ] **Step 4: Update the failure-recording catch block**

Find every `catch (e) { publish(_OpOutcome.failure(typeName: e.runtimeType.toString(), ...)) }` pattern. For each, update the typename computation so a `BlueyPlatformException` surfaces its code:

```dart
String _typeName(Object e) {
  if (e is BlueyPlatformException) {
    return 'BlueyPlatformException(${e.code ?? 'null'})';
  }
  return e.runtimeType.toString();
}
```

Add this as a top-level (or class-private) helper and update every `typeName: e.runtimeType.toString()` site inside the `run*` methods to `typeName: _typeName(e)`.

The helper goes at the top of the file (outside the class, file-private):

```dart
String _typeName(Object e) {
  if (e is BlueyPlatformException) {
    return 'BlueyPlatformException(${e.code ?? 'null'})';
  }
  return e.runtimeType.toString();
}
```

Add the import at the top of the file if absent:

```dart
import 'package:bluey/src/shared/exceptions.dart' show BlueyPlatformException;
```

(Or `import 'package:bluey/bluey.dart' show BlueyPlatformException;` if it's re-exported from the public barrel — check which pattern the file currently uses.)

- [ ] **Step 5: Run existing stress-test-runner tests**

Look for existing tests that exercise `StressTestRunner`:
```bash
cd bluey/example && find test -name "*stress*" 2>/dev/null
```

If none exist, skip this step. If any exist, run them:
```bash
cd bluey/example && flutter test test/<path-to-stress-runner-test>
```
Expected: all tests pass. If a test asserts on the typename (e.g. `'PlatformException'`), it will need updating to match the new format — make that update inline.

- [ ] **Step 6: Flutter analyze + full test suite**

Run: `cd bluey/example && flutter analyze`
Expected: No issues found.

Run: `cd bluey && flutter test` (the core library tests — unaffected by example-app changes but run as a smoke).
Expected: all tests pass.

- [ ] **Step 7: Manual smoke on device (not strictly required for commit)**

Per the spec's verification section:
- Build & run `cd bluey/example && flutter run` on an Android client with an iOS server (or simulate the scenario).
- Run the burst-write stress test immediately after connect. Expected: most/all ops succeed on first run. Previously many failed.
- If any fail, the UI failure breakdown now shows the typed exception + ATT status code instead of opaque `PlatformException × N`.

This manual verification isn't gated on the implementer — note it in the PR description for the human reviewer to confirm.

- [ ] **Step 8: Commit**

```bash
git add bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart
git commit -m "feat(example): stress tests request MTU(247) upfront; display platform code on failure

- Shared _prologue() helper calls connection.requestMtu(247) (best
  effort) then writes ResetCommand. Every run* method uses it except
  runMtuProbe, which handles MTU as part of its measurement.
- Failure typename for BlueyPlatformException now includes the code
  so the UI shows 'BlueyPlatformException(unknown) × N' instead of
  opaque 'BlueyPlatformException × N'.

Together with the iOS translation helpers, this eliminates the
first-run burst failure mode and makes any remaining failures
diagnosable at a glance via the ATT status code display."
```

---

## Self-review

After writing this plan, checked against the spec sections:

| Spec section | Plan task | Coverage |
|---|---|---|
| Goals / Architecture — 4 layers of change | Tasks 1–9 cover all 4 layers | ✓ |
| Non-goals | Not planned (cancellation, new exception types, Android rework, UI redesign) | ✓ |
| Error mapping — `BlueyError` client/server context | Task 3 | ✓ |
| Error mapping — `NSError`/`CBATTErrorDomain` | Task 4 | ✓ |
| Error mapping — Dart adapter `bluey-unknown` | Task 7 | ✓ |
| Error mapping — core library catch-all | Task 2 | ✓ |
| `BlueyPlatformException.code` field | Task 1 | ✓ |
| CentralManagerImpl wiring | Task 5 | ✓ |
| PeripheralManagerImpl wiring | Task 6 | ✓ |
| Remove unused `BlueyError.illegalArgument` | Task 3 (done in the rewrite) | ✓ |
| Stress-test MTU prologue | Task 9 | ✓ |
| Stress-test typename display | Task 9 | ✓ |
| Remove `_isDeadPeerSignal` legacy branch | Task 8 | ✓ |
| Testing — Swift `BlueyError` mappings | Task 3 (BlueyErrorPigeonTests) | ✓ |
| Testing — Swift `NSError` mappings | Task 4 (CBErrorPigeonTests) | ✓ |
| Testing — Dart adapter new code | Task 7 | ✓ |
| Testing — `BlueyPlatformException.code` | Task 1 | ✓ |
| Testing — `_runGattOp` catch-all | Task 2 | ✓ |
| Testing — lifecycle_client cleanup | Task 8 | ✓ |
| Testing — regression guard for server `notFound` | Task 6 (PeripheralManagerErrorTests) | ✓ |
| Risk — false-disconnect from server `notFound` | Task 6 regression test | ✓ |
| Risk — unmapped `CBATTError` | Task 4 unknown-domain test | ✓ |
| Risk — `requestMtu` failure | Task 9 swallows it | ✓ |

No spec requirement left unaddressed. No placeholder code. Method / type names (`toClientPigeonError`, `toServerPigeonError`, `toPigeonError`, `_prologue`, `_typeName`, `BlueyPlatformException.code`) are consistent across tasks.

## Out of scope (per spec)

- In-flight GATT op cancellation.
- New `BlueyException` subtypes beyond extending `BlueyPlatformException`.
- Android-side error audit.
