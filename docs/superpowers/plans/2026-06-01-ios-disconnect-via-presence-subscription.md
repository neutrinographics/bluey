# iOS-server disconnect via presence subscription (Pattern B) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iOS GATT server a real client-disconnect signal (a central unsubscribing from a dedicated presence characteristic) and flip it to the authoritative path, so heartbeat silence becomes advisory — eliminating the eviction handshake and the Codex-P1 loop while keeping all four I338 guarantees.

**Architecture:** Add a notify-only **presence** characteristic to the lifecycle control service; the client subscribes on connect and never voluntarily unsubscribes. iOS `didUnsubscribe(presence)` → remove the central + `onCentralDisconnected` → the *existing* `centralDisconnections` → `_handleClientDisconnected`. Flip `Capabilities.iOS.reportsCentralDisconnects` to `true` so `_handleLifecycleSilence` returns early (advisory). The Stage-2/3 eviction code stays in place but dormant behind `reportsCentralDisconnects == false`.

**Tech Stack:** Dart/Flutter (`bluey`, `bluey_platform_interface`), Swift (`bluey_ios`), `flutter_test`, `fake_async`.

**Reference spec:** `docs/superpowers/specs/2026-06-01-ios-disconnect-via-presence-subscription-design.md`

**Branch:** `i338-disconnect-via-presence` (already created off `i338-stage2-eviction`). Do NOT push without being asked.

**Key seam fact (verified):** the Stage-2 session-gate (`_hasEstablishedSession`) is *unconditional* — it runs under both capability values. Under Pattern B it never fires (sessions are established by the real connect signal via announce-before-forward), so it stays as a harmless dormant safety net; no change needed.

---

## Task 1: Presence characteristic in the control service

**Files:**
- Modify: `bluey/lib/src/lifecycle.dart`
- Test: `bluey/test/lifecycle_test.dart`

- [ ] **Step 1: Write the failing test.** Append a group to `bluey/test/lifecycle_test.dart` (reuse the existing `package:bluey/src/lifecycle.dart` import):

```dart
  group('presence characteristic', () {
    test('control service includes a notify-only presence characteristic', () {
      final svc = buildControlService();
      final presence = svc.characteristics
          .firstWhere((c) => c.uuid.toLowerCase() == presenceCharUuid);
      expect(presence.properties.canNotify, isTrue);
      expect(presence.properties.canWrite, isFalse);
      expect(presence.properties.canRead, isFalse);
    });

    test('isControlServiceCharacteristic recognises the presence char', () {
      expect(isControlServiceCharacteristic(presenceCharUuid), isTrue);
    });
  });
```

- [ ] **Step 2: Run, confirm FAIL** (`presenceCharUuid` undefined): `cd bluey && flutter test test/lifecycle_test.dart`

- [ ] **Step 3: Implement** in `bluey/lib/src/lifecycle.dart`:
  - Add the UUID constant next to the others (~line 26): `const _presenceCharUuidString = 'b1e70005-0000-1000-8000-00805f9b34fb';`
  - Add the public export next to the others (~line 39): `final presenceCharUuid = _presenceCharUuidString;`
  - In `buildControlService()` add a 4th characteristic (after `serverId`):
```dart
      PlatformLocalCharacteristic(
        uuid: _presenceCharUuidString,
        properties: const PlatformCharacteristicProperties(
          canRead: false,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: true,
          canIndicate: false,
        ),
        permissions: const [PlatformGattPermission.read],
        descriptors: const [],
      ),
```
  - In `isControlServiceCharacteristic`, add `|| normalized == _presenceCharUuidString` to the return.

- [ ] **Step 4: Run, confirm PASS + analyze:** `cd bluey && flutter test test/lifecycle_test.dart && flutter analyze lib/src/lifecycle.dart`

- [ ] **Step 5: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/lifecycle.dart bluey/test/lifecycle_test.dart
git commit -m "feat(lifecycle): add notify-only presence characteristic to the control service"
```

---

## Task 2: Client subscribes to presence on connect

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart` (`start()`, ~line 235)
- Test: `bluey/test/connection/lifecycle_client_test.dart`

