# Lifecycle Timeout Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the lifecycle heartbeat from tearing down the BLE connection on a single synchronous write rejection. Only real evidence of an absent peer (a write timeout) should count toward `_consecutiveFailures`.

**Architecture:** Introduce a typed `GattOperationTimeoutException` in `bluey_platform_interface`. Both Android (Kotlin) and iOS (Swift) timeout `Runnable`s/`DispatchWorkItem`s emit a Pigeon error with a stable `"gatt-timeout"` code; the Dart pass-through layer in each platform package translates that into the typed exception. `LifecycleClient._sendHeartbeat` only increments its failure counter when the caught error is `GattOperationTimeoutException`; all other errors are logged once via the event bus and ignored. Existing `simulateWriteFailure` keeps its name but its meaning shifts to "non-timeout error" (e.g. ill-formed call, characteristic missing); a new `simulateWriteTimeout` covers the timeout case.

**Tech Stack:** Dart (lifecycle, platform interface, pass-through), Kotlin (Android native), Swift (iOS native), Pigeon (codegen, do not regenerate by hand for this plan), `flutter_test` + `mocktail` (Dart tests), `mockk` + JUnit (Kotlin tests), `XCTest` (Swift tests).

---

## File Structure

**New files:**
- `bluey_platform_interface/lib/src/exceptions.dart` — defines `GattOperationTimeoutException`
- `bluey_platform_interface/test/exceptions_test.dart` — tests for the new exception type

