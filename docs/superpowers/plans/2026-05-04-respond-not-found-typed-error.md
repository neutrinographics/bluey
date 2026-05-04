# Respond-not-found typed error chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the unhandled-exception crash that fires when `LifecycleServer.handleReadRequest` issues a fire-and-forget `_platform.respondToReadRequest(...)` call against a `requestId` the iOS plugin no longer has in `pendingReadRequests`. Plumb a typed exception end-to-end so `lifecycle_server.dart` can log-and-move-on for the *expected* race ("request id not found") while still surfacing *unexpected* failures as errors.

**Architecture:** Mirrors I313's typed-error pattern. New `PlatformRespondToRequestNotFoundException` at the platform-interface; iOS adapter wraps `_hostApi.respondToReadRequest` and translates the existing `bluey-not-found` Pigeon code; `error_translation.dart` translates to a new domain `RespondNotFoundException extends BlueyException`; `lifecycle_server.dart` wraps the two `respondToReadRequest` call sites in `unawaited(... .catchError(...))` matching the *domain* type only — no platform-interface types leak into domain code. Anti-corruption layer respected (no contribution to I308).

The duplicate-response root cause (why the same requestId is responded to twice in the first place) is filed separately as I322 and not addressed in this PR. This plan delivers defense-in-depth + observability so the field signal arrives cleanly while root cause is investigated.

**Tech Stack:** Dart 3, Pigeon, Swift, `flutter_test`.

---

## File Structure

**Platform interface (`bluey_platform_interface/`):**
- `lib/src/exceptions.dart` — add `PlatformRespondToRequestNotFoundException`.
- `test/exceptions_test.dart` — exception tests.

**iOS plugin (`bluey_ios/`):**
- `lib/src/ios_server.dart` — wrap `_hostApi.respondToReadRequest`; translate `bluey-not-found` to typed exception.
- `test/ios_server_advertise_test.dart` — extend with translation test (or add a new file `test/ios_server_respond_test.dart` if convention prefers per-method test files; check neighbours).

**Domain (`bluey/`):**
- `lib/src/shared/exceptions.dart` — add `RespondNotFoundException extends BlueyException`.
- `lib/src/shared/error_translation.dart` — add translation branch.
- `lib/src/gatt_server/lifecycle_server.dart` — wrap the two `respondToReadRequest` calls (lines ~146 and ~159) with `unawaited(... .catchError(...))` matching `RespondNotFoundException`. Add branch+UUID diagnostic logs.
- `test/shared/error_translation_test.dart` — translation test.
- `test/exceptions_test.dart` — domain exception test.
- `test/gatt_server/lifecycle_server_test.dart` — defensive-path tests.

**Docs:**
- `docs/backlog/I322-duplicate-respond-to-request.md` — file the root cause for follow-up.
- `docs/backlog/README.md` — index entry.

**Out of scope:**
- Symmetric `respondToWriteRequest` fix (filed in I322 — the same translation should apply, but lifecycle_server.dart's write-side `respondToWriteRequest` call site is at a different layer and writes have a different test profile).
- Android plugin's analogous code path (filed in I322 — Android's plugin has a similar pending-request map; verify and apply the same translator there for consistency).
- Fixing the duplicate-response root cause (filed in I322 — likely BlueyServer multi-subscription, hot-reload-resilience audit).

---

## Task 1: Platform-interface — `PlatformRespondToRequestNotFoundException`