Context: `LifecycleClient.start()` locates the control service and the heartbeat char. Add: locate the presence char and subscribe to it via `presenceChar.notifications.listen(...)` (which auto-enables notifications through `_onFirstListen` → `setNotification`). Hold the subscription for the client's lifetime; cancel it in `stop()`.

- [ ] **Step 1: Write the failing test.** Append to `bluey/test/connection/lifecycle_client_test.dart`. READ `_setUpConnectedClient` first — its services fixture must include the presence char (update the fixture's control service to add a presence `RemoteCharacteristic`, mirroring how it builds heartbeat/interval chars; the fake's `setNotification` records the handle in the connection's `subscribedCharacteristics`). Use `fakeAsync` (no real delays):

```dart
    test('subscribes to the presence characteristic on start', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;
        _setUpConnectedClient(onServerUnreachable: () {}).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // The fake records setNotification(enable:true) calls; assert the
        // presence characteristic handle was enabled.
        expect(
          fakePlatform.setNotificationCalls.any(
            (c) => c.enable && c.characteristicUuid == lifecycle.presenceCharUuid,
          ),
          isTrue,
          reason: 'presence subscription must be enabled on start',
        );
      });
    });
```
> The exact assertion hook depends on what the fake exposes. If the fake records `setNotification` by HANDLE not UUID, assert against the presence char's handle (resolve it from the fixture). If the fake has no `setNotificationCalls` recorder, add one in Task 2 Step 3b (a `final List<SetNotificationCall> setNotificationCalls = []` populated in `setNotification`, carrying handle + the resolved UUID + enable). Match the fake's existing call-recorder pattern (`writeCharacteristicCalls`, `respondWriteCalls`).

- [ ] **Step 2: Run, confirm FAIL.** `cd bluey && flutter test test/connection/lifecycle_client_test.dart`

- [ ] **Step 3a: Implement the subscribe** in `lifecycle_client.dart` `start()`, after the heartbeat char is located and `_isRunning = true`, before/after `_sendProbe()`:
```dart
    // Subscribe to the presence characteristic so the server (iOS) gets a
    // real disconnect signal via didUnsubscribe when this link drops. The
    // client never voluntarily unsubscribes while running; stop() cancels it.
    final presenceChar = controlService
        .characteristics()
        .where((c) =>
            c.uuid.toString().toLowerCase() == lifecycle.presenceCharUuid)
        .firstOrNull;
    if (presenceChar != null) {
      _presenceSub = presenceChar.notifications.listen(
        (_) {}, // presence char carries no payload; the subscription IS the signal
        onError: (_) {},
      );
    }
```
  - Add the field near the other subscriptions: `StreamSubscription<Uint8List>? _presenceSub;`
  - In `stop()`, cancel it: `_presenceSub?.cancel(); _presenceSub = null;` (add alongside the existing cleanup).

- [ ] **Step 3b (only if needed):** add the `setNotificationCalls` recorder to `fake_platform.dart` per the Step-1 note, and add the presence char to `_setUpConnectedClient`'s services fixture.

- [ ] **Step 4: Run, confirm PASS + full lifecycle suite + analyze:**
```bash
cd bluey && flutter test test/connection/lifecycle_client_test.dart && flutter analyze lib/src/connection/lifecycle_client.dart
```

- [ ] **Step 5: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/connection/lifecycle_client.dart bluey/test/connection/lifecycle_client_test.dart bluey/test/fakes/fake_platform.dart
git commit -m "feat(connection): client subscribes to the presence characteristic on connect"
```

---

## Task 3: Flip iOS to authoritative + update the silence tests

**Files:**
- Modify: `bluey_platform_interface/lib/src/capabilities.dart` (`Capabilities.iOS`)
- Modify: `bluey/test/gatt_server/lifecycle_silence_test.dart` (the "inferring iOS" test → advisory)
- Test: `bluey_platform_interface/test/capabilities_test.dart`

- [ ] **Step 1: Write/adjust the failing tests.**
  - In `bluey_platform_interface/test/capabilities_test.dart`, change the iOS expectation to `true`:
```dart
    test('iOS reports central disconnects (Pattern B — presence-unsubscribe)', () {
      expect(Capabilities.iOS.reportsCentralDisconnects, isTrue);
    });
```
  - In `bluey/test/gatt_server/lifecycle_silence_test.dart`, the test `'I338: inferring platform — silence DOES emit disconnections (current iOS behaviour)'` (uses `FakeBlueyPlatform(reportsCentralDisconnects: false)` and asserts `gone == [mac]`) — rename + re-purpose it to assert the iOS-now-advisory behaviour. Replace it with:
```dart
  test('Pattern B: iOS (authoritative) — silence does NOT emit disconnections',
      () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _silenceInterval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final gone = <ClientAddress>[];
      server.disconnections.listen(gone.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.fireLifecycleSilence(_mac);
      async.flushMicrotasks();
      async.elapse(_silenceInterval);
      expect(gone, isEmpty,
          reason: 'silence is advisory on iOS under Pattern B; '
              'disconnects come from presence-unsubscribe');
      expect(server.isClientConnected(const ClientAddress(_mac)), isTrue);
      server.dispose();
      bluey.dispose();
    });
  });