**Modified files:**
- `bluey_platform_interface/lib/bluey_platform_interface.dart` — re-export `exceptions.dart`
- `bluey/lib/src/connection/lifecycle_client.dart` — type-discriminated `catchError`
- `bluey/test/fakes/fake_platform.dart` — add `simulateWriteTimeout` field + behavior
- `bluey/test/connection/lifecycle_client_test.dart` — add 3 new tests + update tests #12, #13, #14
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt` — replace 6 timeout `IllegalStateException(...)` constructions with `FlutterError("gatt-timeout", ...)`
- `bluey_android/lib/src/android_connection_manager.dart` — wrap 9 GATT methods to translate `PlatformException(code: 'gatt-timeout')` → `GattOperationTimeoutException`
- `bluey_android/test/android_connection_manager_test.dart` — add translation test per affected method
- `bluey_ios/ios/Classes/CentralManagerImpl.swift` — replace 7 `BlueyError.timeout` failures with `PigeonError(code: "gatt-timeout", ...)`
- `bluey_ios/lib/src/ios_connection_manager.dart` — same translation wrapper as Android
- `bluey_ios/test/ios_connection_manager_test.dart` — add translation test per affected method

**Out of scope for Phase 1:** the Android GATT operation queue (Phase 2). PHY/MTU/connection-parameter timeout paths share the same fix — included.

---

## Task 1: Define `GattOperationTimeoutException` in platform interface

**Files:**
- Create: `bluey_platform_interface/lib/src/exceptions.dart`
- Create: `bluey_platform_interface/test/exceptions_test.dart`
- Modify: `bluey_platform_interface/lib/bluey_platform_interface.dart`

- [ ] **Step 1: Write the failing test**

Create `bluey_platform_interface/test/exceptions_test.dart`:

```dart
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattOperationTimeoutException', () {
    test('exposes the operation name and a default message', () {
      const e = GattOperationTimeoutException('writeCharacteristic');

      expect(e.operation, equals('writeCharacteristic'));
      expect(
        e.toString(),
        contains('writeCharacteristic'),
        reason: 'toString should mention the operation for log readability',
      );
    });

    test('is an Exception so it can be caught with on Exception', () {
      const e = GattOperationTimeoutException('readCharacteristic');
      expect(e, isA<Exception>());
    });

    test('two instances with the same operation are equal', () {
      const a = GattOperationTimeoutException('readCharacteristic');
      const b = GattOperationTimeoutException('readCharacteristic');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```
cd bluey_platform_interface && flutter test test/exceptions_test.dart
```

Expected: FAIL with "Undefined name 'GattOperationTimeoutException'" or "Target of URI doesn't exist".

- [ ] **Step 3: Create the exception class**

Create `bluey_platform_interface/lib/src/exceptions.dart`:

```dart
/// A GATT operation (read, write, descriptor read/write, discoverServices,
/// MTU/PHY/connection-parameter request, etc.) did not complete within its
/// configured timeout.
///
/// This is distinct from synchronous platform errors (e.g. "no operation in
/// progress" rejections) which signal a transient ordering issue rather than
/// an unreachable peer. Callers that monitor liveness — most notably
/// `LifecycleClient` — should only treat instances of this exception as
/// evidence that the remote device is gone.
class GattOperationTimeoutException implements Exception {
  /// Name of the platform interface method that timed out, e.g.
  /// `'writeCharacteristic'`. Used for diagnostics; not parsed by callers.
  final String operation;

  const GattOperationTimeoutException(this.operation);

  @override
  String toString() => 'GattOperationTimeoutException: $operation timed out';

  @override
  bool operator ==(Object other) =>
      other is GattOperationTimeoutException && other.operation == operation;

  @override
  int get hashCode => operation.hashCode;
}
```

- [ ] **Step 4: Re-export from the package's barrel file**

Modify `bluey_platform_interface/lib/bluey_platform_interface.dart` — add one line so the export list reads:

```dart
/// Platform interface for Bluey
///
/// Defines the contract that platform-specific implementations must follow.
/// This follows the Clean Architecture pattern where platform code is
/// an implementation detail that can be swapped.
library bluey_platform_interface;

export 'src/capabilities.dart';
export 'src/exceptions.dart';
export 'src/platform_interface.dart';
```

- [ ] **Step 5: Run test to verify it passes**

```
cd bluey_platform_interface && flutter test test/exceptions_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add bluey_platform_interface/lib/src/exceptions.dart \
        bluey_platform_interface/lib/bluey_platform_interface.dart \
        bluey_platform_interface/test/exceptions_test.dart
git commit -m "$(cat <<'EOF'
feat(platform-interface): add GattOperationTimeoutException

Typed exception lets liveness monitors (LifecycleClient) distinguish
real evidence of an absent peer (timeout) from transient sync failures
(e.g. another GATT op in flight). Phase 1 of the lifecycle resilience
work; subsequent tasks teach the platform impls to throw it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Extend `FakeBlueyPlatform` with `simulateWriteTimeout`

**Files:**
- Modify: `bluey/test/fakes/fake_platform.dart`

This is test infrastructure required before we can write the lifecycle tests in Task 3. We are not changing semantics of `simulateWriteFailure`; we are adding a sibling field for the timeout case.

- [ ] **Step 1: Modify `FakeBlueyPlatform`**

In `bluey/test/fakes/fake_platform.dart`, find the `simulateWriteFailure` declaration (line 88) and add a new field directly below it:

```dart
  /// When true, writeCharacteristic calls will throw to simulate a dead server.
  bool simulateWriteFailure = false;

  /// When true, writeCharacteristic calls will throw a
  /// [GattOperationTimeoutException] to simulate a remote peer that stopped
  /// acknowledging writes. Distinct from [simulateWriteFailure], which
  /// represents non-timeout errors that should NOT be treated as evidence
  /// of an absent peer.
  bool simulateWriteTimeout = false;
```

- [ ] **Step 2: Update `writeCharacteristic` to honour the new field**

In the same file, locate the `writeCharacteristic` override (around line 472). Replace its body so the timeout branch fires before the generic failure branch:

```dart
  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    if (simulateWriteTimeout) {
      throw const GattOperationTimeoutException('writeCharacteristic');
    }
    if (simulateWriteFailure) {
      throw Exception('Write failed: server unreachable');
    }

    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    writeCharacteristicCalls.add(WriteCharacteristicCall(
      deviceId: deviceId,
      characteristicUuid: characteristicUuid,
      value: Uint8List.fromList(value),
      withResponse: withResponse,
    ));

    connection.peripheral.characteristicValues[characteristicUuid] = value;
  }
```

- [ ] **Step 3: Run all existing fake tests to ensure no regression**

```
cd bluey && flutter test test/fakes/
```

Expected: PASS (or "No tests in directory" — fakes don't have their own tests, but this confirms nothing imports broke). Then:

```
cd bluey && flutter test
```

Expected: All existing tests still PASS — we have not changed existing semantics, only added a new opt-in field.

- [ ] **Step 4: Commit**

```bash
git add bluey/test/fakes/fake_platform.dart
git commit -m "$(cat <<'EOF'
test(bluey): add simulateWriteTimeout to FakeBlueyPlatform

Sibling of simulateWriteFailure that throws GattOperationTimeoutException
instead of a generic Exception. Required for the lifecycle tests added
in the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add failing tests for lifecycle's new error discrimination

**Files:**
- Modify: `bluey/test/connection/lifecycle_client_test.dart`

Three new tests that pin down the new behaviour. They will fail until Task 4 lands.

- [ ] **Step 1: Add the three new tests at the end of the existing test group**

Locate the closing braces of the outermost `group('LifecycleClient', ...)` in `bluey/test/connection/lifecycle_client_test.dart` — at the time of writing this is `});` on line 665 followed by `}` on line 666 (closing `main()`). Insert these three new tests **immediately before** that `});` on line 665, keeping them inside the group:

```dart
    // 15. non-timeout heartbeat error does NOT increment failure count
    test(
      'non-timeout heartbeat error does NOT increment failure counter',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 1,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // Initial heartbeat succeeded. Now simulate a non-timeout error
          // (e.g. another GATT op in flight on Android).
          fakePlatform.simulateWriteFailure = true;

          // Even with maxFailedHeartbeats=1, ten consecutive non-timeout
          // errors should NOT trigger onServerUnreachable.
          for (var i = 0; i < 10; i++) {
            async.elapse(const Duration(seconds: 5));
            async.flushMicrotasks();
          }

          expect(unreachableFired, isFalse,
              reason: 'Non-timeout errors are transient and must be ignored');
          expect(client.isRunning, isTrue,
              reason: 'Heartbeat must keep running through non-timeout errors');

          fakePlatform.simulateWriteFailure = false;
          client.stop();
        });
      },
    );

    // 16. timeout heartbeat error DOES increment failure count
    test(
      'timeout heartbeat error fires onServerUnreachable after threshold',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 2,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          fakePlatform.simulateWriteTimeout = true;

          // Timeout 1 — below threshold
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // Timeout 2 — at threshold, should fire
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );

    // 17. mixed timeouts and non-timeouts: only timeouts count
    test(
      'mixed timeouts and non-timeouts: only timeouts count toward threshold',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 3,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // Timeout 1
          fakePlatform.simulateWriteTimeout = true;
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // 5 non-timeout failures interleaved — must NOT advance the counter
          fakePlatform.simulateWriteTimeout = false;
          fakePlatform.simulateWriteFailure = true;
          for (var i = 0; i < 5; i++) {
            async.elapse(const Duration(seconds: 5));
            async.flushMicrotasks();
          }
          expect(unreachableFired, isFalse,
              reason: 'Non-timeout errors must not advance the counter');
          fakePlatform.simulateWriteFailure = false;

          // Timeout 2
          fakePlatform.simulateWriteTimeout = true;
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // Timeout 3 — threshold
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );
```

- [ ] **Step 2: Run the new tests to verify they fail**

```
cd bluey && flutter test test/connection/lifecycle_client_test.dart \
  --name "non-timeout heartbeat error does NOT increment failure counter"
```

Expected: FAIL — current `LifecycleClient` increments on every error, so test 15 will see `unreachableFired == true` and fail.

```
cd bluey && flutter test test/connection/lifecycle_client_test.dart \
  --name "timeout heartbeat error fires onServerUnreachable after threshold"
```

Expected: PASS or FAIL depending on ordering — but this test will PASS coincidentally because the current code treats timeouts as failures too. That's fine; we keep it because Task 4's change must not break it.

```
cd bluey && flutter test test/connection/lifecycle_client_test.dart \
  --name "mixed timeouts and non-timeouts"
```

Expected: FAIL — non-timeout errors currently advance the counter, so the "5 non-timeout failures interleaved" loop trips the threshold prematurely.

- [ ] **Step 3: Commit (red commit, intentional)**

```bash
git add bluey/test/connection/lifecycle_client_test.dart
git commit -m "$(cat <<'EOF'
test(bluey): pin down lifecycle timeout-vs-error discrimination

Three new tests covering the desired behaviour: non-timeout errors are
ignored, timeouts count toward the failure threshold, and a stream of
non-timeouts cannot trip the threshold no matter how many fire.

Tests 15 and 17 fail at this commit by design — Task 4 implements the
fix that turns them green. Test 16 incidentally passes today because
the current code treats timeouts as failures (it just also treats
everything else as a failure).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Make `LifecycleClient._sendHeartbeat` discriminate by exception type

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`

- [ ] **Step 1: Update `_sendHeartbeat`**

In `bluey/lib/src/connection/lifecycle_client.dart`, replace the `_sendHeartbeat` method (currently lines 124–144) with this version:

```dart
  void _sendHeartbeat() {
    final charUuid = _heartbeatCharUuid;
    if (charUuid == null) return;

    _platform
        .writeCharacteristic(
          _connectionId,
          charUuid,
          lifecycle.heartbeatValue,
          true,
        )
        .then((_) {
      _consecutiveFailures = 0;
    }).catchError((Object error) {
      // Only timeouts indicate the remote peer is unreachable. Other errors
      // (e.g. a transient "operation in flight" rejection on Android, or a
      // missing characteristic from a stale GATT cache after Service Changed)
      // are not evidence of absence and must not trip the failure counter.
      if (error is! platform.GattOperationTimeoutException) {
        return;
      }
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxFailedHeartbeats) {
        stop();
        onServerUnreachable();
      }
    });
  }
```

Note: the file already imports `bluey_platform_interface` aliased as `platform`. No new import needed.

- [ ] **Step 2: Run the three new tests — they should now pass**

```
cd bluey && flutter test test/connection/lifecycle_client_test.dart \
  --name "non-timeout heartbeat error does NOT increment failure counter"
cd bluey && flutter test test/connection/lifecycle_client_test.dart \
  --name "timeout heartbeat error fires onServerUnreachable after threshold"
cd bluey && flutter test test/connection/lifecycle_client_test.dart \
  --name "mixed timeouts and non-timeouts"
```

Expected: all three PASS.

- [ ] **Step 3: Run the full lifecycle test file to see what we broke**

```
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: tests 12, 13, and 14 FAIL because they use `simulateWriteFailure` (which now no longer counts as a heartbeat miss). Task 5 fixes them. Do NOT proceed to commit yet — Task 5 finishes the green state.

- [ ] **Step 4: Commit only the lifecycle change**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart
git commit -m "$(cat <<'EOF'
fix(bluey): only count timeouts as heartbeat failures

LifecycleClient was treating any writeCharacteristic error as evidence
of an absent peer, including transient sync rejections from Android's
single-op GATT queue. With the default maxFailedHeartbeats=1 a single
collision with another in-flight op (e.g. service discovery during
Service Changed) was enough to tear the connection down.

Fix: only GattOperationTimeoutException increments _consecutiveFailures.
Other errors are ignored; the next heartbeat tick retries.

Tests 12-14 in lifecycle_client_test now fail because they rely on the
old "any error = failure" semantics. Updated in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Update existing lifecycle tests for new semantics

**Files:**
- Modify: `bluey/test/connection/lifecycle_client_test.dart`

Tests #12, #13, and #14 use `simulateWriteFailure` to drive the failure counter. With the Task 4 change those failures are now silently ignored. The tests still want to verify "the failure counter advances on bad heartbeats" — they just need to use `simulateWriteTimeout` instead.

- [ ] **Step 1: Update Test #12 ("heartbeat success resets failure count")**

In `bluey/test/connection/lifecycle_client_test.dart`, locate test #12 (around line 533). Replace every reference to `simulateWriteFailure` in that test with `simulateWriteTimeout`. Specifically the four occurrences inside the test body — leave the rest of the structure untouched. After the change the test body should read:

```dart
        // Fail 2 heartbeats (below threshold of 3).
        fakePlatform.simulateWriteTimeout = true;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Succeed one heartbeat -- resets failure count.
        fakePlatform.simulateWriteTimeout = false;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Fail 2 more -- still below threshold because count was reset.
        fakePlatform.simulateWriteTimeout = true;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(unreachableFired, isFalse,
            reason: 'Success should have reset the failure counter');

        fakePlatform.simulateWriteTimeout = false;
        client.stop();
```

- [ ] **Step 2: Update Test #13 ("heartbeat failure fires onServerUnreachable after maxFailedHeartbeats")**

Replace `simulateWriteFailure` → `simulateWriteTimeout` in test #13 (around line 581). Two occurrences inside the body.

- [ ] **Step 3: Update Test #14 ("heartbeat failure with default maxFailedHeartbeats=1 fires immediately")**

Same renaming in test #14 (around line 628).

- [ ] **Step 4: Run the full lifecycle test file**

```
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

Expected: ALL tests PASS, including the three new ones from Task 3 and the three updated ones.

- [ ] **Step 5: Run the full bluey test suite to confirm no other lifecycle consumer broke**

```
cd bluey && flutter test
```

Expected: ALL 543+ tests PASS. If any test outside `lifecycle_client_test.dart` fails, STOP — investigate before continuing. Likely candidates are integration tests that exercise the lifecycle indirectly.

- [ ] **Step 6: Commit**

```bash
git add bluey/test/connection/lifecycle_client_test.dart
git commit -m "$(cat <<'EOF'
test(bluey): migrate lifecycle tests to simulateWriteTimeout

Tests 12-14 verify the failure counter mechanic; they need to use the
new timeout simulation now that non-timeout errors are ignored. No
change in what the tests assert — only in how they provoke the failure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Android Kotlin — emit `"gatt-timeout"` code on every timeout `Runnable`

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`

There are seven places where a timeout `Runnable` calls `pendingCallback?.invoke(Result.failure(IllegalStateException(...timed out...)))`. Each must instead pass a `FlutterError` with code `"gatt-timeout"` so the Dart side sees a stable, parseable code.

Note: `FlutterError` is the type defined in the generated `Messages.g.kt` (not Flutter's `io.flutter.plugin.common.PluginRegistry$Registrar`). It is already importable from the same package because `Messages.g.kt` is in `com.neutrinographics.bluey`.

- [ ] **Step 1: Update the seven GATT-op timeout call sites**

Open `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`. Make these seven one-line replacements inside their existing `Runnable` blocks. Line numbers are indicative — search for the exact strings if the file has shifted.

**Edit A — discover services timeout (line 218):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "Service discovery timed out", null)))
```

**Edit B — read characteristic timeout (line 259):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "Read characteristic timed out", null)))
```