**Files:**
- Modify: `bluey_platform_interface/lib/src/exceptions.dart`
- Test: `bluey_platform_interface/test/exceptions_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `bluey_platform_interface/test/exceptions_test.dart` (mirror the existing `PlatformAdvertiseDataTooLargeException` group structure — that's the I313 precedent):

```dart
  group('PlatformRespondToRequestNotFoundException', () {
    test('toString includes the message and class name', () {
      const e = PlatformRespondToRequestNotFoundException('requestId 42 not found');
      expect(e.toString(), contains('PlatformRespondToRequestNotFoundException'));
      expect(e.toString(), contains('requestId 42 not found'));
    });

    test('two instances with the same message are equal', () {
      const a = PlatformRespondToRequestNotFoundException('msg');
      const b = PlatformRespondToRequestNotFoundException('msg');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs by message', () {
      const a = PlatformRespondToRequestNotFoundException('a');
      const b = PlatformRespondToRequestNotFoundException('b');
      expect(a, isNot(equals(b)));
    });

    test('exposes the message via the public field', () {
      const e = PlatformRespondToRequestNotFoundException('boom');
      expect(e.message, equals('boom'));
    });

    test('is catchable as Exception', () {
      const e = PlatformRespondToRequestNotFoundException('whatever');
      expect(e, isA<Exception>());
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey_platform_interface && flutter test test/exceptions_test.dart
```

Expected: FAIL — `'PlatformRespondToRequestNotFoundException' isn't a type`.

- [ ] **Step 3: Add the exception**

Append to `bluey_platform_interface/lib/src/exceptions.dart` (mirror `PlatformAdvertiseDataTooLargeException`'s shape exactly — same equality idiom, same `implements Exception`, same field doc style):

```dart

/// Raised when a server-side `respondToReadRequest` or
/// `respondToWriteRequest` call references a `requestId` the platform
/// plugin no longer has on file.
///
/// On iOS this is the surface of `BlueyError.notFound` from
/// `PeripheralManagerImpl.respondToReadRequest` (or `respondToWriteRequest`)
/// when the corresponding entry has already been removed from
/// `pendingReadRequests` / `pendingWriteRequests`. Common cause: a
/// duplicate response on the Dart side (a request was emitted on
/// the platform's broadcast `readRequests` stream, two subscribers
/// both responded; the second one hits "not found"). Less commonly,
/// a `closeServer` raced an in-flight respond.
///
/// The domain layer translates this to `RespondNotFoundException`. Surface
/// this typed form instead of generic `bluey-unknown` so the lifecycle
/// server can distinguish the *expected race* (warn-and-move-on) from
/// *unexpected respond failures* (error-level, surface for triage).
class PlatformRespondToRequestNotFoundException implements Exception {
  /// Human-readable description of the missing request id, if the
  /// underlying platform plugin provided one.
  final String message;

  const PlatformRespondToRequestNotFoundException(this.message);

  @override
  String toString() =>
      'PlatformRespondToRequestNotFoundException: $message';

  @override
  bool operator ==(Object other) =>
      other is PlatformRespondToRequestNotFoundException &&
          other.message == message;

  @override
  int get hashCode => message.hashCode;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey_platform_interface && flutter test
```

Expected: PASS — all existing tests + 5 new tests.

- [ ] **Step 5: Commit**

```bash
git add bluey_platform_interface/lib/src/exceptions.dart \
        bluey_platform_interface/test/exceptions_test.dart
git commit -m "feat(platform-interface): add PlatformRespondToRequestNotFoundException (I322 prep)"
```

---

## Task 2: iOS adapter — translate `bluey-not-found` to typed exception

The iOS plugin already returns the `bluey-not-found` Pigeon code from `respondToReadRequest` when the requestId is missing (`PeripheralManagerImpl.swift:296`, `BlueyError.notFound.toServerPigeonError()`). This task wires the Dart-side translation: the bluey_ios adapter catches the `PlatformException` with that code and re-throws `PlatformRespondToRequestNotFoundException`.

**Files:**
- Modify: `bluey_ios/lib/src/ios_server.dart`
- Test: `bluey_ios/test/ios_server_respond_test.dart` (CREATE)

- [ ] **Step 1: Locate the existing `respondToReadRequest` call site in the iOS adapter**

```bash
grep -n "respondToReadRequest\|_hostApi" bluey_ios/lib/src/ios_server.dart
```

Find the existing thin wrapper (likely `Future<void> respondToReadRequest(...) async => _hostApi.respondToReadRequest(...);` or similar). The wrapper either passes through unchanged or has a try/catch — match the existing style.

- [ ] **Step 2: Confirm the iOS plugin's `BlueyError.notFound` Pigeon code**

```bash
grep -n "notFound\|toServerPigeonError\|bluey-not-found" bluey_ios/ios/Classes/Errors.swift bluey_ios/ios/Classes/PeripheralManagerImpl.swift
```

Note the exact Pigeon code string (likely `'bluey-not-found'`). The Dart-side `if (e.code == ...)` branch must match exactly.

- [ ] **Step 3: Write the failing test**

Create `bluey_ios/test/ios_server_respond_test.dart`. Mirror the structure of the existing `ios_server_advertise_test.dart` — same `MockBlueyHostApi` (defined in `test/mocks.dart`), same `setUpAll(registerFallbackValue(...))`, same mocktail patterns:

```dart
import 'package:bluey_ios/src/ios_server.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  setUpAll(() {
    // Match the fallback registrations already used by ios_server_advertise_test.dart.
    registerFallbackValue(AdvertiseConfigDto(
      serviceUuids: const [],
      scanResponseServiceUuids: const [],
    ));
  });

  group('IosServer.respondToReadRequest — error translation', () {
    test(
      'PlatformException(bluey-not-found) -> PlatformRespondToRequestNotFoundException',
      () async {
        final mockHostApi = MockBlueyHostApi();
        when(() => mockHostApi.respondToReadRequest(any(), any(), any())).thenThrow(
          PlatformException(
            code: 'bluey-not-found',
            message: 'requestId 42 not found',
          ),
        );
        final server = IosServer(mockHostApi);

        await expectLater(
          server.respondToReadRequest(
            42,
            PlatformGattStatus.success,
            null,
          ),
          throwsA(
            isA<PlatformRespondToRequestNotFoundException>().having(
              (e) => e.message,
              'message',
              'requestId 42 not found',
            ),
          ),
        );
      },
    );

    test(
      'other PlatformException codes propagate unchanged (regression guard)',
      () async {
        final mockHostApi = MockBlueyHostApi();
        when(() => mockHostApi.respondToReadRequest(any(), any(), any())).thenThrow(
          PlatformException(
            code: 'bluey-unknown',
            message: 'something else',
          ),
        );
        final server = IosServer(mockHostApi);

        await expectLater(
          server.respondToReadRequest(99, PlatformGattStatus.success, null),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'bluey-unknown')),
        );
      },
    );
  });
}
```

**Adapt** the call signature in `server.respondToReadRequest(...)` to match the actual `IosServer.respondToReadRequest` signature — read the file in Step 1 and mirror exactly.

- [ ] **Step 4: Run test to verify it fails**

```bash
cd bluey_ios && flutter test test/ios_server_respond_test.dart
```

Expected: FAIL — translation isn't in place; the raw PlatformException propagates.

- [ ] **Step 5: Wrap `_hostApi.respondToReadRequest` in `IosServer`**

In `bluey_ios/lib/src/ios_server.dart`, replace the existing `respondToReadRequest` method (or add a try/on-PlatformException wrapper to the existing implementation, matching the I313 pattern in `bluey_android/lib/src/android_server.dart:startAdvertising`):

```dart
  /// Responds to a pending read request from a connected central.
  ///
  /// Translates the Pigeon `'bluey-not-found'` error code to the typed
  /// [PlatformRespondToRequestNotFoundException] (raised when the
  /// requestId is no longer in the iOS plugin's `pendingReadRequests`
  /// map — typically a duplicate-response race; see I322). Other
  /// `PlatformException`s propagate unchanged.
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    try {
      await _hostApi.respondToReadRequest(
        requestId,
        _mapStatusToDto(status),
        value,
      );
    } on PlatformException catch (e) {
      if (e.code == 'bluey-not-found') {
        throw PlatformRespondToRequestNotFoundException(e.message ?? '');
      }
      rethrow;
    }
  }
```

If `flutter/services.dart` import (`PlatformException`) isn't already present, add it.

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd bluey_ios && flutter test
```

Expected: PASS — all existing tests + 2 new tests.

- [ ] **Step 7: Commit**

```bash
git add bluey_ios/lib/src/ios_server.dart \
        bluey_ios/test/ios_server_respond_test.dart
git commit -m "feat(ios): typed not-found -> PlatformRespondToRequestNotFoundException (I322 prep)"
```

---

## Task 3: Domain — `RespondNotFoundException`

**Files:**
- Modify: `bluey/lib/src/shared/exceptions.dart`
- Test: `bluey/test/exceptions_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `bluey/test/exceptions_test.dart`:

```dart
  group('RespondNotFoundException', () {
    test('extends BlueyException', () {
      const e = RespondNotFoundException('requestId 42');
      expect(e, isA<BlueyException>());
    });

    test('toString includes the operation context', () {
      const e = RespondNotFoundException('requestId 42 missing');
      expect(e.toString(), contains('RespondNotFoundException'));
    });

    test('exposes the message via the public field', () {
      const e = RespondNotFoundException('requestId 42 missing');
      expect(e.message, contains('requestId 42 missing'));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey && flutter test test/exceptions_test.dart
```

Expected: FAIL — `'RespondNotFoundException' isn't a type`.

- [ ] **Step 3: Add the exception**

In `bluey/lib/src/shared/exceptions.dart`, add (place near the other server-side exceptions like `ServerRespondFailedException`):

```dart

/// The platform plugin no longer has the `requestId` referenced in a
/// `respondToReadRequest` / `respondToWriteRequest` call.
///
/// Indicates an *expected race*: the most likely cause is a duplicate
/// response on the Dart side (e.g. the platform's broadcast
/// `readRequests` stream had two subscribers, both invoked
/// `respondToReadRequest` with the same id; the second one hits "not
/// found"). The lifecycle server logs this at warn level and continues.
/// Apps should not need to react to it directly. See I322 for the
/// duplicate-response root-cause investigation.
class RespondNotFoundException extends BlueyException {
  const RespondNotFoundException(String message)
    : super(
        'Server respond failed: $message',
        action:
            'Likely a duplicate response on the Dart side (broadcast '
            'stream multi-subscription); safe to log and continue.',
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey && flutter test test/exceptions_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/shared/exceptions.dart \
        bluey/test/exceptions_test.dart
git commit -m "feat(domain): add RespondNotFoundException (I322 prep)"
```

---

## Task 4: Domain — translate platform-interface to domain exception

**Files:**
- Modify: `bluey/lib/src/shared/error_translation.dart`
- Test: `bluey/test/shared/error_translation_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `bluey/test/shared/error_translation_test.dart` (inside the existing `translatePlatformException` group):

```dart
    test(
      'PlatformRespondToRequestNotFoundException -> RespondNotFoundException',
      () {
        const platformError = PlatformRespondToRequestNotFoundException(
          'requestId 42 not found',
        );
        final translated = translatePlatformException(
          platformError,
          operation: 'respondToReadRequest',
        );
        expect(translated, isA<RespondNotFoundException>());
        expect(
          (translated as RespondNotFoundException).message,
          contains('requestId 42 not found'),
        );
      },
    );
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey && flutter test test/shared/error_translation_test.dart --name "RespondNotFound"
```

Expected: FAIL — translation falls into the catch-all `BlueyPlatformException` branch.

- [ ] **Step 3: Add the translation branch**

In `bluey/lib/src/shared/error_translation.dart`, inside `translatePlatformException`, add a branch (after the I313 `PlatformAdvertiseDataTooLargeException` branch, before the catch-all `PlatformException` branch):

```dart
  if (error is platform.PlatformRespondToRequestNotFoundException) {
    return RespondNotFoundException(error.message);
  }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey && flutter test test/shared/error_translation_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the full bluey suite**

```bash
cd bluey && flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/shared/error_translation.dart \
        bluey/test/shared/error_translation_test.dart
git commit -m "feat(domain): translate PlatformRespondToRequestNotFoundException -> RespondNotFoundException (I322 prep)"
```

---

## Task 5: `lifecycle_server.dart` — wrap fire-and-forget responds with typed `.catchError`

The two `respondToReadRequest` call sites in `lifecycle_server.dart` (lines 146-150 and 159-163) currently fire-and-forget. After Tasks 1-4, an unhandled future from those calls can produce a typed `RespondNotFoundException` (or any other domain exception). Wrap both in `unawaited(... .catchError((Object e, StackTrace st) { ... }))` matching the *domain* type — anti-corruption layer respected, no platform-interface types in domain code.

**Files:**
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart`
- Test: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `bluey/test/gatt_server/lifecycle_server_test.dart` (find the existing `LifecycleServer` group and add a new sub-group):

```dart
    group('respond fire-and-forget — error containment', () {
      test(
        'serverId read: RespondNotFoundException is caught and logged at warn, no crash',
        () async {
          // Configure the fake platform to throw RespondNotFoundException when
          // respondToReadRequest is called. This simulates a duplicate-response
          // race surfaced through the typed-exception chain.
          fakePlatform.respondToReadFailure = const RespondNotFoundException(
            'requestId 42 not found',
          );

          final logger = testLogger();
          final logs = <BlueyLogEvent>[];
          logger.events.listen(logs.add);

          final server = LifecycleServer(
            platformApi: fakePlatform,
            interval: const Duration(seconds: 5),
            serverId: ServerId.generate(),
            onClientGone: (_) {},
            logger: logger,
          );

          // handleReadRequest dispatches synchronously; the unawaited respond
          // future may fail asynchronously. We pump the event loop so any
          // catchError handler runs.
          server.handleReadRequest(_readReq(
            characteristicUuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
          ));
          await Future<void>.delayed(Duration.zero);

          // The handler returned true (handled the request).
          // The respond future failed but was caught — no unhandled exception.
          // A warn-level log entry was emitted.
          final warns = logs.where((e) => e.level == BlueyLogLevel.warn).toList();
          expect(warns, isNotEmpty,
              reason: 'RespondNotFoundException must be logged at warn level');
          expect(
            warns.last.context,
            equals('bluey.server.lifecycle'),
          );
          expect(
            warns.last.message.toLowerCase(),
            contains('respond'),
          );

          server.dispose();
        },
      );

      test(
        'interval read: same warn-and-continue path',
        () async {
          fakePlatform.respondToReadFailure = const RespondNotFoundException(
            'requestId 99 not found',
          );

          final logger = testLogger();
          final logs = <BlueyLogEvent>[];
          logger.events.listen(logs.add);

          final server = LifecycleServer(
            platformApi: fakePlatform,
            interval: const Duration(seconds: 5),
            serverId: ServerId.generate(),
            onClientGone: (_) {},
            logger: logger,
          );

          server.handleReadRequest(_readReq(
            characteristicUuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
          ));
          await Future<void>.delayed(Duration.zero);

          final warns = logs.where((e) => e.level == BlueyLogLevel.warn).toList();
          expect(warns, isNotEmpty);

          server.dispose();
        },
      );

      test(
        'unexpected (non-RespondNotFound) error logs at error level, no crash',
        () async {
          fakePlatform.respondToReadFailure = const BlueyPlatformException(
            'native crashed mid-flight',
            code: 'bluey-unknown',
          );

          final logger = testLogger();
          final logs = <BlueyLogEvent>[];
          logger.events.listen(logs.add);

          final server = LifecycleServer(
            platformApi: fakePlatform,
            interval: const Duration(seconds: 5),
            serverId: ServerId.generate(),
            onClientGone: (_) {},
            logger: logger,
          );

          server.handleReadRequest(_readReq(
            characteristicUuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
          ));
          await Future<void>.delayed(Duration.zero);

          final errors = logs.where((e) => e.level == BlueyLogLevel.error).toList();
          expect(errors, isNotEmpty,
              reason: 'unexpected respond failure must surface at error level');

          server.dispose();
        },
      );
    });
```

The test assumes `FakeBlueyPlatform` has a `respondToReadFailure` field that can be set to inject an exception when `respondToReadRequest` is called. **Inspect the fake first**:

```bash
grep -n "respondToReadRequest\|respondToReadFailure" bluey/test/fakes/fake_platform.dart
```

If the fake's `respondToReadRequest` doesn't currently support failure injection, add a single field:

```dart
/// Test seam: when non-null, the next [respondToReadRequest] call
/// completes with this error instead of recording the response. Reset
/// to null after consuming. Lets tests verify the lifecycle server's
/// catchError path without contriving a real Pigeon failure.
Object? respondToReadFailure;

@override
Future<void> respondToReadRequest(int requestId, PlatformGattStatus status, Uint8List? value) async {
  final injectedFailure = respondToReadFailure;
  if (injectedFailure != null) {
    respondToReadFailure = null;  // consume — one-shot.
    throw injectedFailure;
  }
  // ... existing implementation.
}
```

Match the existing fake's `respondToReadRequest` shape exactly — the example above is a sketch, not literal.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart --name "fire-and-forget"
```

Expected: FAIL — currently the fake's exception escapes as an unhandled future, OR the `catchError` handler isn't in place.

- [ ] **Step 3: Wrap the two respond call sites in `lifecycle_server.dart`**

In `bluey/lib/src/gatt_server/lifecycle_server.dart`, replace:

```dart
  bool handleReadRequest(platform.PlatformReadRequest req) {
    final uuid = req.characteristicUuid.toLowerCase();

    if (uuid == lifecycle.serverIdCharUuid) {
      _platform.respondToReadRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
        lifecycle.lifecycleCodec.encodeAdvertisedIdentity(_serverId),
      );
      return true;
    }

    if (!lifecycle.isControlServiceCharacteristic(uuid)) {
      return false;
    }

    final interval = _interval ?? lifecycle.defaultLifecycleInterval;
    _platform.respondToReadRequest(
      req.requestId,
      platform.PlatformGattStatus.success,
      lifecycle.encodeInterval(interval),
    );

    return true;
  }
```

with:

```dart
  bool handleReadRequest(platform.PlatformReadRequest req) {
    final uuid = req.characteristicUuid.toLowerCase();

    if (uuid == lifecycle.serverIdCharUuid) {
      _respondAndContain(
        req: req,
        branch: 'serverId',
        value: lifecycle.lifecycleCodec.encodeAdvertisedIdentity(_serverId),
      );
      return true;
    }

    if (!lifecycle.isControlServiceCharacteristic(uuid)) {
      return false;
    }

    final interval = _interval ?? lifecycle.defaultLifecycleInterval;
    _respondAndContain(
      req: req,
      branch: 'interval',
      value: lifecycle.encodeInterval(interval),
    );

    return true;
  }

  /// Issues a fire-and-forget read response and contains failures.
  ///
  /// `RespondNotFoundException` (translated from the platform's typed
  /// not-found code) is the *expected race* — duplicate response on the
  /// Dart side (see I322); logged at warn. Any other failure is
  /// unexpected and logged at error so it shows up in observability.
  ///
  /// Always returns synchronously (the underlying respond future is
  /// `unawaited` to preserve the synchronous `handleReadRequest`
  /// contract). The diagnostic log on success/expected-failure carries
  /// the branch + characteristic UUID so a future maintainer
  /// investigating I322 can correlate by id.
  void _respondAndContain({
    required platform.PlatformReadRequest req,
    required String branch,
    required Uint8List value,
  }) {
    _logger.log(
      BlueyLogLevel.trace,
      'bluey.server.lifecycle',
      'respond entered',
      data: {
        'requestId': req.requestId,
        'characteristicUuid': req.characteristicUuid,
        'branch': branch,
      },
    );
    unawaited(
      _platform.respondToReadRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
        value,
      ).then((_) {}, onError: (Object e, StackTrace st) {
        final translated = translatePlatformException(
          e,
          operation: 'respondToReadRequest',
        );
        if (translated is RespondNotFoundException) {
          _logger.log(
            BlueyLogLevel.warn,
            'bluey.server.lifecycle',
            'respond skipped — request id not found '
                '(likely duplicate response; see I322)',
            data: {
              'requestId': req.requestId,
              'characteristicUuid': req.characteristicUuid,
              'branch': branch,
            },
            errorCode: 'respond-not-found',
          );
          return;
        }
        _logger.log(
          BlueyLogLevel.error,
          'bluey.server.lifecycle',
          'respond failed unexpectedly',
          data: {
            'requestId': req.requestId,
            'characteristicUuid': req.characteristicUuid,
            'branch': branch,
            'exception': translated.runtimeType.toString(),
          },
          errorCode: translated.runtimeType.toString(),
        );
      }),
    );
  }
```

Add the necessary imports at the top:

```dart
import 'dart:async';  // unawaited

import '../shared/error_translation.dart';
import '../shared/exceptions.dart';
```

(The `error_translation` and `exceptions` imports may already be present — only add what's missing. Check via `head -30 bluey/lib/src/gatt_server/lifecycle_server.dart`.)

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart
```

Expected: PASS — all three new sub-group tests green.

- [ ] **Step 5: Run the full bluey suite**

```bash
cd bluey && flutter test
```

Expected: PASS — all 885+ tests still green.

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/gatt_server/lifecycle_server.dart \
        bluey/test/gatt_server/lifecycle_server_test.dart \
        bluey/test/fakes/fake_platform.dart
git commit -m "fix(lifecycle): contain unhandled async exception from fire-and-forget respondToReadRequest"
```

---

## Task 6: Diagnostic logs — branch + UUID in `handleReadRequest`

The `_respondAndContain` helper added in Task 5 already logs the branch + UUID on entry (trace) and on failure (warn/error). For successful responses, the branch is currently silent. Add a debug-level log on the synchronous part so the branch is observable even when the respond succeeds — this lets I322 investigators correlate by characteristic UUID without waiting for a failure.

Decision: the trace log on entry already provides this. **Do not add an additional log** — the entry trace covers the success case.

This task is therefore a **no-op confirmation** that Task 5's implementation already covers diagnostic visibility. Verify by reading the Task 5 diff:

- [ ] **Step 1: Confirm the trace log is on the synchronous entry path**

```bash
grep -n "trace\|TRACE\|BlueyLogLevel.trace" bluey/lib/src/gatt_server/lifecycle_server.dart
```

Expected: a `BlueyLogLevel.trace` log inside `_respondAndContain` carrying `requestId`, `characteristicUuid`, and `branch`.

- [ ] **Step 2: No code change required**

If the Task 5 implementation matches the plan's `_respondAndContain` snippet, this task is complete. Move to Task 7.

If it diverges (e.g., the implementer chose a different log level), discuss before changing — trace might be too noisy for production but might be the right fit for "I322 investigation observability."

---

## Task 7: Backlog — file I322 (root cause investigation)

**Files:**
- Create: `docs/backlog/I322-duplicate-respond-to-request.md`
- Modify: `docs/backlog/README.md` (add to Open — domain layer or appropriate section)

- [ ] **Step 1: Write the backlog entry**

Create `docs/backlog/I322-duplicate-respond-to-request.md`:

```markdown
---
id: I322
title: `LifecycleServer.handleReadRequest` invoked twice for the same request id; second `respondToReadRequest` fails with `RespondNotFoundException`
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-05-04
related: [I308]
---

## Symptom

In production a connected Android central → iOS server pair, after the
I313 cross-platform discovery fix, exhibits a recurring crash with the
following signature on the iOS server side:

```
[WARN ] bluey.ios.peripheral: respondToReadRequest: requestId not found
        {requestId: <id>} err=not-found
[ERROR] (unhandled) PlatformException(bluey-not-found, ...)
```

The crash fires at a deterministic ~30-second cadence — matching the
discovery probe frequency on the central side. Each discovery round
issues a read on `b1e70004` (the lifecycle `serverId` characteristic).

The proximate cause is a fire-and-forget `_platform.respondToReadRequest`
in `LifecycleServer.handleReadRequest`. The defensive containment
(typed-exception chain + warn/error log) shipped with this entry; that
work stops the crash but does not address the underlying issue: **why
is the lifecycle handler responding to the same `requestId` more than
once**?

## Location

- `bluey/lib/src/gatt_server/lifecycle_server.dart:142-176` — the
  containment is in place; the duplicate-invocation root cause is
  upstream.
- `bluey_ios/lib/src/ios_server.dart:20-21` — `_readRequestsController`
  is a *broadcast* `StreamController`; multiple subscribers all receive
  every emission.
- `bluey/lib/src/gatt_server/bluey_server.dart` — `BlueyServer`
  subscribes to `_platform.readRequests` in its constructor and only
  cancels the subscription in `dispose()`.

## Root cause (hypotheses, ranked)

**1. Multi-subscriber on the broadcast `readRequests` stream.** If two
`BlueyServer` instances are alive simultaneously, both subscribe to
`_platform.readRequests` and both invoke
`LifecycleServer.handleReadRequest(req)` for each emission. Both
attempt `respondToReadRequest(req.requestId, ...)` — first wins, second
hits "not found." Plausible scenarios:

- Hot reload (Flutter rebuilds Dart-side state but the iOS native
  plugin's `_readRequestsController` survives across reloads, so the
  old `BlueyServer`'s subscription stays alive while a new one
  registers).
- An app-level path that constructs a second `BlueyServer` without
  disposing the first (audit `bluey.example/lib/features/server/`
  callsites).
- A `dispose-without-await` race that returns control before the
  subscription is fully canceled.

**2. Duplicate emission from the platform side.** The iOS plugin's
`didReceiveRead` always assigns a fresh `requestId` (incrementing
counter) and calls `flutterApi.onReadRequest(...)` once per
`CBATTRequest`. Pigeon's `flutterApi.onReadRequest` is generated to
deliver each call exactly once. **Unlikely**, but worth ruling out by
adding a unique-id check in `_readRequestsController.add(...)`.

**3. `closeServer` racing in-flight responds.** Possible but should
fire only on teardown; doesn't fit the steady-state cadence. Low
probability.

## Notes

**Defense-in-depth shipped (this PR):** the typed-exception chain
(`PlatformRespondToRequestNotFoundException` → `RespondNotFoundException`)
plus `_respondAndContain` in `lifecycle_server.dart` log warn-and-move-on
on the expected race and surface unexpected failures at error level. App
code no longer crashes on this. The trace-level log on entry carries
`requestId`, `characteristicUuid`, and `branch` (`serverId` /
`interval`) so investigators can correlate.

**Symmetric `respondToWriteRequest`:** lifecycle_server.dart's
`handleWriteRequest` (around line 81-86) also calls
`_platform.respondToWriteRequest` fire-and-forget. The same
defense-in-depth should apply. Out of scope for the current PR;
schedule as a small follow-up commit.

**Android equivalent:** the Android plugin has an analogous
pending-request map. Verify the equivalent error code propagates
through `_translateGattPlatformError` (or its server-side counterpart)
and add the same `PlatformRespondToRequestNotFoundException`
translation. Without it, Android servers that hit the same
multi-subscriber issue would still crash with a generic
`bluey-unknown`. Out of scope for the current PR; small follow-up.

**Investigation plan:**

1. Capture a fresh failure with the new trace log enabled. Confirm the
   `branch` and `characteristicUuid` consistently match (i.e., it's
   always the same characteristic firing).

2. Add a duplicate-emission guard at the platform-interface layer
   (debug build only): if the same `req.requestId` is observed on
   `_platform.readRequests` more than once within ~1 second, log at
   error level. This will distinguish hypothesis 1 from hypothesis 2.

3. Audit `BlueyServer` lifecycle:
   - Does `dispose()` await `_platformReadRequestsSub?.cancel()`? Yes,
     verified — but does the example app actually await
     `BlueyServer.dispose()` before constructing a new one?
   - Hot reload: does the iOS plugin re-init `_readRequestsController`
     on `BlueyPlugin.handleHotRestart` (or equivalent)? Audit.

4. Once root cause is identified, implement the fix and remove the
   `// see I322` comment from `lifecycle_server.dart`'s
   `_respondAndContain`.

External references:
- BLE Core Specification 5.4 Vol 3 Part F — ATT request/response semantics.
```

- [ ] **Step 2: Add to README index**

In `docs/backlog/README.md`, find the "Open — domain layer" section and add an entry:

```markdown
| [I322](I322-duplicate-respond-to-request.md) | `LifecycleServer.handleReadRequest` invoked twice for the same request id; defensive containment shipped, root cause pending | medium |
```

(Match the column / formatting of neighbouring entries.)

- [ ] **Step 3: Commit**

```bash
git add docs/backlog/I322-duplicate-respond-to-request.md \
        docs/backlog/README.md
git commit -m "docs: file I322 — duplicate respondToReadRequest (root cause follow-up)"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run the full workspace test suite**

```bash
cd bluey && flutter test
cd ../bluey_platform_interface && flutter test
cd ../bluey_android && flutter test
cd ../bluey_ios && flutter test
```

Expected: all four packages PASS.

- [ ] **Step 2: Run `flutter analyze`**

```bash
cd /Users/joel/git/neutrinographics/bluey/.worktrees/respond-not-found-typed-error && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Push and open PR**

```bash
git push -u origin feature/respond-not-found-typed-error
gh pr create --title "Contain fire-and-forget respond-not-found crash; typed exception chain (I322 prep)" --body "..."
```

PR body should reference: the user-reported crash, the I322 backlog entry's root-cause hypotheses, the I313 typed-error precedent, and the test counts.

---

## Out of scope

- **Symmetric `respondToWriteRequest` containment** — same pattern, separate small commit. Tracked in I322 notes.
- **Android plugin's analogous translation** — `bluey-not-found` mapped to `PlatformRespondToRequestNotFoundException`. Tracked in I322 notes.
- **Duplicate-response root cause** — the actual fix to whatever's causing the duplicate `handleReadRequest` invocation. Tracked in I322 itself; this PR is defense-in-depth only.