```
  (Keep the existing "authoritative — silence does NOT emit disconnections" test as-is; it now documents the same behaviour generically.)

- [ ] **Step 2: Run, confirm FAIL:**
```bash
cd bluey_platform_interface && flutter test test/capabilities_test.dart
cd ../bluey && flutter test test/gatt_server/lifecycle_silence_test.dart
```

- [ ] **Step 3: Implement.** In `bluey_platform_interface/lib/src/capabilities.dart`, in the `Capabilities.iOS` preset, change `reportsCentralDisconnects: false` → `reportsCentralDisconnects: true`. Update its doc comment to note iOS now reports disconnects via the presence-unsubscribe mechanism (Pattern B), not a native callback.

- [ ] **Step 4: Run, confirm PASS + both full suites + analyze:**
```bash
cd bluey_platform_interface && flutter test && flutter analyze
cd ../bluey && flutter test test/gatt_server/ && flutter analyze
```
> The full `bluey` suite may surface other tests that hard-coded iOS=`false` semantics. The `eviction_session_coherence_test.dart` tests explicitly pass `reportsCentralDisconnects: false` — they STAY (dormant-fallback coverage for the eviction path). Do NOT change them. If any *other* test breaks because it assumed iOS evicts on silence, update it to the advisory expectation (matching the rename above). List any you change.

- [ ] **Step 5: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_platform_interface/lib/src/capabilities.dart bluey_platform_interface/test/capabilities_test.dart bluey/test/gatt_server/lifecycle_silence_test.dart
git commit -m "feat(platform-interface): iOS reports central disconnects (Pattern B); silence advisory"
```

---

## Task 4: Pattern-B server behavior — disconnect + reconnect recovery (the Codex-P1 resolution, at the domain seam)

**Files:**
- Test (create): `bluey/test/gatt_server/pattern_b_disconnect_test.dart`

Context: at the platform-interface seam, Pattern B's disconnect is just `centralDisconnections`. This task proves BlueyServer's authoritative path gives clean disconnect + **loop-free reconnect recovery** + no-eviction-under-the-flip, using the existing fake signals. (The native side that *produces* these signals is Task 6.)

- [ ] **Step 1: Write the tests.** Create `bluey/test/gatt_server/pattern_b_disconnect_test.dart`:

```dart
import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart' show BlueyPlatform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_platform.dart';

const _mac = 'AA:BB:CC:DD:EE:FF';
const _char = '0000fff1-0000-1000-8000-00805f9b34fb';
const _interval = Duration(seconds: 5);

void main() {
  test('iOS: presence-unsubscribe (centralDisconnections) emits disconnections + removes session', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final gone = <ClientAddress>[];
      server.disconnections.listen(gone.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.simulateCentralDisconnection(_mac); // = iOS didUnsubscribe(presence)
      async.flushMicrotasks();
      expect(gone, equals([const ClientAddress(_mac)]));
      expect(server.isClientConnected(const ClientAddress(_mac)), isFalse);
      server.dispose();
      bluey.dispose();
    });
  });

  test('Codex-P1 resolved: reconnect after disconnect re-establishes cleanly (no loop)', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final forwarded = <WriteRequest>[];
      server.writeRequests.listen(forwarded.add);

      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.simulateCentralDisconnection(_mac);
      async.flushMicrotasks();
      // Reconnect (same identity — models centrals cleared on disconnect → re-announce).
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();

      expect(server.isClientConnected(const ClientAddress(_mac)), isTrue,
          reason: 'reconnect re-establishes the session — no eviction loop');
      // A request from the reconnected client is serviced, not evicted.
      fake.simulateWriteRequest(
        centralId: _mac, characteristicUuid: _char,
        value: Uint8List.fromList([1]), responseNeeded: false,
      );
      async.flushMicrotasks();
      expect(forwarded, hasLength(1));
      server.dispose();
      bluey.dispose();
    });
  });

  test('no eviction under the flip: silence then a request is serviced, not evicted', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final forwarded = <WriteRequest>[];
      server.writeRequests.listen(forwarded.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.fireLifecycleSilence(_mac);
      async.flushMicrotasks();
      async.elapse(_interval); // silence fires — advisory, session retained
      fake.simulateWriteRequest(
        centralId: _mac, characteristicUuid: _char,
        value: Uint8List.fromList([2]), responseNeeded: false,
      );
      async.flushMicrotasks();
      expect(forwarded, hasLength(1),
          reason: 'session retained through silence → request serviced, not evicted');
      server.dispose();
      bluey.dispose();
    });
  });
}
```
> Verify `simulateWriteRequest`/`simulateCentralConnection`/`simulateCentralDisconnection` signatures against the fake (Task-3 agent confirmed them). Adjust the char UUID if the fake requires a registered handle.

- [ ] **Step 2: Run.** `cd bluey && flutter test test/gatt_server/pattern_b_disconnect_test.dart` — these likely PASS already (the authoritative path + the unconditional gate behave correctly). If any fails, it reveals a real domain gap to fix before proceeding. Treat a green run as characterization that the domain seam supports Pattern B; a red run as a bug to investigate.

- [ ] **Step 3: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/test/gatt_server/pattern_b_disconnect_test.dart
git commit -m "test(gatt-server): Pattern-B disconnect + loop-free reconnect recovery at the domain seam"
```

---

## Task 5: The `didUnsubscribe`-miss case (the honest empirical gap)

**Files:**
- Modify: `bluey/test/fakes/fake_platform.dart` (add `simulateSilentLinkLoss`)
- Test: `bluey/test/gatt_server/pattern_b_disconnect_test.dart` (append)

Context: if iOS's `didUnsubscribe` fails to fire on a real loss (the flaky case), no `centralDisconnections` is emitted → the disconnect is missed. Model it explicitly so the dependency is visible and the dormant-eviction fallback is justified.

- [ ] **Step 1: Add the fake helper.** In `fake_platform.dart`, next to `simulateCentralDisconnection`:
```dart
  /// Models an iOS link loss where `didUnsubscribe` did NOT fire (the flaky
  /// case): the transport central is gone, but NO `centralDisconnections`
  /// signal is emitted — so the server never learns. Used to make Pattern B's
  /// empirical dependency on `didUnsubscribe` reliability explicit.
  void simulateSilentLinkLoss(String centralId) {
    _connectedCentrals.remove(centralId);
    // Deliberately does NOT add to _centralDisconnectionController.
  }