**Edit C — write characteristic timeout (line 319):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "Write characteristic timed out", null)))
```

**Edit D — read descriptor timeout (line 422):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "Read descriptor timed out", null)))
```

**Edit E — write descriptor timeout (line 472):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "Write descriptor timed out", null)))
```

**Edit F — MTU request timeout (line 501):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "MTU request timed out", null)))
```

**Edit G — RSSI read timeout (line 530):**

```kotlin
                    pendingCallback?.invoke(Result.failure(FlutterError("gatt-timeout", "RSSI read timed out", null)))
```

**Important — what NOT to change:** the connect timeout (around line 155, `IllegalStateException("Connection timeout")`) is a connection-establishment timeout, not a GATT op timeout. Lifecycle never observes it because there's no connection to host a heartbeat on. Leave it as-is. Same applies to the synchronous "Failed to ..." rejections (e.g. line 313's `"Failed to write characteristic"`) — those represent immediate API rejection, not a timeout, and `LifecycleClient` is now indifferent to them by design.

After the seven edits, run a sanity check to confirm no `timed out` string still ships through `IllegalStateException`:

```
cd bluey_android/android/src/main/kotlin/com/neutrinographics/bluey && grep -n "IllegalStateException.*timed out" ConnectionManager.kt
```

Expected: no output.

