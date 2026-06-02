# Lifecycle-silence ⇄ transport reconciliation — Stage 2–3 (eviction handshake + precise ordering) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the **iOS half** of I338 — when the GATT-server's heartbeat-silence timeout removes a client's session, a paused-then-resumed peer must be forced through a *clean reconnect* (rejected with a reserved ATT status that the client translates into a self-disconnect) instead of resuming mid-stream and corrupting frame reassembly.

**Architecture:** Build on Stage 1's capability-gated split (Android silence advisory, iOS silence removes the session). Stage 2 adds the **eviction handshake**: the server services read/write requests *only within an established session*; a request from a session-less client is answered with a reserved ATT application-range status (`0x80`, `lifecycleEvictionAttStatus`) and **not** dispatched. The client's error-translation layer maps that status → `BlueyConnection` self-disconnect → `DisconnectedException(evictedByServer)` → the app's existing reconnect logic runs. Stage 3 makes the "established session precedes its first serviced request" guarantee *precise* via a native **announce-before-forward** invariant (iOS already holds it per Phase 0; Android's write/read handlers are fixed to mirror it) plus **reset-announced-state on server (re)init**.

**Tech Stack:** Dart/Flutter (`bluey`, `bluey_platform_interface`), Pigeon, Kotlin (`bluey_android`), Swift (`bluey_ios`), `flutter_test`.

**Reference spec:** `docs/superpowers/specs/2026-05-30-lifecycle-silence-transport-reconciliation-design.md` (incl. the `## Phase 0 findings` section — read it; the native-behavior verification shapes Stage 3).