```

- [ ] **Step 2: Write the test.** Append to `pattern_b_disconnect_test.dart`:
```dart
  test('didUnsubscribe-miss: a silent link loss is NOT detected (justifies the dormant eviction fallback)', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final gone = <ClientAddress>[];
      server.disconnections.listen(gone.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.simulateSilentLinkLoss(_mac); // didUnsubscribe didn't fire
      async.flushMicrotasks();
      async.elapse(_interval * 3); // even long silence is advisory under the flip
      expect(gone, isEmpty,
          reason: 'without the didUnsubscribe signal, the loss is missed — '
              'the explicit, visible cost of Pattern B; covered by re-enabling '
              'the dormant eviction (reportsCentralDisconnects=false) if hardware proves the signal flaky');
      expect(server.isClientConnected(const ClientAddress(_mac)), isTrue);
      server.dispose();
      bluey.dispose();
    });
  });
```

- [ ] **Step 3: Run, confirm PASS:** `cd bluey && flutter test test/gatt_server/pattern_b_disconnect_test.dart`

- [ ] **Step 4: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/test/fakes/fake_platform.dart bluey/test/gatt_server/pattern_b_disconnect_test.dart
git commit -m "test(gatt-server): model the didUnsubscribe-miss gap (Pattern B empirical dependency)"
```

---

## Task 6: iOS native — presence-unsubscribe → onCentralDisconnected

**Files:**
- Modify: `bluey_ios/ios/Classes/PeripheralManagerImpl.swift` (`didUnsubscribe`)

Context: this is the native source of the `centralDisconnections` signal the domain layer already consumes. Not Dart-unit-testable; verified by an iOS/Kotlin-style compile is not possible here (no iOS build), so this is **dogfood-gated** — implement faithfully, mirroring Android's disconnect path.

- [ ] **Step 1: Implement.** In `PeripheralManagerImpl.swift` `didUnsubscribe`, after the existing `onCharacteristicUnsubscribed` call, add (gate strictly on the presence characteristic UUID so a data-characteristic unsubscribe stays a no-op):
```swift
    // Pattern B: a central unsubscribing from the dedicated presence
    // characteristic means it disconnected (graceful, or a supervision-timeout
    // link loss). It is the iOS server's real client-disconnect signal (I201
    // has no native callback). Only the presence char triggers this — a data
    // characteristic unsubscribe must NOT be treated as a disconnect.
    if charUuid == "b1e70005-0000-1000-8000-00805f9b34fb" {
        centrals.removeValue(forKey: centralId)
        flutterApi.onCentralDisconnected(centralId: centralId) { _ in }
    }
```
  - Replace the stale "We do NOT infer disconnection from unsubscribe events" comment block with a note that disconnect is now inferred *only* from the presence characteristic (data-char unsubscribes remain inert, preserving the original false-positive protection).
  - Define the presence UUID once as a Swift constant near the top of the class (e.g. `private static let presenceCharUuid = "b1e70005-0000-1000-8000-00805f9b34fb"`) and use it instead of the inline literal.

- [ ] **Step 2: Verify what's verifiable.** `cd bluey_ios && flutter analyze` (Dart side — won't compile Swift). If an iOS build is available, build the example for iOS to confirm Swift compiles; otherwise record Swift compilation + behavior as **dogfood-gated**.