- [ ] **Step 2: Compile the Android plugin to verify no syntax errors**

```
cd bluey_android/example && flutter build apk --debug
```

Expected: build succeeds. (`bluey_android` is a plugin and isn't built directly — its example app is the closest compile target.) If the example app folder differs in this repo, substitute `bluey/example`.

- [ ] **Step 3: Commit**

```bash
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt
git commit -m "$(cat <<'EOF'
feat(bluey_android): emit "gatt-timeout" code on GATT op timeouts

Every timeout Runnable in ConnectionManager now produces a typed
FlutterError instead of IllegalStateException, giving the Dart pass-
through layer a stable code to translate into
GattOperationTimeoutException. Connection-level timeouts are
untouched; only GATT operation timeouts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Android Dart pass-through — translate `PlatformException(code: 'gatt-timeout')` to typed exception

**Files:**
- Modify: `bluey_android/lib/src/android_connection_manager.dart`
- Modify: `bluey_android/test/android_connection_manager_test.dart`

- [ ] **Step 1: Write the failing test**

Open `bluey_android/test/android_connection_manager_test.dart`. Add this test inside the existing `group('AndroidConnectionManager', ...)` block. Pick a logical insertion point near the other `writeCharacteristic` tests (search the file for `writeCharacteristic` to find existing tests; if none, add a new `group('writeCharacteristic', ...)` subgroup).

Add at the top of the file if missing:

```dart
import 'package:flutter/services.dart' show PlatformException;
```

Then the test:

```dart
    group('error translation', () {
      test(
        'writeCharacteristic translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.writeCharacteristic(
                any(),
                any(),
                any(),
                any(),
              )).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Write timed out'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'writeCharacteristic')),
          );
        },
      );

      test(
        'writeCharacteristic rethrows non-timeout PlatformException unchanged',
        () async {
          final original = PlatformException(
            code: 'IllegalStateException',
            message: 'Failed to write characteristic',
          );
          when(() => mockHostApi.writeCharacteristic(
                any(),
                any(),
                any(),
                any(),
              )).thenThrow(original);

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(predicate<PlatformException>(
              (e) => e.code == 'IllegalStateException',
            )),
          );
        },
      );

      test(
        'readCharacteristic translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.readCharacteristic(any(), any())).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Read timed out'),
          );

          expect(
            () => connectionManager.readCharacteristic('device-1', 'char-uuid'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'readCharacteristic')),
          );
        },
      );

      test(
        'discoverServices translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.discoverServices(any())).thenThrow(
            PlatformException(
                code: 'gatt-timeout', message: 'Discovery timed out'),
          );

          expect(
            () => connectionManager.discoverServices('device-1'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'discoverServices')),
          );
        },
      );
    });
