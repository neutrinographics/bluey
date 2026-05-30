# Lifecycle-silence ⇄ transport reconciliation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the GATT-server's heartbeat-silence timeout from masquerading as a transport disconnect, so it no longer corrupts consumers' stream framing.

**Architecture:** Capability-gated handling keyed on the *server's* platform. Android (`reportsCentralDisconnects == true`) treats silence as advisory and lets the native disconnect callback drive `disconnections`; iOS (`false`) keeps silence-as-disconnect but (Stage 2) arms a session-coherence/eviction handshake so a paused peer returns via a clean reconnect. The two events that today share `_handleClientDisconnected` are dis-conflated.

**Tech Stack:** Dart/Flutter (`bluey`, `bluey_platform_interface`), Pigeon, Kotlin (`bluey_android`), Swift (`bluey_ios`), `flutter_test`.

**Reference spec:** `docs/superpowers/specs/2026-05-30-lifecycle-silence-transport-reconciliation-design.md`

**Staging (why this plan is scoped to Phase 0 + Stage 1):** The spec's eviction handshake and precise-ordering invariant depend on four native-behavior assumptions the spec flags as *gating*. This plan resolves those (Phase 0) and delivers the fully-specifiable, pure-Dart fix that closes the **Android** half of the bug (Stage 1). Stages 2–3 (the reserved-status eviction handshake and the announce-before-forward invariant — both native-heavy) are written as a **follow-up plan** once Phase 0 confirms the native behaviors, so their Kotlin/Swift/Pigeon tasks aren't built on unverified ground. Stage 1 ships on its own (Android fixed; iOS unchanged from today, pending Stage 2).

---

## Phase 0 — Gating verification (investigation, no production code)

Resolve the spec's four gating items. Output: a findings note appended to the spec under a new `## Phase 0 findings (2026-05-30)` heading, recording each answer and any design adjustment. These outcomes determine the Stage 2–3 plan.

### Task 0.1: Native callback-queue & announce-before-forward

**Files (read only):**
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift` (`trackCentralIfNeeded`, `didReceiveWrite`, `didReceiveRead`, queue setup)
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` (`onCharacteristicWriteRequest`, `onCharacteristicReadRequest`, the central-connected announce)

- [ ] **Step 1: Determine the callback queue.** Confirm whether `CBPeripheralManager` is created with a dedicated serial dispatch queue (look for `CBPeripheralManager(delegate:queue:)` — `nil` means the main queue, which is serial) and whether Android's GATT server callbacks arrive on a single binder thread. Record the answer.
- [ ] **Step 2: Determine announce ordering.** In iOS `didReceiveWrite`, confirm whether `trackCentralIfNeeded` (→ `onCentralConnected`) is invoked *before* the write is forwarded to Dart (`flutterApi.onWriteRequest`). Do the same for Android's write handler (is the central announced before `flutterApi.onWriteRequest`?). Record file:line for each forward and announce site.
- [ ] **Step 3: Record outcome.** If both platforms announce-before-forward on a serial queue → the precise-ordering invariant holds; Stage 3 just enforces/locks it. If not → Stage 3 must add the session-epoch fallback (per the spec). Write the finding.

### Task 0.2: Flutter cross-channel ordering

- [ ] **Step 1:** Confirm the relied-upon property: two Pigeon `FlutterApi` calls issued sequentially from the same native thread/queue are delivered to Dart in that order. Check whether `onCentralConnected` and `onWriteRequest` are generated on the same Pigeon `BinaryMessenger` (same generated `pigeonVar_messageChannelSuffix`); note that Pigeon uses per-method channel names. Record whether ordering is guaranteed by construction or whether Stage 3 needs the epoch fallback to avoid relying on it.

### Task 0.3: Server-recreation native-manager reuse

**Files (read only):** `bluey/lib/src/bluey.dart` (`server()`, `dispose()`), `bluey_ios/.../PeripheralManagerImpl.swift` (lifecycle), `bluey_android/.../GattServer.kt` (`ensureServerOpen`, close), I333 invalidation path.

- [ ] **Step 1:** Determine whether a recreated `BlueyServer` (via adapter-cycle/I333 invalidation or a second `bluey.server()`) **reuses** the native peripheral manager / GATT server (so its `centrals`/`connectedCentrals` map and "announced" state survive) or gets a fresh native instance. Record the answer.
- [ ] **Step 2:** If reused → Stage 2 must include a native "reset announced-state on server init" step. If fresh → the stale-central case can't arise and that step is dropped. Write the finding.

### Task 0.4: Client-side application-range status delivery