- [ ] **Step 3: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_ios/ios/Classes/PeripheralManagerImpl.swift
git commit -m "feat(ios): presence-characteristic unsubscribe drives onCentralDisconnected (Pattern B)"
```

---

## Task 7: Docs + dormant-eviction note

**Files:**
- Modify: `bluey/docs/cross-platform-quirks.md`
- Modify: `bluey/lib/src/gatt_server/server.dart` (the `disconnections` doc)
- Modify: `bluey_ios/IOS_BLE_NOTES.md`
- Modify: `docs/backlog/I338-*.md` (note the iOS approach changed to Pattern B; eviction dormant)

- [ ] **Step 1:** `cross-platform-quirks.md`: iOS-server now detects client disconnects via the presence-subscription mechanism (a central leaving the presence subscriber list = disconnected; supervision-timeout-bound for ungraceful loss). Silence is advisory on both platforms — a paused peer resumes seamlessly. The empirical caveat: a real loss that fails to fire `didUnsubscribe` is missed until the link teardown; the eviction handshake remains as a re-enable-able fallback (`reportsCentralDisconnects`).
- [ ] **Step 2:** `server.dart` `disconnections` doc: driven by the platform's native disconnect callback (Android) or the presence-unsubscribe signal (iOS); never by heartbeat silence (advisory on both).
- [ ] **Step 3:** `IOS_BLE_NOTES.md`: document the presence-characteristic-unsubscribe disconnect mechanism + the dedicated-char rationale (avoids the data-char false-positive).
- [ ] **Step 4:** Backlog: note I338's iOS path moved from eviction to Pattern B; the eviction code is dormant behind the capability flag (not deleted); the Codex-P1 loop is resolved.
- [ ] **Step 5:** `cd bluey && flutter analyze` (doc-comment refs intact). Commit:
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/docs/cross-platform-quirks.md bluey/lib/src/gatt_server/server.dart bluey_ios/IOS_BLE_NOTES.md docs/backlog/I338-*.md
git commit -m "docs: iOS disconnect via presence subscription (Pattern B); eviction now dormant"
```

---

## Task 8: Full-suite verification + dogfood handoff

- [ ] **Step 1: All Dart suites green + analyze:**
```bash
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test && flutter analyze
cd ../bluey_platform_interface && flutter test && flutter analyze
cd ../bluey_android && flutter test && flutter analyze
cd ../bluey_ios && flutter test && flutter analyze
```
- [ ] **Step 2: Android APK build** (confirms the cross-package wiring compiles): `cd bluey/example && flutter build apk --debug`.
- [ ] **Step 3: Dogfood (user-driven, gating).** iOS server + a peer client: (a) **disconnect** the client (background-kill / BT off / out of range) → server emits `disconnections` within the supervision window (confirm `didUnsubscribe(presence)` fires); (b) **pause then resume** the client past the silence interval → **seamless**, no `disconnections`, no reconnect, frame-aligned; (c) **reconnect** after a real disconnect → re-establishes cleanly, **no loop**. Capture iOS logs (`bluey.ios.peripheral` / `bluey.server`). If (a) proves `didUnsubscribe` unreliable on a loss mode, record it and the fallback is to flip `reportsCentralDisconnects` back to `false` (eviction).

---

## Self-Review

**Spec coverage:** presence char → Task 1; client subscribe → Task 2; capability flip + advisory silence → Task 3; disconnect via the real signal + loop-free recovery + no-eviction-under-flip → Task 4; the didUnsubscribe-miss honesty test → Task 5; iOS `didUnsubscribe(presence)` → `onCentralDisconnected` native wiring → Task 6; docs + dormant-eviction + the empirical-confirm → Tasks 7–8. The parameterized "model" reduces (correctly) to: the existing fake signals + the capability flip + `simulateSilentLinkLoss` (the one new knob), because the platform-interface seam already abstracts the native subscribe/unsubscribe into `centralConnections`/`centralDisconnections`. Heartbeats retained (carry identity); eviction kept dormant (unconditional gate is a harmless safety net) — both per spec.

**Placeholder scan:** every code step carries concrete code. The two flagged parametric spots — the fake's `setNotification` recorder (Task 2 Step 3b) and the `_setUpConnectedClient` services fixture — are called out with the exact pattern to match, not left vague.

**Type consistency:** `presenceCharUuid`/`_presenceCharUuidString` (`b1e70005-…`), `reportsCentralDisconnects`, `simulateCentralConnection`/`simulateCentralDisconnection`/`fireLifecycleSilence`/`simulateSilentLinkLoss`/`simulateWriteRequest`, `_presenceSub`, `onCentralDisconnected` used consistently across tasks. The iOS native UUID literal matches the Dart constant exactly.