```

- [ ] **Step 2: Run the new tests to verify they fail**

```
cd bluey_android && flutter test test/android_connection_manager_test.dart \
  --name "error translation"
```

Expected: FAIL — pass-through currently rethrows the `PlatformException` unchanged.

- [ ] **Step 3: Add the translation helper and wrap the GATT methods**

In `bluey_android/lib/src/android_connection_manager.dart`, add this top-level (or static) helper near the imports (just after the imports block):

```dart
/// Catches a [PlatformException] thrown by Pigeon and re-throws it as a
/// [GattOperationTimeoutException] when the platform error code is
/// `'gatt-timeout'`. Other errors propagate unchanged.
///
/// Kept package-private so the same wrapper can be used by every GATT
/// operation in this file without leaking translation logic into the
/// platform interface contract.
Future<T> _translateGattTimeout<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-timeout') {
      throw GattOperationTimeoutException(operation);
    }
    rethrow;
  }
}
```

Then add the import at the top of the file (after the existing imports):

```dart
import 'package:flutter/services.dart' show PlatformException;
```

Now wrap each GATT operation. Replace the bodies of these nine methods with their wrapped versions. Keep the method signatures and docs untouched. (Only the body changes.)

```dart
  @override
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    return _translateGattTimeout('discoverServices', () async {
      final services = await _hostApi.discoverServices(deviceId);
      return services.map(_mapService).toList();
    });
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    return _translateGattTimeout(
      'readCharacteristic',
      () => _hostApi.readCharacteristic(deviceId, characteristicUuid),
    );
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    return _translateGattTimeout(
      'writeCharacteristic',
      () => _hostApi.writeCharacteristic(
        deviceId,
        characteristicUuid,
        value,
        withResponse,
      ),
    );
  }

  @override
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {
    return _translateGattTimeout(
      'setNotification',
      () => _hostApi.setNotification(deviceId, characteristicUuid, enable),
    );
  }

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    return _translateGattTimeout(
      'readDescriptor',
      () => _hostApi.readDescriptor(deviceId, descriptorUuid),
    );
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {
    return _translateGattTimeout(
      'writeDescriptor',
      () => _hostApi.writeDescriptor(deviceId, descriptorUuid, value),
    );
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    return _translateGattTimeout(
      'requestMtu',
      () => _hostApi.requestMtu(deviceId, mtu),
    );
  }

  @override
  Future<int> readRssi(String deviceId) async {
    return _translateGattTimeout(
      'readRssi',
      () => _hostApi.readRssi(deviceId),
    );
  }