**Prerequisite (Stage 1, shipped in PR #35):** `Capabilities.reportsCentralDisconnects` (Android `true` / iOS `false`); `BlueyServer._handleLifecycleSilence` branching on it (advisory on Android; on iOS it calls `_handleClientDisconnected`, which already `_connectedClients.remove(clientAddress)` + clears identification). Stage 2 relies on that session-removal already being in place.

---

## Branch setup

- [ ] **Step 0: Branch off the updated `main`.**

```bash
cd /Users/joel/git/neutrinographics/bluey
git checkout main
git pull --ff-only   # ensure PR #35 (Stage 1) is present: `git log --oneline -1` should be 2a90fd1 or later
git checkout -b i338-stage2-eviction
```

Do **not** push or open a PR at any point unless explicitly asked (user pushes).

---

## Key constants & names (use these exact spellings everywhere)

| Symbol | Where it lives | Value / type |
|--------|----------------|--------------|
| `lifecycleEvictionAttStatus` | `bluey/lib/src/lifecycle.dart` (next to the other reserved lifecycle constants) | `const int lifecycleEvictionAttStatus = 0x80;` |
| `PlatformGattStatus.lifecycleEviction` | `bluey_platform_interface/lib/src/platform_interface.dart` | new enum case (last) |
| `GattStatusDto.lifecycleEviction` | `bluey_{android,ios}/pigeons/messages.dart` (+ regenerated `messages.g.*`) | new enum case (last) |
| `DisconnectReason.evictedByServer` | `bluey/lib/src/shared/exceptions.dart` | new enum case (last) |

**Invariant guard (do NOT break):** the *public* domain enum `GattResponseStatus` in `bluey/lib/src/gatt_server/gatt_request.dart` stays `0x01–0x0F` only. The reserved eviction status is **never** added there — that absence is the collision-safety guard (an app cannot emit an application-range code through bluey's public API). The server emits the reserved status by calling `_platform.respondTo{Read,Write}Request(..., PlatformGattStatus.lifecycleEviction, ...)` **directly**, bypassing `_mapGattResponseStatusToPlatform`.

---

## Testing conventions (apply to EVERY task — non-negotiable)

These mirror the existing suite (`bluey/test/gatt_server/lifecycle_silence_test.dart` is the reference). The test **skeletons below are illustrative** — match these conventions over the skeleton wherever they differ:

1. **Simulate time — never wait it out.** Any test touching a timer (lifecycle interval, silence timeout, heartbeat probe, `peerSilenceTimeout`) MUST use `fakeAsync((async) { ... })` and advance with `async.elapse(Duration(...))`. Flush pending microtasks with `async.flushMicrotasks()`. **Do not** use `await Future.delayed(Duration(...))` with a non-zero duration anywhere.

2. **Fake injection API.** Construct via `BlueyPlatform.instance = fake; final bluey = await Bluey.create();` (NOT `Bluey.create(platform: fake)` — that named param does not exist). `await Bluey.create()` runs *before* the `fakeAsync` block; everything after (server creation, advertising, simulated requests, timer firing, `server.dispose(); bluey.dispose();`) runs *inside* `fakeAsync` using `async.flushMicrotasks()`.

3. **Short interval constant.** Use a short `lifecycleInterval` (e.g. `const _silenceInterval = Duration(seconds: 5);`) passed to `bluey.server(lifecycleInterval: _silenceInterval)` so `async.elapse(_silenceInterval)` fires the silence timer deterministically.

4. **Firing silence.** `fake.simulateCentralConnection(centralId: mac)` establishes a session; `fake.fireLifecycleSilence(mac)` arms the silence timer; `async.elapse(_silenceInterval)` fires it. (Reference file lines 44–55.)

5. **Rejected futures.** A simulated request the server rejects completes its future with an error — attach `.catchError((_) {})` (reads: `.catchError((_) => Uint8List(0))`) then `async.flushMicrotasks()`; never leave it unhandled.

Canonical shape:
```dart
final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
BlueyPlatform.instance = fake;
final bluey = await Bluey.create();
fakeAsync((async) {
  final server = bluey.server(lifecycleInterval: _silenceInterval)!;
  server.startAdvertising(name: 't');
  async.flushMicrotasks();
  // ... simulate, elapse, assert ...
  server.dispose();
  bluey.dispose();
});
```

---

# Stage 2 — eviction handshake & session coherence (fixes iOS)

## Task 2.1: Reserve the eviction status on the platform-interface surface + the shared constant

**Files:**
- Modify: `bluey_platform_interface/lib/src/platform_interface.dart` (the `PlatformGattStatus` enum, ~line 790–800)
- Modify: `bluey/lib/src/lifecycle.dart` (add `lifecycleEvictionAttStatus` next to the marker constants, ~line 85)
- Test: `bluey_platform_interface/test/platform_gatt_status_test.dart` (create) and `bluey/test/lifecycle_test.dart` (append, or create if absent)

- [ ] **Step 1: Write the failing test** for the constant. Append to / create `bluey/test/lifecycle_test.dart`:

```dart
import 'package:bluey/src/lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lifecycleEvictionAttStatus', () {
    test('is the reserved ATT application-range status 0x80', () {
      expect(lifecycleEvictionAttStatus, 0x80);
    });
    test('is inside the ATT application range 0x80..0x9F', () {
      expect(lifecycleEvictionAttStatus, greaterThanOrEqualTo(0x80));
      expect(lifecycleEvictionAttStatus, lessThanOrEqualTo(0x9F));
    });
  });
}
```

- [ ] **Step 2: Run, confirm FAIL** (`lifecycleEvictionAttStatus` undefined):

```bash
cd bluey && flutter test test/lifecycle_test.dart
```
Expected: compile error / FAIL.

- [ ] **Step 3: Add the constant.** In `bluey/lib/src/lifecycle.dart`, immediately after the existing marker constants (`_markerHeartbeat = 0x01;` / `_markerCourtesyDisconnect = 0x00;`, ~line 85), add:

```dart
/// Reserved ATT application-range status the GATT **server** returns to a
/// client whose session it has evicted (heartbeat-silence timeout on an
/// inferring platform). Any request from a client with no established
/// session is answered with this status and is **not** dispatched —
/// forcing the client through a clean reconnect (see I338 design).
///
/// In the ATT application range `0x80–0x9F`. The public [GattResponseStatus]
/// enum deliberately excludes this range, so an app can never emit it
/// through bluey's API — that exclusion is the collision-safety guard.
/// If that enum is ever widened to allow application-range statuses, this
/// value must remain reserved.
const int lifecycleEvictionAttStatus = 0x80;
```

- [ ] **Step 4: Run, confirm PASS:**
```bash
cd bluey && flutter test test/lifecycle_test.dart
```

- [ ] **Step 5: Write the failing test** for the platform-interface enum. Create `bluey_platform_interface/test/platform_gatt_status_test.dart`:

```dart
import 'package:bluey_platform_interface/src/platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlatformGattStatus exposes a reserved lifecycleEviction case', () {
    expect(PlatformGattStatus.values, contains(PlatformGattStatus.lifecycleEviction));
  });

  test('lifecycleEviction is the last case (additive, stable ordinals)', () {
    expect(PlatformGattStatus.values.last, PlatformGattStatus.lifecycleEviction);
  });
}
```

- [ ] **Step 6: Run, confirm FAIL:**
```bash
cd bluey_platform_interface && flutter test test/platform_gatt_status_test.dart
```

- [ ] **Step 7: Add the case.** In `bluey_platform_interface/lib/src/platform_interface.dart`, append to the `PlatformGattStatus` enum (keep it **last** so existing ordinals are stable):

```dart
enum PlatformGattStatus {
  success,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  invalidAttributeLength,
  insufficientAuthentication,
  insufficientEncryption,
  requestNotSupported,

  /// Reserved eviction status (ATT application range, see
  /// `lifecycleEvictionAttStatus`). Emitted by the GATT server to reject a
  /// request from a client with no established session; the client
  /// translates it into a self-disconnect (I338). Not part of the public
  /// `GattResponseStatus` surface — an app cannot select it.
  lifecycleEviction,
}
```

- [ ] **Step 8: Run, confirm PASS + analyze:**
```bash
cd bluey_platform_interface && flutter test test/platform_gatt_status_test.dart && flutter analyze
cd ../bluey && flutter analyze
```

- [ ] **Step 9: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_platform_interface/lib/src/platform_interface.dart \
        bluey_platform_interface/test/platform_gatt_status_test.dart \
        bluey/lib/src/lifecycle.dart bluey/test/lifecycle_test.dart
git commit -m "feat(platform-interface): reserve lifecycleEviction ATT status (I338 Stage 2)"
```

---

## Task 2.2: Carry the reserved status through Pigeon + native conversions

The reserved status must reach native and be emitted as the raw ATT byte `0x80`. Add the Pigeon enum case (both packages), regenerate, then update the **hand-written** native conversions and the per-package `_mapGattStatusToDto`.

**Files:**
- Modify: `bluey_android/pigeons/messages.dart` (`GattStatusDto`, ~line 305–315)
- Modify: `bluey_ios/pigeons/messages.dart` (`GattStatusDto`, ~line 286–296)
- Regenerate: `bluey_android/lib/src/messages.g.dart`, `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt`, `bluey_ios/lib/src/messages.g.dart`, `bluey_ios/ios/Classes/Messages.g.swift`
- Modify (hand-written conversions): `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt` (`toAndroidStatus`, ~line 67–76), `bluey_ios/ios/Classes/Messages.x.swift` (`toCBATTError`, ~line 117–138)
- Modify (PlatformGattStatus→Dto mappers): `bluey_android/lib/src/android_server.dart` (`_mapGattStatusToDto`, ~line 364), `bluey_ios/lib/src/ios_server.dart` (`_mapGattStatusToDto`, ~line 394)
- Test: `bluey_android/test/android_server_test.dart`, `bluey_ios/test/ios_server_test.dart` (append; if no such file, create per the package's existing test conventions)

- [ ] **Step 1: Write the failing Dart mapper tests.** Append to `bluey_android/test/android_server_test.dart` (mirror the file's existing setup for constructing the `AndroidServer`/mapper; if `_mapGattStatusToDto` is private, test via the public `respondToWriteRequest` path and assert the Pigeon call carried `GattStatusDto.lifecycleEviction`). Minimal direct form if the mapper is reachable in tests:

```dart
test('maps PlatformGattStatus.lifecycleEviction to GattStatusDto.lifecycleEviction', () {
  // Use whatever harness the file already uses to reach the mapper / respond path.
  // Assert the Dto carried to the Pigeon HostApi for a lifecycleEviction response
  // is GattStatusDto.lifecycleEviction.
});
```

Do the same in `bluey_ios/test/ios_server_test.dart`.

> If these packages don't unit-test the private mapper, instead add the assertion at the existing `respondToWriteRequest`/`respondToReadRequest` test (drive a response with `PlatformGattStatus.lifecycleEviction` and assert the fake/mock HostApi received `GattStatusDto.lifecycleEviction`). Match the file's established mocking pattern (`flutter analyze` will reveal the available test doubles).

- [ ] **Step 2: Run, confirm FAIL** (mapper has no `lifecycleEviction` case → non-exhaustive switch compile error or missing Dto value):
```bash
cd bluey_android && flutter test test/android_server_test.dart
cd ../bluey_ios && flutter test test/ios_server_test.dart
```

- [ ] **Step 3: Add the Pigeon enum case (both packages, last position).** In `bluey_android/pigeons/messages.dart` and `bluey_ios/pigeons/messages.dart`, append to `GattStatusDto`:

```dart
enum GattStatusDto {
  success,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  invalidAttributeLength,
  insufficientAuthentication,
  insufficientEncryption,
  requestNotSupported,

  /// Reserved eviction status (ATT application range 0x80; see
  /// `lifecycleEvictionAttStatus`). Server-internal — rejects a
  /// session-less client's request (I338).
  lifecycleEviction,
}
```

- [ ] **Step 4: Regenerate Pigeon (both packages):**
```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_android && dart run pigeon --input pigeons/messages.dart
cd /Users/joel/git/neutrinographics/bluey/bluey_ios && dart run pigeon --input pigeons/messages.dart
```
Verify with `git diff --stat` that only the generated `messages.g.dart` / `Messages.g.kt` / `Messages.g.swift` changed (each gains a `lifecycleEviction` / `LIFECYCLE_EVICTION` enum member at ordinal 8). Do **not** hand-edit generated files beyond what Pigeon produces.

- [ ] **Step 5: Update the per-package Dart mapper.** In `bluey_android/lib/src/android_server.dart` `_mapGattStatusToDto` (~line 364) add a case (the switch will not compile without it):

```dart
      case PlatformGattStatus.lifecycleEviction:
        return GattStatusDto.lifecycleEviction;
```
Add the identical case to `bluey_ios/lib/src/ios_server.dart` `_mapGattStatusToDto` (~line 394).

- [ ] **Step 6: Update the native conversions to the raw ATT byte.**

In `bluey_android/.../PendingRequestRegistry.kt` `toAndroidStatus()` (~line 67–76), add:
```kotlin
    GattStatusDto.LIFECYCLE_EVICTION -> 0x80  // lifecycleEvictionAttStatus — ATT application range
```

In `bluey_ios/ios/Classes/Messages.x.swift` `toCBATTError()` (~line 117–138), add:
```swift
        case .lifecycleEviction:
            // lifecycleEvictionAttStatus (0x80). CBATTError.Code is open;
            // an application-range raw value is delivered verbatim to the central.
            return CBATTError.Code(rawValue: 0x80) ?? .unlikelyError
```

- [ ] **Step 7: Run, confirm PASS + analyze (all three Dart packages):**
```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter test test/android_server_test.dart && flutter analyze
cd /Users/joel/git/neutrinographics/bluey/bluey_ios && flutter test test/ios_server_test.dart && flutter analyze
```

- [ ] **Step 8: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/pigeons/messages.dart bluey_ios/pigeons/messages.dart \
        bluey_android/lib/src/messages.g.dart bluey_ios/lib/src/messages.g.dart \
        bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt \
        bluey_ios/ios/Classes/Messages.g.swift \
        bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/PendingRequestRegistry.kt \
        bluey_ios/ios/Classes/Messages.x.swift \
        bluey_android/lib/src/android_server.dart bluey_ios/lib/src/ios_server.dart \
        bluey_android/test/android_server_test.dart bluey_ios/test/ios_server_test.dart
git commit -m "feat(platform): carry lifecycleEviction status through Pigeon to native ATT 0x80 (I338 Stage 2)"
```

---

## Task 2.3: Client-side translation — `DisconnectReason.evictedByServer` + reserved-status mapping

**Files:**
- Modify: `bluey/lib/src/shared/exceptions.dart` (`DisconnectReason` enum, ~line 73–80)
- Modify: `bluey/lib/src/shared/error_translation.dart` (`translatePlatformException`, the `GattOperationStatusFailedException` branch, ~line 43–44)
- Test: `bluey/test/shared/error_translation_test.dart` (append; create if absent)

- [ ] **Step 1: Write the failing test.** Append to `bluey/test/shared/error_translation_test.dart`:

```dart
import 'package:bluey/src/lifecycle.dart' show lifecycleEvictionAttStatus;
import 'package:bluey/src/shared/error_translation.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart' as platform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('eviction-status translation', () {
    test('reserved eviction status becomes DisconnectedException(evictedByServer)', () {
      final translated = translatePlatformException(
        platform.GattOperationStatusFailedException('write', lifecycleEvictionAttStatus),
        operation: 'write',
        address: 'AA:BB:CC:DD:EE:FF',
      );
      expect(translated, isA<DisconnectedException>());
      final dx = translated as DisconnectedException;
      expect(dx.reason, DisconnectReason.evictedByServer);
      expect(dx.address, 'AA:BB:CC:DD:EE:FF');
    });

    test('a non-reserved status still maps to GattOperationFailedException', () {
      final translated = translatePlatformException(
        platform.GattOperationStatusFailedException('write', 0x01),
        operation: 'write',
      );
      expect(translated, isA<GattOperationFailedException>());
    });
  });
}
```

- [ ] **Step 2: Run, confirm FAIL** (`evictedByServer` undefined / wrong type returned):
```bash
cd bluey && flutter test test/shared/error_translation_test.dart
```

- [ ] **Step 3: Add the enum value.** In `bluey/lib/src/shared/exceptions.dart`, append to `DisconnectReason` (keep last):

```dart
enum DisconnectReason {
  requested, // disconnect() was called
  remoteDisconnect, // Remote device disconnected
  linkLoss, // Connection lost (out of range, etc.)
  timeout, // Operation timeout
  unknown,
  evictedByServer, // Server rejected us (no established session) — I338; reconnect
}
```

- [ ] **Step 4: Implement the translation branch.** In `bluey/lib/src/shared/error_translation.dart`, add an import and reorder the `GattOperationStatusFailedException` handling so the reserved status is caught first:

```dart
import '../lifecycle.dart' show lifecycleEvictionAttStatus;
```
Replace the existing branch (~line 43–44):
```dart
  if (error is platform.GattOperationStatusFailedException) {
    if (error.status == lifecycleEvictionAttStatus) {
      // Server evicted us: our session is gone (heartbeat-silence timeout on
      // an inferring server). Surface as a connection-fatal disconnect so the
      // app reconnects via existing logic (I338). The connection layer drives
      // the actual teardown (LifecycleClient eviction fast-path / disconnect).
      return DisconnectedException(address ?? '', DisconnectReason.evictedByServer);
    }
    return GattOperationFailedException(operation, error.status);
  }
```

- [ ] **Step 5: Run, confirm PASS + analyze:**
```bash
cd bluey && flutter test test/shared/error_translation_test.dart && flutter analyze
```

- [ ] **Step 6: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/shared/exceptions.dart bluey/lib/src/shared/error_translation.dart \
        bluey/test/shared/error_translation_test.dart
git commit -m "feat(connection): translate reserved eviction status to DisconnectedException(evictedByServer) (I338 Stage 2)"
```

---

## Task 2.4: `LifecycleClient` eviction fast-path — self-disconnect on a reserved-status heartbeat failure

The heartbeat write is the most frequent client→server request, so after eviction it is the reliable, low-latency trigger for the self-disconnect (this also matches the spec's fallback: restrict the eviction signal to the heartbeat-write path if an OS masks app-range statuses on app writes). `_sendProbe`'s `catchError` receives the **raw** `platform.GattOperationStatusFailedException` (it does not go through `withErrorTranslation`), so detect the reserved status here and fire the existing `onServerUnreachable` immediately, bypassing the silence timer.

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart` (`_sendProbe` catchError ~line 561; add `_isEvictionSignal` near `_isDeadPeerSignal` ~line 643)
- Test: `bluey/test/connection/lifecycle_client_test.dart` (append; match the file's existing fake/harness for driving a failing heartbeat write)

- [ ] **Step 1: Write the failing test.** Append a case that drives a heartbeat write to fail with `GattOperationStatusFailedException('Write', lifecycleEvictionAttStatus)` and asserts `onServerUnreachable` fires **immediately** — on the *first* probe, with **no** elapsed virtual time (proving it is not gated on `peerSilenceTimeout`).

**Use `fakeAsync` — do NOT use real `Future.delayed` durations.** This is a hard project rule: timer-driven behaviour is tested by simulating time (`fakeAsync((async){ ... async.flushMicrotasks(); async.elapse(...); })`), never by waiting out a wall-clock delay. Reuse the file's existing `_setUpConnectedClient(...)` helper and its fake write-failure injection. The load-bearing assertion is that `onServerUnreachable` fires after the *first* failed probe **without** any `async.elapse` of the silence window. Skeleton (mirror the existing `'keeps re-sending probes after a transient write failure'` test's structure for setup):

```dart
test('reserved eviction status triggers onServerUnreachable immediately', () {
  fakeAsync((async) {
    var unreachable = 0;
    late LifecycleClient client;
    late List<RemoteService> services;
    late FakeBlueyPlatform fakePlatform;

    _setUpConnectedClient(
      onServerUnreachable: () => unreachable++,
      // long silence window — if the impl waited on it, the assertion below
      // (no elapse) would fail, proving eviction is immediate.
      peerSilenceTimeout: const Duration(seconds: 30),
    ).then((setup) {
      client = setup.client;
      services = setup.services;
      fakePlatform = setup.fakePlatform;
    });
    async.flushMicrotasks();

    // Next heartbeat write throws the reserved eviction status (typed).
    // (Task 2.6 adds this injector if the fake lacks a typed-error hook;
    // do NOT reuse the generic `simulateWriteFailure` — it throws a plain
    // Exception, which is a transient signal, not the eviction status.)
    fakePlatform.writeCharacteristicError =
        platform.GattOperationStatusFailedException('Write', lifecycleEvictionAttStatus);

    client.start(allServices: services); // first probe fires synchronously
    async.flushMicrotasks();             // let the failed write's catchError run

    expect(unreachable, 1,
        reason: 'eviction is immediate on the first probe, not silence-timer gated');
    expect(client.isRunning, isFalse, reason: 'stop() called before signalling');
    // No async.elapse(...) anywhere — that is the point of the test.
  });
});
```
> Match `_setUpConnectedClient`'s actual parameter names (it may be `intervalValue:` for the server interval; add/forward a `peerSilenceTimeout:` if needed, or assert via "no elapse" alone). The non-negotiable property: `onServerUnreachable` fires from a *single* failed probe with **zero** simulated silence-window elapse.

- [ ] **Step 2: Run, confirm FAIL** (today a reserved status is just a `_isDeadPeerSignal`, so it waits for the silence timer):
```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart
```

- [ ] **Step 3: Implement.** In `lifecycle_client.dart`:

Add the predicate next to `_isDeadPeerSignal` (~line 648):
```dart
  /// Whether [error] is the server's reserved *eviction* status (our session
  /// was removed). Distinct from a generic dead-peer signal: eviction is
  /// definitive and immediate — we self-disconnect now rather than waiting
  /// out the silence timer, so the app reconnects into a fresh session
  /// (I338). Only the eviction byte qualifies; every other status failure
  /// stays a dead-peer signal fed to the silence monitor.
  bool _isEvictionSignal(Object error) =>
      error is platform.GattOperationStatusFailedException &&
      error.status == lifecycleEvictionAttStatus;
```
Add the import at the top of the file (if not already importing it):
```dart
import '../lifecycle.dart' show lifecycleEvictionAttStatus;
```
In `_sendProbe`'s `catchError` (the first lines of the callback, ~line 561, before the `_isDeadPeerSignal` check), add:
```dart
        .catchError((Object error) {
          if (!_isRunning) return;
          if (_isEvictionSignal(error)) {
            _logger.log(
              BlueyLogLevel.warn,
              'bluey.connection.lifecycle',
              'evicted by server (reserved status) — self-disconnecting',
              data: {'connectionId': _connectionId},
            );
            if (_deviceAddress != null) {
              _events?.emit(
                HeartbeatFailedEvent(
                  deviceAddress: _deviceAddress,
                  isDeadPeerSignal: true,
                  reason: 'evictedByServer',
                  source: 'LifecycleClient',
                ),
              );
            }
            _monitor.cancelProbe();
            stop();
            onServerUnreachable();
            return;
          }
          if (!_isDeadPeerSignal(error)) {
            // ... existing transient-failure handling unchanged ...
```
(Leave the rest of the `catchError` body unchanged.)

- [ ] **Step 4: Run, confirm PASS + full lifecycle suite + analyze:**
```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart && flutter analyze
```

- [ ] **Step 5: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart
git commit -m "feat(connection): LifecycleClient self-disconnects immediately on reserved eviction status (I338 Stage 2)"
```

> **Note (no signature change to `disconnect()`):** the `evictedByServer` *reason* is surfaced through `translatePlatformException` (Task 2.3) to any in-flight app op that races the eviction. The heartbeat-driven teardown is a plain `disconnect()` (via the existing `onServerUnreachable` wiring at `bluey.dart:764` and `bluey_peer.dart:120`) — "the app sees a normal disconnect," per the spec. No new callback is needed.

---

## Task 2.5: Server chokepoint — reject session-less requests; stop establishing from an unknown heartbeat

This is the core of the eviction model. In `BlueyServer`, gate the read- and write-request listeners on an **established session** *before* any dispatch (control-service handling, app forward, or peer-identification). A request from a client not in `_connectedClients` is answered with `PlatformGattStatus.lifecycleEviction` and dropped.

**Why uniform (not capability-gated):** on Android, silence is advisory (Stage 1) so a live central's session is never removed — the gate never trips for it once Stage 3's announce-before-forward lands (a real connect always establishes the session before the first request). On iOS, the gate *is* the eviction mechanism (silence removed the session). One rule covers both. The capability still governs only *whether silence removes the session* — already wired in Stage 1.

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart` (read listener ~line 183–190, write listener ~line 192–205, `_trackPeerClient` ~line 856–894; add a `_hasEstablishedSession` helper near `_connectedClients`)
- Test: `bluey/test/gatt_server/eviction_session_coherence_test.dart` (create)

- [ ] **Step 1: Confirm the fake helpers exist** (from Stage 1 / the Phase 0 inventory): `FakeBlueyPlatform(reportsCentralDisconnects: false)`, `simulateCentralConnection(centralId:)`, `fireLifecycleSilence(centralId)`, `simulateReadRequest(...)`, `simulateWriteRequest(...)`, and the recorded `respondWriteCalls` / `respondReadCalls` lists (each element exposes `.status`). If `simulateReadRequest`/`simulateWriteRequest` or the recorded-call lists are missing, add them in this step (see Task 2.6) before writing the test.

- [ ] **Step 2: Write the failing test.** Create `bluey/test/gatt_server/eviction_session_coherence_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    show PlatformGattStatus;
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_platform.dart';

void main() {
  const mac = 'AA:BB:CC:DD:EE:FF';
  const someCharUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  test('inferring server: a write from a session-less client is rejected with '
      'the reserved status and NOT forwarded', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');

    final forwarded = <WriteRequest>[];
    server.writeRequests.listen(forwarded.add);

    // No simulateCentralConnection → no established session.
    await fake.simulateWriteRequest(
      centralId: mac,
      characteristicUuid: someCharUuid,
      value: Uint8List.fromList([1, 2, 3]),
    ).catchError((_) {}); // rejected write completes with error

    await Future<void>.delayed(Duration.zero);

    expect(forwarded, isEmpty, reason: 'no session → not dispatched to app');
    expect(fake.respondWriteCalls.last.status,
        PlatformGattStatus.lifecycleEviction);
    await bluey.dispose();
  });

  test('inferring server: a read from a session-less client is rejected with '
      'the reserved status', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');

    final reads = <ReadRequest>[];
    server.readRequests.listen(reads.add);

    await fake.simulateReadRequest(
      centralId: mac,
      characteristicUuid: someCharUuid,
    ).catchError((_) => Uint8List(0));

    await Future<void>.delayed(Duration.zero);

    expect(reads, isEmpty);
    expect(fake.respondReadCalls.last.status,
        PlatformGattStatus.lifecycleEviction);
    await bluey.dispose();
  });

  test('a session-less heartbeat does NOT re-create the client or re-emit '
      'peerConnections (no establish-from-unknown-heartbeat)', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');

    final peers = <PeerClient>[];
    server.peerConnections.listen(peers.add);

    // Drive a heartbeat write from a client with no session (fireLifecycleSilence
    // injects a heartbeat write; here it stands in for an unknown-client heartbeat).
    fake.fireLifecycleSilence(mac);
    await Future<void>.delayed(Duration.zero);

    expect(peers, isEmpty, reason: 'no session → heartbeat rejected, not identified');
    expect(server.isClientConnected(const ClientAddress(mac)), isFalse);
    await bluey.dispose();
  });

  test('an established client (real connect) is serviced normally', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');

    final forwarded = <WriteRequest>[];
    server.writeRequests.listen(forwarded.add);

    fake.simulateCentralConnection(centralId: mac); // establishes session
    await Future<void>.delayed(Duration.zero);

    await fake.simulateWriteRequest(
      centralId: mac,
      characteristicUuid: someCharUuid,
      value: Uint8List.fromList([9]),
      responseNeeded: false,
    );
    await Future<void>.delayed(Duration.zero);

    expect(forwarded, hasLength(1), reason: 'established session → dispatched');
    await bluey.dispose();
  });
}
```

- [ ] **Step 3: Run, confirm FAIL** (today session-less requests are forwarded / re-create the client):
```bash
cd bluey && flutter test test/gatt_server/eviction_session_coherence_test.dart
```

- [ ] **Step 4: Implement the gate.** In `bluey/lib/src/gatt_server/bluey_server.dart`:

Add a helper near `_connectedClients` (~line 51):
```dart
  /// A client has an *established session* iff it is present in
  /// [_connectedClients] via a real connect/announce (`centralConnections`).
  /// The server services read/write requests only within an established
  /// session — a request from a session-less client is evicted (I338).
  bool _hasEstablishedSession(ClientAddress clientAddress) =>
      _connectedClients.containsKey(clientAddress);
```

Rewrite the **write** listener (~line 192–205) to gate first:
```dart
    _platformWriteRequestsSub = _platform.writeRequests.listen((req) {
      final clientAddress = ClientAddress(req.centralId);
      if (!_hasEstablishedSession(clientAddress)) {
        // No established session → evict. Do not dispatch, do not let the
        // lifecycle layer re-establish from this write (I338).
        _logger.log(
          BlueyLogLevel.info,
          'bluey.server',
          'rejecting write from session-less client (eviction)',
          data: {'clientId': clientAddress.toString()},
        );
        if (req.responseNeeded) {
          _platform.respondToWriteRequest(
            req.requestId,
            platform.PlatformGattStatus.lifecycleEviction,
          );
        }
        return;
      }
      if (!_lifecycle.handleWriteRequest(req)) {
        if (req.responseNeeded) {
          _lifecycle.requestStarted(clientAddress, req.requestId);
        } else {
          _lifecycle.recordActivity(clientAddress);
        }
        _filteredWriteRequestsController.add(req);
      }
    });
```

Rewrite the **read** listener (~line 183–190) the same way (reads always need a response, so always respond on the no-session path):
```dart
    _platformReadRequestsSub = _platform.readRequests.listen((req) {
      final clientAddress = ClientAddress(req.centralId);
      if (!_hasEstablishedSession(clientAddress)) {
        _logger.log(
          BlueyLogLevel.info,
          'bluey.server',
          'rejecting read from session-less client (eviction)',
          data: {'clientId': clientAddress.toString()},
        );
        _platform.respondToReadRequest(
          req.requestId,
          platform.PlatformGattStatus.lifecycleEviction,
          null,
        );
        return;
      }
      if (!_lifecycle.handleReadRequest(req)) {
        _lifecycle.requestStarted(clientAddress, req.requestId);
        _filteredReadRequestsController.add(req);
      }
    });
```

> Confirm `platform` is the import prefix already used in this file for `bluey_platform_interface` (Phase 0 map shows `final platform.BlueyPlatform _platform;`). Use the same prefix for `platform.PlatformGattStatus`.

- [ ] **Step 5: Remove establish-from-unknown-heartbeat in `_trackPeerClient`.** With the gate in front, `_trackPeerClient` is only ever reached for a client that already has a session, so its `wasNew` create branch is dead for session-less clients. Make that explicit and safe — `_trackPeerClient` must only *identify* an existing session, never create one (~line 856–894):

```dart
  void _trackPeerClient(ClientAddress clientAddress, ServerId senderId) {
    // Identification only — never establishes a session. A heartbeat from a
    // client with no established session is rejected at the chokepoint before
    // it can reach here (I338); if one still arrives (defensive), ignore it
    // rather than silently re-creating the client and re-emitting peerConnections.
    final client = _connectedClients[clientAddress];
    if (client == null) return;

    if (_identifiedPeerClientAddresses.add(clientAddress)) {
      _logger.log(
        BlueyLogLevel.info,
        'bluey.server',
        'central identified as Bluey peer',
        data: {
          'clientId': clientAddress.toString(),
          'senderId': senderId.toString(),
        },
      );
      _peerConnectionsController.add(
        PeerClient.create(client: client, serverId: senderId),
      );
    }
  }
```

> This removes the `BlueyClient(... mtu: 23)` synthesis and the `ClientConnectedEvent` + `_connectionsController.add` from the heartbeat path. Sessions are now created **only** by the `centralConnections` listener (~line 145–172). Verify no test depended on heartbeat-only establishment that should instead drive `simulateCentralConnection` — Task 2.7 / the existing-test sweep covers this.

- [ ] **Step 6: Run, confirm PASS + analyze:**
```bash
cd bluey && flutter test test/gatt_server/eviction_session_coherence_test.dart && flutter analyze
```

- [ ] **Step 7: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/gatt_server/bluey_server.dart bluey/test/gatt_server/eviction_session_coherence_test.dart
git commit -m "feat(gatt-server): evict session-less requests with reserved status; no establish-from-unknown-heartbeat (I338 Stage 2)"
```

---

## Task 2.6: Fake-platform support for eviction assertions (only what Task 2.5 needed and is missing)

Most hooks exist from Stage 1 / the Phase 0 inventory (`simulateCentralConnection`, `fireLifecycleSilence`, `simulateReadRequest`, `simulateWriteRequest`, `respondReadCalls`/`respondWriteCalls` recording, `reportsCentralDisconnects` constructor param). This task fills any gap and adds a client-side write-failure injector for Task 2.4's harness if absent.

**Files:**
- Modify: `bluey/test/fakes/fake_platform.dart`

- [ ] **Step 1:** Verify `respondToReadRequest` / `respondToWriteRequest` record the `PlatformGattStatus` into `respondReadCalls` / `respondWriteCalls` (Phase 0 confirmed they do). If a recorded element doesn't expose `.status`, add it. No change if already present.

- [ ] **Step 2:** Ensure a client-side heartbeat/write failure can be injected for the Task 2.4 `lifecycle_client_test` harness — i.e. a way to make `writeCharacteristic(connectionId, handle, value, withResponse)` throw `platform.GattOperationStatusFailedException('Write', lifecycleEvictionAttStatus)`. If the fake already has a per-op failure injector (Phase 0 noted `respondToReadFailure` one-shot and `simulateWriteDisconnected`), add an analogous one-shot:

```dart
  /// One-shot: the next `writeCharacteristic` throws this error, then clears.
  Object? writeCharacteristicFailure;
```
and in the fake's `writeCharacteristic`:
```dart
    final injected = writeCharacteristicFailure;
    if (injected != null) {
      writeCharacteristicFailure = null;
      throw injected;
    }
```
(Skip if an equivalent hook already exists — reuse it in the Task 2.4 test instead.)

- [ ] **Step 3: Run the fake-dependent suites, confirm green + analyze:**
```bash
cd bluey && flutter test test/gatt_server/ test/connection/ && flutter analyze
```

- [ ] **Step 4: Commit (only if the fake changed):**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/test/fakes/fake_platform.dart
git commit -m "test(fakes): record response status + inject client write failure for eviction tests (I338 Stage 2)"
```

---

## Task 2.7: Headline regression (I338 contract) + existing-test sweep

**Files:**
- Test: `bluey/test/gatt_server/eviction_session_coherence_test.dart` (append the headline case)
- Modify: any existing test broken by the `_trackPeerClient` change (heartbeat-only establishment) — likely in `bluey/test/bluey_server_test.dart`, `bluey/test/connection/lifecycle_events_test.dart`

- [ ] **Step 1: Write the headline regression test** (the load-bearing I338 contract — a silence-then-resume on the inferring path cannot continue mid-stream). Append:

```dart
  test('I338 contract: inferring server — silence-then-resume is rejected, '
      'forcing reconnect (cannot continue mid-stream)', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');
    const mac = 'AA:BB:CC:DD:EE:FF';
    const charUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

    final forwarded = <WriteRequest>[];
    server.writeRequests.listen(forwarded.add);

    // 1. Real connect → established session.
    fake.simulateCentralConnection(centralId: mac);
    await Future<void>.delayed(Duration.zero);

    // 2. Heartbeat silence removes the session (Stage 1 inferring path).
    fake.fireLifecycleSilence(mac);
    await Future<void>.delayed(Duration.zero);
    expect(server.isClientConnected(const ClientAddress(mac)), isFalse);

    // 3. Peer "resumes" mid-stream with an app write → MUST be rejected, not forwarded.
    await fake.simulateWriteRequest(
      centralId: mac,
      characteristicUuid: charUuid,
      value: Uint8List.fromList([0xAA, 0xBB]),
    ).catchError((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(forwarded, isEmpty,
        reason: 'resumed write from a removed session must not reach the app');
    expect(fake.respondWriteCalls.last.status,
        PlatformGattStatus.lifecycleEviction);
    await bluey.dispose();
  });
```

> Note: whether `fireLifecycleSilence` fires the timeout synchronously or needs `fakeAsync`/`async.elapse(lifecycleInterval)` depends on the Stage 1 helper. If it arms a timer, wrap the silence step with the same `fakeAsync` pattern the Stage 1 `lifecycle_silence_test.dart` uses, then advance the clock.

- [ ] **Step 2: Run the full `bluey` suite to find sweep breakers:**
```bash
cd bluey && flutter test 2>&1 | tail -40
```
Expect possible failures in tests that previously relied on a heartbeat *alone* establishing a client (now removed). For each: if the test's intent is a real client, drive `simulateCentralConnection(centralId: mac)` first; if its intent is specifically the (now-removed) unknown-heartbeat establishment, update it to assert the new eviction behavior. Do **not** weaken assertions.

- [ ] **Step 3: Run all packages green + analyze:**
```bash
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test && flutter analyze
cd ../bluey_platform_interface && flutter test && flutter analyze
cd ../bluey_android && flutter test && flutter analyze
cd ../bluey_ios && flutter test && flutter analyze
```

- [ ] **Step 4: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/test
git commit -m "test(gatt-server): I338 headline regression + sweep tests for session-coherence (I338 Stage 2)"
```

---

# Stage 3 — precise establishment ordering (native)

Make "a legitimate fresh client already has a session by the time its first request is serviced" *deterministic*, so the Stage 2 gate never evicts a live central. Phase 0: **iOS already holds** announce-before-forward; **Android does not** (its write/read handlers `handler.post` the forward without announcing the central first, racing the connect post). Stage 3 fixes Android to mirror iOS, and resets the native announced-state on server (re)init so a recreated `BlueyServer` re-announces surviving centrals.

> These are native (Kotlin/Swift) changes whose end-to-end effect is verified by the Stage 2 Dart tests (gate correctness) plus the Task 4.2 device dogfood. Keep each change minimal and mirror the iOS pattern Phase 0 documented.

## Task 3.1: Android announce-before-forward in the write/read handlers

**Files:**
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` (`onCharacteristicWriteRequest` ~line 836/881, `onCharacteristicReadRequest` ~line 790/829, `connectedCentrals` map ~line 43, the `onConnectionStateChange` announce ~line 692–704)

- [ ] **Step 1: Read the current handlers** to confirm the exact symbols (`connectedCentrals`, the `CentralDto` shape passed to `flutterApi.onCentralConnected`, the `handler.post { ... }` wrapping, and how `centralId`/`device.address` is derived in the write/read callbacks).

- [ ] **Step 2: Add an idempotent announce helper** on `GattServer` that announces a central exactly once (mirrors iOS `trackCentralIfNeeded`). It must be safe to call from a binder thread and must post the `onCentralConnected` to the main handler **before** the caller posts its forward:

```kotlin
/** Announce [device] as connected exactly once, before any request from it is
 *  forwarded to Dart. Mirrors iOS `trackCentralIfNeeded`. Idempotent: a central
 *  already in [connectedCentrals] is not re-announced. Establishes the
 *  announce-before-forward invariant the Dart session-gate relies on (I338). */
private fun announceCentralIfNeeded(device: BluetoothDevice) {
    val id = device.address
    if (connectedCentrals.containsKey(id)) return
    connectedCentrals[id] = device
    val dto = /* build the same CentralDto used in onConnectionStateChange */
    handler.post { flutterApi.onCentralConnected(dto) { } }
}
```
> Match the exact `CentralDto`/`CentralMessage` constructor and `onCentralConnected` signature used at the existing connect site (~line 701). If a default MTU is needed, use the same value the connect path uses (or the known MTU if available).

- [ ] **Step 3: Call it before each forward.** In `onCharacteristicWriteRequest`, immediately before the `handler.post { flutterApi.onWriteRequest(...) }` (~line 881), add `announceCentralIfNeeded(device)`. Do the same in `onCharacteristicReadRequest` before `flutterApi.onReadRequest` (~line 829). Because both posts now originate from the same callback, in order (announce then forward), they arrive at the main looper — and thus at Dart — in that order.

- [ ] **Step 4: Keep `onConnectionStateChange` as the primary announce** (unchanged) — `announceCentralIfNeeded` is the backstop for the race where a write/read beats the connect post. The `containsKey` guard makes the two paths idempotent.

- [ ] **Step 5: Build the Android package** to confirm it compiles (no Kotlin unit harness assumed for this path; correctness is covered by the Dart gate tests + dogfood):
```bash
cd /Users/joel/git/neutrinographics/bluey/bluey_android && flutter analyze
# If the example app builds Android, optionally: cd ../bluey/example && flutter build apk --debug
```

- [ ] **Step 6: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt
git commit -m "fix(android): announce central before forwarding read/write requests (I338 Stage 3 ordering)"
```

## Task 3.2: Reset announced-state on server (re)init (both platforms)

Phase 0: the native peripheral/GATT manager is **reused** across `BlueyServer` recreations, and the I333 adapter-cycle invalidation path does **not** call `closeServer`. So a surviving central's "already announced" flag can outlive the Dart server that knew it, and the new server never re-announces it (→ no session → its next request is evicted, forcing an avoidable reconnect). Reset the native announced-state whenever a new `BlueyServer` initializes, so each surviving central is re-announced on its next interaction.

**Files:**
- Add a platform-interface method: `bluey_platform_interface/lib/src/platform_interface.dart` (`resetServerSessions()` — or fold into existing `addService`/start; prefer an explicit method for testability)
- Implement in: `bluey_android/lib/src/android_server.dart` + `GattServer.kt`; `bluey_ios/lib/src/ios_server.dart` + `PeripheralManagerImpl.swift`; `bluey/test/fakes/fake_platform.dart`
- Call from: `bluey/lib/src/gatt_server/bluey_server.dart` constructor (or first `startAdvertising`/`addService`)
- Test: `bluey/test/gatt_server/eviction_session_coherence_test.dart` (append a reset-on-init case driven through the fake)

- [ ] **Step 1: Write the failing test** (Dart-observable via the fake): a surviving central in the native "announced" set is re-announced (re-establishing the Dart session) after a new `BlueyServer` is created. Drive it through a fake hook `fake.simulateSurvivingAnnouncedCentral(mac)` (a central the native layer still has but the new Dart server hasn't heard of), then assert that after `bluey.server()` + reset, the central's first request is serviced (session re-established) rather than evicted. Skeleton:

```dart
test('reset-on-init: a surviving native-announced central is re-announced, '
    'not permanently evicted', () async {
  final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
  final bluey = await Bluey.create(platform: fake);
  // Simulate a central the native side still "knows" but the new Dart server doesn't.
  fake.simulateSurvivingAnnouncedCentral('AA:BB:CC:DD:EE:FF');
  final server = bluey.server()!;                  // triggers resetServerSessions()
  await server.startAdvertising(name: 't');
  // On reset, the fake re-announces survivors via centralConnections.
  await Future<void>.delayed(Duration.zero);
  expect(server.isClientConnected(const ClientAddress('AA:BB:CC:DD:EE:FF')), isTrue);
  await bluey.dispose();
});
```
> Model the fake so `resetServerSessions()` re-emits `centralConnections` for any "surviving announced" central — that is exactly the native contract (clear announced-flags → re-announce on next interaction), made synchronous and observable in tests.

- [ ] **Step 2: Run, confirm FAIL.**
```bash
cd bluey && flutter test test/gatt_server/eviction_session_coherence_test.dart
```

- [ ] **Step 3: Add the platform-interface method** (default no-op so other platforms/tests are unaffected):
```dart
  /// Resets the native server's per-central "announced" state so a recreated
  /// [BlueyServer] re-announces every surviving central on its next
  /// interaction. Establishes a clean session baseline after server
  /// (re)init — required because the native manager is reused across
  /// recreations and the I333 invalidation path does not close it (I338).
  Future<void> resetServerSessions() async {}
```

- [ ] **Step 4: Call it from `BlueyServer`.** In the `BlueyServer` constructor (after wiring the `centralConnections`/`centralDisconnections` listeners so the re-announcements are observed), call `unawaited(_platform.resetServerSessions());` — or `await` it in the first `startAdvertising`/`addService` if the constructor must stay synchronous. Pick whichever the file's existing init style supports; ensure the listeners are attached before the reset fires so re-announcements aren't missed.

- [ ] **Step 5: Implement native.**
  - **iOS** (`PeripheralManagerImpl.swift`): a `resetServerSessions()` that, for each central currently in `centrals`, clears the announced-flag and re-invokes `flutterApi.onCentralConnected` (or simply `centrals.removeAll()` so the next `didReceiveRead/Write`'s `trackCentralIfNeeded` re-announces). Mirror the `closeServer` clearing (~line 399) but **without** stopping advertising.
  - **Android** (`GattServer.kt`): `resetServerSessions()` clears the `connectedCentrals` map's announced-flags so `announceCentralIfNeeded` (Task 3.1) re-announces each still-connected central on its next request. If `BluetoothGattServer.getConnectedDevices()` is available, optionally re-announce them proactively.
  - Wire both through the per-package `android_server.dart` / `ios_server.dart` HostApi method (regenerate Pigeon if `resetServerSessions` is exposed as a HostApi call; otherwise implement directly in the `BlueyPlatform` subclass).

- [ ] **Step 6: Implement the fake hook.** In `fake_platform.dart`: add `simulateSurvivingAnnouncedCentral(String mac)` (records a survivor) and make `resetServerSessions()` re-emit `centralConnections` for each survivor (then clear the survivor set). This models the native contract observably.

- [ ] **Step 7: Run, confirm PASS + all packages green + analyze:**
```bash
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test && flutter analyze
cd ../bluey_platform_interface && flutter test && flutter analyze
cd ../bluey_android && flutter analyze
cd ../bluey_ios && flutter analyze
```

- [ ] **Step 8: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_platform_interface/lib/src/platform_interface.dart \
        bluey/lib/src/gatt_server/bluey_server.dart \
        bluey_android/lib/src/android_server.dart bluey_ios/lib/src/ios_server.dart \
        bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt \
        bluey_ios/ios/Classes/PeripheralManagerImpl.swift \
        bluey/test/fakes/fake_platform.dart \
        bluey/test/gatt_server/eviction_session_coherence_test.dart
# include regenerated Pigeon files if resetServerSessions became a HostApi method
git commit -m "feat(platform): reset announced-state on server (re)init so survivors re-announce (I338 Stage 3)"
```

---

# Stage 4 — docs + real-device dogfood (gating before close)

## Task 4.1: Documentation

**Files:**
- Modify: `bluey/lib/src/gatt_server/server.dart` (`disconnections` / `peerConnections` docs — note the eviction model on inferring platforms)
- Modify: `bluey/docs/cross-platform-quirks.md` (the iOS clean-reconnect blip)
- Modify: `bluey/lib/src/shared/exceptions.dart` (doc the new `DisconnectReason.evictedByServer` if not already inline)
- Modify: `bluey/CHANGELOG.md` (or the package changelog) — additive `Capabilities.reportsCentralDisconnects` is already noted from Stage 1; add the `DisconnectReason.evictedByServer` line and the iOS reconnect behavior change
- Modify: `docs/backlog/README.md` + the `docs/backlog/I338-*.md` entry — mark the iOS half resolved

- [ ] **Step 1:** Add to `cross-platform-quirks.md`: on iOS-server, a peer that pauses past the silence timeout is **evicted** — its next request is rejected with a reserved status and it reconnects cleanly into a fresh, frame-aligned session (a brief reconnect blip), whereas Android resumes seamlessly. Both are non-corrupting; tunable via `peerSilenceTimeout` / `lifecycleInterval`. Cross-reference Stage 1's Android note.
- [ ] **Step 2:** Update `server.dart` docs to describe the established-session model and that `peerConnections` re-emits only after a real reconnect on inferring platforms (no phantom re-emit on heartbeat resume).
- [ ] **Step 3:** Mark the I338 backlog entry's iOS half resolved (Stage 1 fixed Android; Stage 2–3 fixes iOS). Note the empirical-confirmation residual (Task 4.2) if dogfood is pending at commit time.
- [ ] **Step 4: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/gatt_server/server.dart bluey/docs/cross-platform-quirks.md \
        bluey/lib/src/shared/exceptions.dart bluey/CHANGELOG.md \
        docs/backlog/README.md docs/backlog/I338-*.md
git commit -m "docs(gatt-server): document iOS eviction→clean-reconnect model (I338 Stage 2-3)"
```

## Task 4.2: Real-device dogfood (gossip_chat) — the load-bearing real-world claim

This confirms the design's empirical residual from Phase 0: that an iOS central actually surfaces the `0x80` ATT write-response status to Dart (vs masking), and that the eviction→reconnect yields **frame-aligned reassembly** on hardware.

- [ ] **Step 1:** Build/run the `gossip_chat` example (or the project's dogfood app) on **two real devices**, at least one pairing exercising an **iOS server** (iOS↔iOS and Android→iOS).
- [ ] **Step 2:** Reproduce the I338 trigger: background/pause the central app past `lifecycleInterval` so the server's silence timer fires and removes the session; then resume the central.
- [ ] **Step 3: Confirm on the wire/logs:**
  - The resumed heartbeat (or app write) returns the reserved status → `LifecycleClient` self-disconnects → `DisconnectedException(evictedByServer)` is observable.
  - The app reconnects via its existing logic; a fresh `centralConnections` → re-identify → `peerConnections` re-emits.
  - The consumer's frame decoder rebuilds on a **frame-aligned** stream — no mid-frame reassembly, no discarded throughput.
- [ ] **Step 4:** If a platform **masks** the `0x80` write-response status (the resumed heartbeat does not surface it), the Task 2.4 heartbeat fast-path is the fallback already in place; record the empirical finding in the spec's Phase 0 section (a short follow-up note) and confirm the heartbeat path still drives the clean reconnect.
- [ ] **Step 5:** Record the dogfood result (pass/fail per platform pairing) in the I338 backlog entry / spec. Do not consider Stage 2–3 closed until iOS-server eviction→clean-reconnect is confirmed on hardware.

---

## Self-Review

**Spec coverage (Stage 2–3 scope):**
- Reserved ATT status on the platform-interface surface + Pigeon + native respond paths → Tasks 2.1, 2.2. ✓
- `BlueyServer` chokepoint rejects requests with no established session → Task 2.5. ✓
- Inferring-path silence removes the session → already shipped in Stage 1 (`_handleLifecycleSilence` → `_handleClientDisconnected`); relied upon, not re-implemented. ✓
- Remove "establish from unknown heartbeat" in `_trackPeerClient` → Task 2.5 Step 5. ✓
- Client-side translation: reserved status → `BlueyConnection` self-disconnect + `DisconnectedException(evictedByServer)` → Tasks 2.3 (translation) + 2.4 (heartbeat-driven self-disconnect). ✓
- `DisconnectReason.evictedByServer` → Task 2.3. ✓
- Collision-safety guard (public `GattResponseStatus` unchanged) → enforced in "Key constants" + Task 2.5 (server emits via `PlatformGattStatus` directly). ✓
- Precise establishment ordering: announce-before-forward (Android fix; iOS holds per Phase 0) → Task 3.1; reset-announced-on-init → Task 3.2. ✓
- I338 headline regression → Task 2.7. ✓
- Docs (`cross-platform-quirks.md`, `disconnections`/`peerConnections`, changelog, backlog) → Task 4.1. ✓
- Device dogfood (empirical `0x80` delivery + frame-aligned reassembly) → Task 4.2. ✓

**Placeholder scan:** native Kotlin/Swift steps reference exact Phase-0 file:line sites and mirror the documented iOS pattern; the two parametric areas (the file's existing test-double/fakeAsync conventions in `lifecycle_client_test.dart` and the per-package server-test mocking) are explicitly flagged to match the existing file, not left as "TODO."

**Type consistency:** `lifecycleEvictionAttStatus` (int 0x80), `PlatformGattStatus.lifecycleEviction`, `GattStatusDto.lifecycleEviction` / `GattStatusDto.LIFECYCLE_EVICTION` (Kotlin), `DisconnectReason.evictedByServer`, `_hasEstablishedSession(ClientAddress)`, `resetServerSessions()`, `announceCentralIfNeeded(BluetoothDevice)` used consistently across tasks. `respondToWriteRequest(int, PlatformGattStatus)` and `respondToReadRequest(int, PlatformGattStatus, Uint8List?)` signatures match the Phase-0 platform-interface map.

**Ordering safety:** the Stage 2 gate (Task 2.5) is uniform, but it only ever evicts a *live* central during the Android connect-race window — closed by Task 3.1 (announce-before-forward). Execute Stage 3 in the same branch before the dogfood; on Android the gate + advisory-silence (Stage 1) mean a live central always retains its session once ordering is enforced.