**Files (read only):** `bluey_android/.../ConnectionManager.kt` (`onCharacteristicWrite`, `statusFailedError`), `bluey_ios/ios/Classes/CentralManagerImpl.swift` (write completion / NSError→status mapping, post-I091).

- [ ] **Step 1:** Confirm both client platforms carry a write-response ATT status byte to Dart (`GattOperationStatusFailedException(status)`): Android via `onCharacteristicWrite(status)` → `statusFailedError`, iOS via the I091 numeric-status preservation. Record file:line.
- [ ] **Step 2:** Note the residual: whether the OS delivers a `0x80–0x9F` code on a write response (vs masking). This is confirmed empirically in Stage 2's device dogfood, not here. If a platform is known to mask it, record that Stage 2 restricts the eviction signal to the heartbeat-write path (the `LifecycleClient` treats a heartbeat-write failure on a believed-live session as evict-and-reconnect).

- [ ] **Step 5 (Phase 0 close): Commit findings.**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add docs/superpowers/specs/2026-05-30-lifecycle-silence-transport-reconciliation-design.md
git commit -m "docs(I338): Phase 0 native-behavior verification findings"
```

---

## Stage 1 — Dart capability-gated A/B split (fixes the Android repro)

Pure Dart. After this stage: Android-server treats heartbeat silence as advisory (no phantom `disconnections`); iOS-server behavior is unchanged from today (still emits `disconnections` on silence — the iOS half is fixed in Stage 2).

### Task 1.1: Add `reportsCentralDisconnects` to `Capabilities`

**Files:**
- Modify: `bluey_platform_interface/lib/src/capabilities.dart`
- Test: `bluey_platform_interface/test/capabilities_test.dart`

- [ ] **Step 1: Write the failing test** (append to the existing capabilities test file; if none exists at that path, create it):

```dart
import 'package:bluey_platform_interface/src/capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reportsCentralDisconnects', () {
    test('android reports central disconnects, iOS infers', () {
      expect(Capabilities.android.reportsCentralDisconnects, isTrue);
      expect(Capabilities.iOS.reportsCentralDisconnects, isFalse);
    });

    test('fake preset reports central disconnects by default', () {
      expect(Capabilities.fake.reportsCentralDisconnects, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run, confirm FAIL** (`reportsCentralDisconnects` undefined):
`cd bluey_platform_interface && flutter test test/capabilities_test.dart`

- [ ] **Step 3: Implement.** In `capabilities.dart`: add the field, a constructor parameter (with a default so unrelated call sites don't break), and set it in the `android`/`iOS`/`fake`/`macOS`/`windows`/`linux` presets.
  - Add field (beside the other `final bool can…` fields):
    ```dart
    /// Whether the platform delivers a reliable native callback when a
    /// connected central disconnects from this device's GATT server.
    /// `true` on Android (`onConnectionStateChange`); `false` on iOS
    /// (`CBPeripheralManager` has no client-disconnect callback — I201),
    /// where disconnects are inferred from lifecycle heartbeat silence.
    final bool reportsCentralDisconnects;
    ```
  - Add to the `const Capabilities({...})` constructor: `this.reportsCentralDisconnects = false,` (default `false` = conservative/inferring; presets set the real value).
  - In the `android` preset add `reportsCentralDisconnects: true,`; in `iOS` add `reportsCentralDisconnects: false,`; in `fake` add `reportsCentralDisconnects: true,` (so existing server tests keep the authoritative path unless they opt out); set `macOS`/`windows`/`linux` to `true` (they have native disconnect callbacks) — or leave default `false` if unsure; record the choice in the `toString()` if it lists fields.
  - If `toString()` enumerates fields, add `reportsCentralDisconnects` there.

- [ ] **Step 4: Run, confirm PASS:**
`cd bluey_platform_interface && flutter test test/capabilities_test.dart`

- [ ] **Step 5: Analyze + commit:**
```bash
cd bluey_platform_interface && flutter analyze
cd /Users/joel/git/neutrinographics/bluey
git add bluey_platform_interface/lib/src/capabilities.dart bluey_platform_interface/test/capabilities_test.dart
git commit -m "feat(platform-interface): add Capabilities.reportsCentralDisconnects (I338)"
```

### Task 1.2: Dis-conflate — add `_handleLifecycleSilence`, branch on the capability

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart` (the `LifecycleServer` wiring at `:116` and a new handler near `_handleClientDisconnected` at `:895`)
- Test: `bluey/test/bluey_server_test.dart`

Context: today `LifecycleServer(onClientGone: _handleClientDisconnected, …)` wires the silence timer straight into the real-disconnect handler. `_handleClientDisconnected` emits `disconnections`, clears identification, removes the client. The real platform disconnect path (`_centralDisconnections.listen → _handleClientDisconnected`, `:176`) must keep that behavior; only the *silence* path changes.

- [ ] **Step 1: Write the failing test.** Use `FakeBlueyPlatform`. Two cases keyed on the capability. Add a `bluey/test/gatt_server/lifecycle_silence_test.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_platform.dart';

void main() {
  // The fake exposes a way to set capabilities + fire a lifecycle-silence
  // timeout for a connected central. Match the fake's actual helper names
  // (see test/fakes/fake_platform.dart); adjust if they differ.

  test('authoritative platform: silence does NOT emit disconnections', () async {
    final fake = FakeBlueyPlatform(); // reportsCentralDisconnects == true (fake default)
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');
    const mac = 'AA:BB:CC:DD:EE:FF';

    final gone = <ClientAddress>[];
    server.disconnections.listen(gone.add);

    fake.simulateCentralConnection(centralId: mac);
    await Future<void>.delayed(Duration.zero);
    fake.fireLifecycleSilence(mac); // server-side silence timeout for this central
    await Future<void>.delayed(Duration.zero);

    expect(gone, isEmpty, reason: 'silence is advisory on an authoritative platform');
    expect(server.isClientConnected(const ClientAddress(mac)), isTrue);
    await bluey.dispose();
  });

  test('inferring platform: silence DOES emit disconnections (current iOS behavior)', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    final bluey = await Bluey.create(platform: fake);
    final server = bluey.server()!;
    await server.startAdvertising(name: 't');
    const mac = 'AA:BB:CC:DD:EE:FF';

    final gone = <ClientAddress>[];
    server.disconnections.listen(gone.add);

    fake.simulateCentralConnection(centralId: mac);
    await Future<void>.delayed(Duration.zero);
    fake.fireLifecycleSilence(mac);
    await Future<void>.delayed(Duration.zero);

    expect(gone, equals([const ClientAddress(mac)]));
    await bluey.dispose();
  });
}
```

- [ ] **Step 2: Make the fake support the test.** In `bluey/test/fakes/fake_platform.dart`: allow constructing with a chosen `Capabilities` (add a `reportsCentralDisconnects` constructor param that produces `Capabilities.fake` with that flag overridden), and add `fireLifecycleSilence(String centralId)` that drives the server's lifecycle timer to expiry for that central (e.g., by injecting the control-service write path / exposing the `LifecycleServer` timer, matching how existing lifecycle tests trigger a timeout — see `bluey_server_test.dart:1086` peerConnections test and the lifecycle timer). If a direct hook is cleaner, expose it; keep it test-only.

- [ ] **Step 3: Run, confirm FAIL** (authoritative case still emits `disconnections` today):
`cd bluey && flutter test test/gatt_server/lifecycle_silence_test.dart`

- [ ] **Step 4: Implement the split** in `bluey/lib/src/gatt_server/bluey_server.dart`:
  - Change the wiring at `:116` from `onClientGone: _handleClientDisconnected,` to `onClientGone: _handleLifecycleSilence,`.
  - Add the new handler next to `_handleClientDisconnected`:
    ```dart
    /// Lifecycle heartbeat-silence timeout for [clientAddress].
    ///
    /// Distinct from a real platform disconnect (`_handleClientDisconnected`).
    /// On platforms that report central disconnects natively the silence is
    /// advisory only — the platform callback remains the sole source of
    /// `disconnections`. On inferring platforms (iOS) silence is the disconnect
    /// signal and is forwarded to the disconnect path. (Stage 2 adds session
    /// removal + eviction on the inferring path.)
    void _handleLifecycleSilence(ClientAddress clientAddress) {
      if (_platform.capabilities.reportsCentralDisconnects) {
        // Advisory only. The ClientLifecycleTimeoutEvent was already emitted by
        // LifecycleServer; the platform's onConnectionStateChange will drive any
        // real disconnect. Do not emit disconnections or clear identification.
        return;
      }
      // Inferring platform: silence is the best disconnect signal available.
      _handleClientDisconnected(clientAddress);
    }
    ```

- [ ] **Step 5: Run, confirm PASS** (both cases):
`cd bluey && flutter test test/gatt_server/lifecycle_silence_test.dart`

- [ ] **Step 6: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/gatt_server/bluey_server.dart bluey/test/gatt_server/lifecycle_silence_test.dart bluey/test/fakes/fake_platform.dart
git commit -m "feat(gatt-server): silence timeout advisory-only on authoritative platforms (I338 Stage 1)"
```

### Task 1.3: Update existing tests that assumed unconditional silence→disconnections

**Files:**
- Modify: `bluey/test/bluey_server_test.dart`, `bluey/test/connection/lifecycle_events_test.dart`

- [ ] **Step 1: Run the full suite to find the breakers:**
`cd bluey && flutter test 2>&1 | grep -A3 FAIL` (or run the two files directly).
Expected: tests that connect a central, fire a silence timeout, and assert `disconnections` emits — now fail under the default `fake` (authoritative) path.

- [ ] **Step 2: Fix each.** For a test whose intent is "silence → disconnect," set the fake to the inferring path (`FakeBlueyPlatform(reportsCentralDisconnects: false)`) so the assertion holds. For a test whose intent is unrelated (just needs a disconnect), drive a *real* `simulateCentralDisconnection(...)` instead of a silence timeout. Do not weaken assertions — pick the path that matches the test's actual intent. Representative:
```dart
// before: relied on silence emitting disconnections under the default fake
final fake = FakeBlueyPlatform();
// ... fireLifecycleSilence(mac); expect(gone, [ClientAddress(mac)]);
// after: this test is specifically about the inferring (silence-as-disconnect) path
final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
```

- [ ] **Step 3: Run, confirm green:**
`cd bluey && flutter analyze && flutter test`
Expected: all pass.

- [ ] **Step 4: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/test
git commit -m "test(gatt-server): split silence→disconnections tests by capability (I338 Stage 1)"
```

### Task 1.4: Document the Android behavior change

**Files:**
- Modify: `bluey/lib/src/gatt_server/server.dart` (the `disconnections` doc), `bluey/docs/cross-platform-quirks.md`

- [ ] **Step 1:** Update the `Stream<ClientAddress> get disconnections;` doc comment to state: emits when the transport link is actually gone — driven by the platform's native disconnect callback where available (Android), and inferred from lifecycle heartbeat silence where not (iOS).
- [ ] **Step 2:** Add a short note to `cross-platform-quirks.md`: on Android a heartbeat lull (peer app paused past the silence timeout) no longer produces a `disconnections` event — only a `ClientLifecycleTimeoutEvent` advisory; the real disconnect comes from the platform. (The iOS clean-reconnect half lands in Stage 2.)
- [ ] **Step 3: Commit:**
```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/lib/src/gatt_server/server.dart bluey/docs/cross-platform-quirks.md
git commit -m "docs(gatt-server): document advisory-only silence on Android (I338 Stage 1)"
```

---

## Stages 2 & 3 — follow-up plan (gated on Phase 0)

**Not detailed here by design** — their tasks depend on Phase 0 outcomes (native queue/ordering, manager reuse, status delivery). Write `docs/superpowers/plans/<date>-lifecycle-silence-stage2-eviction.md` after Phase 0, covering:

- **Stage 2 — eviction handshake & session coherence (fixes iOS):** reserved ATT status (`0x80–0x9F`) added to the platform-interface status surface + Pigeon + Android/iOS `respondTo{Read,Write}Request` native paths; `BlueyServer` chokepoint rejects requests with no established session; inferring-path silence removes the session; remove the "establish from unknown heartbeat" behavior in `_trackPeerClient` on the inferring path; client-side error-translation maps the reserved status → `BlueyConnection.disconnect()` + `DisconnectedException(evictedByServer)`; add `DisconnectReason.evictedByServer`; the I338 headline regression test; device dogfood.
- **Stage 3 — precise establishment ordering:** enforce/lock the native announce-before-forward invariant and (if Phase 0 found reuse) reset-announced-on-init; or the session-epoch fallback if Phase 0 found ordering can't be guaranteed.

---

## Self-Review

**Spec coverage (Stage 1 scope):** capability `reportsCentralDisconnects` → Task 1.1; handler dis-conflation + authoritative/inferring branch → Task 1.2; existing-test split → Task 1.3; `disconnections` semantics + quirks doc → Task 1.4. The eviction handshake, session-coherence, reserved-status, `DisconnectReason.evictedByServer`, and precise-ordering sections are explicitly deferred to the gated Stage 2–3 follow-up (with Phase 0 resolving their prerequisites) — recorded, not dropped.

**Placeholder scan:** Phase 0 tasks are investigation (no production code) and say exactly what to read/confirm and what each outcome implies — not "TODO." Stage 1 tasks carry complete code. The one parametric area (the fake's `fireLifecycleSilence`/`simulateCentralConnection` helper names) is explicitly flagged to match `test/fakes/fake_platform.dart`.

**Type consistency:** `reportsCentralDisconnects` (bool), `_handleLifecycleSilence(ClientAddress)`, `_handleClientDisconnected(ClientAddress)`, `FakeBlueyPlatform(reportsCentralDisconnects: ...)`, `ClientAddress`, `simulateCentralConnection(centralId:)` used consistently across tasks.