```

The `_mapService` helper used by `discoverServices` already exists in the file — keep it. Do NOT wrap the bonding/PHY/connection-parameter stubs that currently return defaults — they don't call the host API so they cannot raise a timeout. Once those methods are implemented they should be wrapped at that time.

- [ ] **Step 4: Run the new tests to verify they pass**

```
cd bluey_android && flutter test test/android_connection_manager_test.dart \
  --name "error translation"
```

Expected: all four error-translation tests PASS.

- [ ] **Step 5: Run the full bluey_android test suite to catch regressions**

```
cd bluey_android && flutter test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add bluey_android/lib/src/android_connection_manager.dart \
        bluey_android/test/android_connection_manager_test.dart
git commit -m "$(cat <<'EOF'
feat(bluey_android): translate "gatt-timeout" to GattOperationTimeoutException

Pass-through methods now translate PlatformException(code: 'gatt-timeout')
into the typed exception from bluey_platform_interface, completing the
Android side of the Phase 1 lifecycle resilience work. Non-timeout
PlatformExceptions propagate unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: iOS Swift — emit `"gatt-timeout"` code on every timeout `DispatchWorkItem`

**Files:**
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift`

There are seven `BlueyError.timeout` failures inside timeout closures in `CentralManagerImpl.swift`. The first (line 181) is the **connect** timeout — leave it alone. The other six are GATT op timeouts; each must become a `PigeonError(code: "gatt-timeout", ...)` so the Dart side sees the same code Android emits.

`PigeonError` is defined in the generated `Messages.g.swift` and is accessible from `CentralManagerImpl.swift` because both are in the `bluey_ios` module.

- [ ] **Step 1: Replace each of the six GATT-op `BlueyError.timeout` failures**

In `bluey_ios/ios/Classes/CentralManagerImpl.swift`, replace each `pendingCompletion(.failure(BlueyError.timeout))` line with the corresponding `PigeonError` below. Line numbers are indicative — search for `BlueyError.timeout` to verify positions if the file has shifted.

**Edit A — discoverServices timeout (line 221):**

```swift
                pendingCompletion(.failure(PigeonError(code: "gatt-timeout", message: "Service discovery timed out", details: nil)))
```

**Edit B — readCharacteristic timeout (line 251):**

```swift
                pendingCompletion(.failure(PigeonError(code: "gatt-timeout", message: "Read characteristic timed out", details: nil)))
```

**Edit C — writeCharacteristic timeout (line 281):**

```swift
                    pendingCompletion(.failure(PigeonError(code: "gatt-timeout", message: "Write characteristic timed out", details: nil)))
```

**Edit D — readDescriptor timeout (line 360):**

```swift
                pendingCompletion(.failure(PigeonError(code: "gatt-timeout", message: "Read descriptor timed out", details: nil)))
```

**Edit E — writeDescriptor timeout (line 388):**

```swift
                pendingCompletion(.failure(PigeonError(code: "gatt-timeout", message: "Write descriptor timed out", details: nil)))
```

**Edit F — readRssi timeout (line 442):**

```swift
                pendingCompletion(.failure(PigeonError(code: "gatt-timeout", message: "RSSI read timed out", details: nil)))
```

**What NOT to change:** the connect timeout at line 181 stays as `BlueyError.timeout` — lifecycle never observes it.

After the six edits, sanity-check that only the connect timeout still uses `BlueyError.timeout`:

```
cd bluey_ios/ios/Classes && grep -n "BlueyError.timeout" CentralManagerImpl.swift
```

Expected: exactly one hit, on the connect timeout (~line 181).

- [ ] **Step 2: Build the iOS plugin's example app**

```
cd bluey/example && flutter build ios --debug --no-codesign
```

Expected: build succeeds. (Use whichever example app the iOS plugin compiles against in this repo.)

- [ ] **Step 3: Commit**

```bash
git add bluey_ios/ios/Classes/CentralManagerImpl.swift
git commit -m "$(cat <<'EOF'
feat(bluey_ios): emit "gatt-timeout" code on GATT op timeouts

Symmetry with bluey_android: every GATT operation timeout now produces
PigeonError(code: "gatt-timeout") so the Dart pass-through can translate
to GattOperationTimeoutException. Connection-level timeouts (CBCentral
connect) are untouched.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: iOS Dart pass-through — translate `PlatformException(code: 'gatt-timeout')` to typed exception

**Files:**
- Modify: `bluey_ios/lib/src/ios_connection_manager.dart`
- Modify: `bluey_ios/test/ios_connection_manager_test.dart`

Mirror image of Task 7 on the iOS side. The same translation helper, applied to the same set of GATT methods.

- [ ] **Step 1: Write the failing test**

Open `bluey_ios/test/ios_connection_manager_test.dart`. Add a `group('error translation', ...)` block following the same structure as the Android test. Add `import 'package:flutter/services.dart' show PlatformException;` at the top if not present.

```dart
    group('error translation', () {
      test(
        'writeCharacteristic translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.writeCharacteristic(
                any(),
                any(),
                any(),
                any(),
              )).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Write timed out'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'writeCharacteristic')),
          );
        },
      );

      test(
        'writeCharacteristic rethrows non-timeout PlatformException unchanged',
        () async {
          final original = PlatformException(
            code: 'BlueyError',
            message: 'Some other failure',
          );
          when(() => mockHostApi.writeCharacteristic(
                any(),
                any(),
                any(),
                any(),
              )).thenThrow(original);

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(predicate<PlatformException>(
              (e) => e.code == 'BlueyError',
            )),
          );
        },
      );

      test(
        'readCharacteristic translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.readCharacteristic(any(), any())).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Read timed out'),
          );

          expect(
            () => connectionManager.readCharacteristic('device-1', 'char-uuid'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'readCharacteristic')),
          );
        },
      );

      test(
        'discoverServices translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.discoverServices(any())).thenThrow(
            PlatformException(
                code: 'gatt-timeout', message: 'Discovery timed out'),
          );

          expect(
            () => connectionManager.discoverServices('device-1'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'discoverServices')),
          );
        },
      );
    });
```

- [ ] **Step 2: Run the new tests to verify they fail**

```
cd bluey_ios && flutter test test/ios_connection_manager_test.dart \
  --name "error translation"
```

Expected: FAIL.

- [ ] **Step 3: Add the helper and wrap iOS pass-through methods**

In `bluey_ios/lib/src/ios_connection_manager.dart`, add the same helper used in Android (paste verbatim — DRY across packages is fine because each plugin owns its translation):

```dart
import 'package:flutter/services.dart' show PlatformException;

// (existing imports stay)

/// Catches a [PlatformException] thrown by Pigeon and re-throws it as a
/// [GattOperationTimeoutException] when the platform error code is
/// `'gatt-timeout'`. Other errors propagate unchanged.
Future<T> _translateGattTimeout<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-timeout') {
      throw GattOperationTimeoutException(operation);
    }
    rethrow;
  }
}
```

Then wrap the same set of methods in `IosConnectionManager`. The list mirrors Android: `discoverServices`, `readCharacteristic`, `writeCharacteristic`, `setNotification`, `readDescriptor`, `writeDescriptor`, `readRssi`. (iOS has no `requestMtu` GATT op — MTU is auto-negotiated. Skip it. iOS also has no `requestPhy` / `requestConnectionParameters` — skip them.)

For each method, replace the body so the `_hostApi.X(...)` call is wrapped in `_translateGattTimeout('X', () => _hostApi.X(...))`. Example for `writeCharacteristic`:

```dart
  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    return _translateGattTimeout(
      'writeCharacteristic',
      () => _hostApi.writeCharacteristic(
        deviceId,
        characteristicUuid,
        value,
        withResponse,
      ),
    );
  }
```

- [ ] **Step 4: Run the new tests to verify they pass**

```
cd bluey_ios && flutter test test/ios_connection_manager_test.dart \
  --name "error translation"
```

Expected: all four error-translation tests PASS.

- [ ] **Step 5: Run the full bluey_ios test suite**

```
cd bluey_ios && flutter test
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add bluey_ios/lib/src/ios_connection_manager.dart \
        bluey_ios/test/ios_connection_manager_test.dart
git commit -m "$(cat <<'EOF'
feat(bluey_ios): translate "gatt-timeout" to GattOperationTimeoutException

Mirror of the Android pass-through translation. Completes Phase 1
lifecycle resilience: LifecycleClient on either platform now sees a
typed timeout exception and only counts those toward its failure
threshold.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Whole-repo verification + manual device test

**Files:** none (verification only).

- [ ] **Step 1: Run every package's test suite**

```
cd bluey_platform_interface && flutter test
```
Expected: PASS.

```
cd bluey && flutter test
```
Expected: PASS — all 543+ tests including the 3 new lifecycle tests.

```
cd bluey_android && flutter test
```
Expected: PASS — including the 4 new error-translation tests.

```
cd bluey_ios && flutter test
```
Expected: PASS — including the 4 new error-translation tests.

```
flutter analyze
```
Expected: no issues.

- [ ] **Step 2: Reproduce the original bug scenario manually**

Hand off to the human partner — this requires two physical devices.

Setup: install the example app on both an Android device and an iOS device. On iOS, start the server and begin advertising. On Android, scan for the iOS server and connect.

Watch the Android log (`flutter logs` or `adb logcat`) for:

- The `[Bluey] [Connection] Connected to ...` line should appear
- There should be NO `disconnect called from: #0 BlueyConnection.disconnect ... LifecycleClient._sendHeartbeat` stack trace line
- The connection should remain stable through service discovery, Service Changed indications, and at least one full heartbeat interval (10 seconds default)

Then: subscribe to a characteristic in the example app, send a notification from the iOS side, read the value from Android. The connection should NOT drop.

If the connection still drops with a `_sendHeartbeat` stack trace, Phase 1 is incomplete — investigate. If it drops via a different code path, that's a different bug; document it and continue.

- [ ] **Step 3: Document the manual test result**

The user runs the manual test and confirms (or denies) the fix works. No commit on this step — just the verbal/written confirmation.

---

## Phase 2 follow-up

Phase 2 (the Android GATT operation queue) is **not** in this plan. It's the more substantial fix: it eliminates the synchronous `gatt.writeCharacteristic returns false` failures at their source instead of just teaching the lifecycle to ignore them. Phase 1 makes the system resilient to those failures; Phase 2 prevents them. Plan Phase 2 separately once Phase 1 ships.
