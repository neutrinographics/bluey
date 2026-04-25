# I079 Server-Side Pending-Request Tolerance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `LifecycleServer` from declaring a client gone while it's still holding a pending read/write request from that client. Fixes I079: a server-app delay longer than `lifecycleInterval` (~10 s default) reliably tears down the connection mid-request.

**Architecture:** Replace `LifecycleServer`'s `Map<String, Timer> _heartbeatTimers` with `Map<String, _ClientLiveness>` where `_ClientLiveness` holds both the (nullable, paused-when-null) timer and a `Set<int>` of pending platform request IDs. Add `requestStarted` / `requestCompleted` API. Wire `BlueyServer`'s request-arrival paths and `respondToRead` / `respondToWrite` to drive the new API. `requestCompleted` fires *before* the platform respond call so the pending set drains even if the platform throws.

**Tech Stack:** Dart, `Timer` (dart:async), `FakeAsync` for deterministic tests, `FakeBlueyPlatform` (lifecycle-server unit tests), `MockBlueyPlatform` (BlueyServer integration tests).

**Spec:** [`docs/superpowers/specs/2026-04-25-i079-lifecycle-server-pending-request-tolerance-design.md`](../specs/2026-04-25-i079-lifecycle-server-pending-request-tolerance-design.md).

**Working directory for all commands:** `/Users/joel/git/neutrinographics/bluey`.

**Branch:** create and execute on `fix/i079-server-pending-request-tolerance` off `main`.

---

## File Structure

| File | Role |
|---|---|
| `bluey/lib/src/gatt_server/lifecycle_server.dart` | Add `_ClientLiveness`, migrate state, add `requestStarted` / `requestCompleted`, modify `_resetTimer` / `cancelTimer` / `dispose` / `recordActivity` |
| `bluey/lib/src/gatt_server/bluey_server.dart` | Wire arrival paths + `respondToRead` / `respondToWrite` to `requestStarted` / `requestCompleted` |
| `bluey/test/gatt_server/lifecycle_server_test.dart` | Add tests 1–5 (LifecycleServer unit tests) |
| `bluey/test/bluey_server_test.dart` | Add tests 6–11 (BlueyServer integration tests, including platform-throw injection) |
| `docs/backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md` | Mark `status: fixed`, add `fixed_in`, replace stale "Notes" prose |
| `docs/backlog/README.md` | Move I079 from open to fixed; remove from "suggested order of attack" |

---

## Task 1: Set up branch and write the first failing test

**Rationale:** Before any code change, confirm the bug is expressible as a failing test. Test 1 directly encodes I079: a tracked client with a pending request must not be declared gone, even after the heartbeat interval elapses.

**Files:**
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Create the feature branch**

```bash
git checkout main
git pull --ff-only
git checkout -b fix/i079-server-pending-request-tolerance
```

Expected: on the new branch, working tree clean.

- [ ] **Step 2: Add the failing test at the bottom of the `LifecycleServer` group**

Locate the closing brace of the `group('LifecycleServer', () { ... })` block in `bluey/test/gatt_server/lifecycle_server_test.dart` (currently around line 500). Insert just *before* that closing `});`:

```dart
    test('pending request suppresses heartbeat timeout', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 10),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        // Track the client via a heartbeat write.
        server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );

        // App-level request begins. Server is now holding it.
        server.requestStarted(_clientId, 42);

        // Advance well past the 10s heartbeat-timeout window.
        async.elapse(const Duration(seconds: 30));

        // Server must NOT declare the client gone — we're holding its request.
        expect(gone, isEmpty);

        server.dispose();
      });
    });
```

- [ ] **Step 3: Run the test to confirm it fails (compile error, method not found)**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart 2>&1 | tail -20
```

Expected: compile error / analyzer failure on `server.requestStarted(_clientId, 42)` — "The method 'requestStarted' isn't defined for the type 'LifecycleServer'".

- [ ] **Step 4: Commit the failing test**

```bash
git add bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "test(lifecycle): I079 red — pending request must suppress heartbeat timeout"
```

---

## Task 2: Refactor `LifecycleServer` state to `_ClientLiveness`

**Rationale:** The current `Map<String, Timer> _heartbeatTimers` overloads key membership as the "tracked client" signal. Once we add a paused-timer state, that overload breaks. Migrate to `Map<String, _ClientLiveness>` first as a pure refactor — all existing tests must still pass, and the failing test from Task 1 stays failing.

**Files:**
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart`

- [ ] **Step 1: Replace `_heartbeatTimers` with `_clients` and add `_ClientLiveness`**

Open `bluey/lib/src/gatt_server/lifecycle_server.dart`. Replace lines 21–22 (the `_controlServiceAdded` and `_heartbeatTimers` field declarations) with:

```dart
  bool _controlServiceAdded = false;
  final Map<String, _ClientLiveness> _clients = {};
```

Add the private value class at the very bottom of the file, after the closing `}` of the `LifecycleServer` class:

```dart
/// Per-client liveness state: a (possibly paused) heartbeat-timeout timer
/// and the set of platform request IDs currently pending a server response.
///
/// While [pendingRequests] is non-empty, [timer] is null (paused) — the
/// client is demonstrably engaged with the server and must not be declared
/// gone. Map-key membership in `_clients` is the unambiguous "tracked"
/// signal.
class _ClientLiveness {
  Timer? timer;
  final Set<int> pendingRequests = {};
}
```

- [ ] **Step 2: Migrate `_resetTimer` to operate on `_clients`**

Replace the existing `_resetTimer` (currently lines 139–148) with:

```dart
  void _resetTimer(String clientId) {
    final interval = _interval;
    if (interval == null) return;

    final state = _clients.putIfAbsent(clientId, _ClientLiveness.new);
    state.timer?.cancel();

    if (state.pendingRequests.isNotEmpty) {
      // Paused while pending — see _ClientLiveness doc.
      state.timer = null;
      return;
    }

    state.timer = Timer(interval, () {
      _clients.remove(clientId);
      onClientGone(clientId);
    });
  }
```

- [ ] **Step 3: Migrate `cancelTimer`**

Replace the existing `cancelTimer` (currently lines 109–112) with:

```dart
  /// Cancels the heartbeat timer for a specific client and clears any
  /// pending-request state. Removes the client entirely from tracking.
  void cancelTimer(String clientId) {
    _clients.remove(clientId)?.timer?.cancel();
  }
```

- [ ] **Step 4: Migrate `recordActivity`**

Replace the existing `recordActivity` (currently lines 125–129) with:

```dart
  /// Treats any incoming activity from [clientId] as liveness evidence,
  /// refreshing an existing per-client timer so a busy lifecycle client
  /// isn't disconnected while its user-service traffic keeps flowing.
  ///
  /// Only clients that have previously identified themselves via a
  /// heartbeat write are tracked — activity from a non-lifecycle
  /// central (e.g. a generic BLE app reading a hosted service) is
  /// ignored so we don't spuriously fire [onClientGone] for a client
  /// we never promised to track.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void recordActivity(String clientId) {
    if (_interval == null) return;
    if (!_clients.containsKey(clientId)) return;
    _resetTimer(clientId);
  }
```

- [ ] **Step 5: Migrate `dispose`**

Replace the existing `dispose` (currently lines 132–137) with:

```dart
  /// Cancels all heartbeat timers and clears all per-client state.
  void dispose() {
    for (final state in _clients.values) {
      state.timer?.cancel();
    }
    _clients.clear();
  }
```

- [ ] **Step 6: Run all tests in the bluey package — old tests must still pass, Task 1's test still fails**

```bash
cd bluey && flutter test 2>&1 | tail -10
```

Expected: pre-existing tests pass. The failing test from Task 1 still fails (compile error on `requestStarted`).

- [ ] **Step 7: Commit the refactor**

```bash
git add bluey/lib/src/gatt_server/lifecycle_server.dart
git commit -m "refactor(lifecycle): migrate LifecycleServer state to _ClientLiveness"
```

---

## Task 3: Implement `requestStarted` and `requestCompleted`

**Rationale:** Drives Task 1's test green. Adds the public API and wires it into the existing `_resetTimer` flow.

**Files:**
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart`

- [ ] **Step 1: Add `requestStarted` and `requestCompleted` after `recordActivity`**

In `bluey/lib/src/gatt_server/lifecycle_server.dart`, immediately after the closing `}` of `recordActivity` (just added in Task 2), insert:

```dart
  /// Marks that the server has accepted a request from [clientId] and
  /// owes a response. Adds [requestId] to the client's pending-request
  /// set and pauses the client's heartbeat-timeout timer until all
  /// pending requests for the client have completed.
  ///
  /// No-op for untracked clients (no prior heartbeat). Lifecycle policy
  /// is opt-in: a generic BLE central reading a hosted service must not
  /// be implicitly tracked as a Bluey peer.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void requestStarted(String clientId, int requestId) {
    if (_interval == null) return;
    final state = _clients[clientId];
    if (state == null) return;
    state.pendingRequests.add(requestId);
    _resetTimer(clientId);
  }

  /// Marks a previously-started request as complete. If the client has
  /// no further pending requests, restarts the heartbeat-timeout timer
  /// with a fresh interval (treated as activity).
  ///
  /// Idempotent: completing an unknown id is a no-op.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void requestCompleted(String clientId, int requestId) {
    if (_interval == null) return;
    final state = _clients[clientId];
    if (state == null) return;
    if (!state.pendingRequests.remove(requestId)) return;
    if (state.pendingRequests.isEmpty) {
      _resetTimer(clientId);
    }
  }
```

- [ ] **Step 2: Run Task 1's test — it should now pass**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart --name "pending request suppresses heartbeat timeout" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Run the whole bluey package — all tests pass**

```bash
cd bluey && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 4: Commit the green**

```bash
git add bluey/lib/src/gatt_server/lifecycle_server.dart
git commit -m "feat(lifecycle): add requestStarted/requestCompleted to LifecycleServer (I079)"
```

---

## Task 4: Test 2 — `requestCompleted` restarts the heartbeat-timeout window

**Rationale:** Verifies the second half of the contract: after the server responds, silence resumes meaning, and `onClientGone` fires after one fresh interval of no activity.

**Files:**
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Add the test, immediately after the test added in Task 1**

```dart
    test('requestCompleted restarts the heartbeat-timeout window', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 10),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );
        server.requestStarted(_clientId, 42);

        // Hold for 30s — still alive (suppressed).
        async.elapse(const Duration(seconds: 30));
        expect(gone, isEmpty);

        // Response sent — pending drains.
        server.requestCompleted(_clientId, 42);

        // Within the fresh interval: still alive.
        async.elapse(const Duration(seconds: 9));
        expect(gone, isEmpty);

        // Past the interval since completion: gone fires.
        async.elapse(const Duration(seconds: 2));
        expect(gone, [_clientId]);

        server.dispose();
      });
    });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart --name "requestCompleted restarts" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "test(lifecycle): requestCompleted restarts heartbeat-timeout window (I079)"
```

---

## Task 5: Test 3 — concurrent requests are tracked individually

**Rationale:** Locks the set semantics. The timer must remain paused until the *last* pending request completes.

**Files:**
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Add the test**

```dart
    test('timer stays suppressed while ANY request is pending', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 10),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );

        server.requestStarted(_clientId, 1);
        server.requestStarted(_clientId, 2);

        // Complete one — the other is still open.
        server.requestCompleted(_clientId, 1);

        async.elapse(const Duration(seconds: 30));
        expect(gone, isEmpty, reason: 'request 2 still pending');

        // Complete the other — set is now empty, timer re-arms.
        server.requestCompleted(_clientId, 2);

        async.elapse(const Duration(seconds: 11));
        expect(gone, [_clientId]);

        server.dispose();
      });
    });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart --name "timer stays suppressed" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "test(lifecycle): concurrent pending requests tracked individually (I079)"
```

---

## Task 6: Test 4 — disconnect (`cancelTimer`) clears pending state

**Rationale:** Pending requests must not leak across disconnect/reconnect. After `cancelTimer`, a late `requestCompleted` for the old request must not resurrect the timer.

**Files:**
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Add the test**

```dart
    test('cancelTimer clears pending requests for the client', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 10),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );
        server.requestStarted(_clientId, 1);

        // Simulate platform-level disconnect cleanup.
        server.cancelTimer(_clientId);

        // Late respond from the app — must be a no-op.
        server.requestCompleted(_clientId, 1);

        async.elapse(const Duration(seconds: 30));
        expect(gone, isEmpty,
            reason: 'cancelTimer cleared the entry; '
                'requestCompleted must not re-arm the timer');

        server.dispose();
      });
    });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart --name "cancelTimer clears pending" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "test(lifecycle): cancelTimer clears pending-request state (I079)"
```

---

## Task 7: Test 5 — `requestStarted` is ignored for an untracked client

**Rationale:** Mirrors the existing `recordActivity` untracked-client guard. A non-Bluey BLE central reading a hosted service must not be implicitly tracked.

**Files:**
- Modify: `bluey/test/gatt_server/lifecycle_server_test.dart`

- [ ] **Step 1: Add the test**

```dart
    test('requestStarted is ignored for an untracked client', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 10),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        // No prior heartbeat — client is untracked. requestStarted must
        // not implicitly track them.
        server.requestStarted('stranger', 1);

        async.elapse(const Duration(seconds: 30));
        expect(gone, isEmpty);

        server.dispose();
      });
    });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/gatt_server/lifecycle_server_test.dart --name "requestStarted is ignored for an untracked" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/gatt_server/lifecycle_server_test.dart
git commit -m "test(lifecycle): requestStarted ignores untracked clients (I079)"
```

---

## Task 8: Wire `BlueyServer` arrival paths to `requestStarted`

**Rationale:** Connects the new `LifecycleServer` API to the actual request flow. Reads always need a response, so they always pend. Writes pend only when `responseNeeded == true`; write-without-response continues through `recordActivity`.

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`

- [ ] **Step 1: Update the read-request listener**

In `bluey/lib/src/gatt_server/bluey_server.dart`, replace the body of the `_platformReadRequestsSub` listener (currently lines 106–111) with:

```dart
    _platformReadRequestsSub = _platform.readRequests.listen((req) {
      if (!_lifecycle.handleReadRequest(req)) {
        // Reads always need a response — pend until the app responds.
        _lifecycle.requestStarted(req.centralId, req.requestId);
        _filteredReadRequestsController.add(req);
      }
    });
```

- [ ] **Step 2: Update the write-request listener**

Replace the body of `_platformWriteRequestsSub` (currently lines 113–118) with:

```dart
    _platformWriteRequestsSub = _platform.writeRequests.listen((req) {
      if (!_lifecycle.handleWriteRequest(req)) {
        if (req.responseNeeded) {
          // Write-with-response — pend until the app responds.
          _lifecycle.requestStarted(req.centralId, req.requestId);
        } else {
          // Write-without-response — no obligation to pend; treat as
          // activity (current behaviour).
          _lifecycle.recordActivity(req.centralId);
        }
        _filteredWriteRequestsController.add(req);
      }
    });
```

- [ ] **Step 3: Run all bluey tests — existing tests must still pass**

```bash
cd bluey && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!` (the new wiring isn't tested yet, but doesn't break existing behaviour because untracked clients are still no-op'd, and the response paths haven't been wired yet — pending will leak in tests that exercise this, but no existing test exercises it.)

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/gatt_server/bluey_server.dart
git commit -m "feat(lifecycle): wire BlueyServer arrival paths to requestStarted (I079)"
```

---

## Task 9: Wire `BlueyServer` response paths to `requestCompleted` (drain *before* platform call)

**Rationale:** The lifecycle obligation is discharged the moment the app calls `respondTo*`. Calling `requestCompleted` before the platform call ensures the pending set is drained even if the platform throws.

**Files:**
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`

- [ ] **Step 1: Update `respondToRead`**

Replace the existing `respondToRead` (currently lines 299–310) with:

```dart
  @override
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  }) async {
    final clientId = (request.client as BlueyClient)._platformId;
    // Drain pending state BEFORE the platform call so the obligation is
    // discharged even if respondToReadRequest throws (stale request id,
    // platform error, etc.).
    _lifecycle.requestCompleted(clientId, request.internalRequestId);
    await _platform.respondToReadRequest(
      request.internalRequestId,
      _mapGattResponseStatusToPlatform(status),
      value,
    );
  }
```

- [ ] **Step 2: Update `respondToWrite`**

Replace the existing `respondToWrite` (currently lines 312–321) with:

```dart
  @override
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  }) async {
    final clientId = (request.client as BlueyClient)._platformId;
    // Drain pending state BEFORE the platform call — see respondToRead.
    _lifecycle.requestCompleted(clientId, request.internalRequestId);
    await _platform.respondToWriteRequest(
      request.internalRequestId,
      _mapGattResponseStatusToPlatform(status),
    );
  }
```

- [ ] **Step 3: Run all bluey tests**

```bash
cd bluey && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add bluey/lib/src/gatt_server/bluey_server.dart
git commit -m "feat(lifecycle): drain pending in BlueyServer.respondTo* before platform call (I079)"
```

---

## Task 10: Test 6 — `BlueyServer` end-to-end stall scenario (write-with-response)

**Rationale:** Reproduces the I079 user-facing scenario at the `BlueyServer` level. A 30 s app-side delay must not cause `onClientGone`; after the response, the timer re-arms normally.

**Files:**
- Modify: `bluey/test/bluey_server_test.dart`

- [ ] **Step 1: Locate the test setup**

Open `bluey/test/bluey_server_test.dart`. Find the existing `'respondToWrite sends response through platform'` test (around line 851) — its setup pattern is the model for this test. Note that `BlueyServer`'s constructor takes `lifecycleInterval`; tests that don't care pass `null`. We need a non-null value here.

- [ ] **Step 2: Add the test in an appropriate group**

Find the closing `});` of the group containing `respondToWrite sends response through platform` and add this test inside the same group (just before that closing `});`):

```dart
      test('I079 — does not declare client gone while holding a pending '
          'write-with-response', () {
        fakeAsync((async) {
          final mockPlatform = MockBlueyPlatform();
          platform.BlueyPlatform.instance = mockPlatform;
          final server = BlueyServer(
            mockPlatform,
            BlueyEventBus(),
            lifecycleInterval: const Duration(seconds: 10),
          );
          addTearDown(() async {
            await server.dispose();
            mockPlatform.dispose();
          });

          final gone = <String>[];
          server.disconnections.listen(gone.add);

          // 1. Track the client by simulating a heartbeat write arrival.
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'client-A',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            responseNeeded: false,
            offset: 0,
          ));
          async.flushMicrotasks();

          // 2. Simulate an app-level write-with-response arriving.
          WriteRequest? captured;
          server.writeRequests.listen((r) => captured = r);
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 99,
            centralId: 'client-A',
            characteristicUuid: '12345678-1234-1234-1234-123456789abc',
            value: Uint8List.fromList([0xAB]),
            responseNeeded: true,
            offset: 0,
          ));
          async.flushMicrotasks();
          expect(captured, isNotNull);

          // 3. App takes 30s to respond. Heartbeat-timeout would normally
          //    fire at 10s — verify it does NOT.
          async.elapse(const Duration(seconds: 30));
          expect(gone, isEmpty,
              reason: 'I079: server must tolerate its own pending response');

          // 4. App finally responds.
          await server.respondToWrite(captured!,
              status: GattResponseStatus.success);
          async.flushMicrotasks();

          // 5. After response, the heartbeat clock restarts. 11s later,
          //    no further activity, client times out normally.
          async.elapse(const Duration(seconds: 11));
          expect(gone, ['client-A']);
        });
      });
```

- [ ] **Step 3: Run, expect pass**

```bash
cd bluey && flutter test test/bluey_server_test.dart --name "I079" 2>&1 | tail -10
```

Expected: `+1: All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add bluey/test/bluey_server_test.dart
git commit -m "test(server): I079 end-to-end — pending write-with-response suppresses timeout"
```

---

## Task 11: Test 7 — `BlueyServer` arrival wiring (read)

**Rationale:** Reads always need a response, so they always enter the pending set. Verifies the read path mirrors the write-with-response path.

**Files:**
- Modify: `bluey/test/bluey_server_test.dart`

- [ ] **Step 1: Add the test in the same group as Task 10**

```dart
      test('I079 — read request enters pending set, drains on respondToRead',
          () {
        fakeAsync((async) {
          final mockPlatform = MockBlueyPlatform();
          platform.BlueyPlatform.instance = mockPlatform;
          final server = BlueyServer(
            mockPlatform,
            BlueyEventBus(),
            lifecycleInterval: const Duration(seconds: 10),
          );
          addTearDown(() async {
            await server.dispose();
            mockPlatform.dispose();
          });

          final gone = <String>[];
          server.disconnections.listen(gone.add);

          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'client-A',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            responseNeeded: false,
            offset: 0,
          ));
          async.flushMicrotasks();

          ReadRequest? captured;
          server.readRequests.listen((r) => captured = r);
          mockPlatform.emitReadRequest(platform.PlatformReadRequest(
            requestId: 77,
            centralId: 'client-A',
            characteristicUuid: '12345678-1234-1234-1234-123456789abc',
            offset: 0,
          ));
          async.flushMicrotasks();
          expect(captured, isNotNull);

          // Server holds the read for 30s — must not declare gone.
          async.elapse(const Duration(seconds: 30));
          expect(gone, isEmpty);

          await server.respondToRead(captured!,
              status: GattResponseStatus.success,
              value: Uint8List.fromList([0xCD]));
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 11));
          expect(gone, ['client-A']);
        });
      });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/bluey_server_test.dart --name "read request enters pending" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/bluey_server_test.dart
git commit -m "test(server): I079 — pending read request also suppresses timeout"
```

---

## Task 12: Test 8 — `BlueyServer` write-without-response uses `recordActivity` (no pend)

**Rationale:** Confirms the conditional in Task 8 step 2: writes with `responseNeeded == false` extend the timer (existing behavior) but do not enter the pending set.

**Files:**
- Modify: `bluey/test/bluey_server_test.dart`

- [ ] **Step 1: Add the test in the same group**

```dart
      test('I079 — write-without-response uses recordActivity (no pend)', () {
        fakeAsync((async) {
          final mockPlatform = MockBlueyPlatform();
          platform.BlueyPlatform.instance = mockPlatform;
          final server = BlueyServer(
            mockPlatform,
            BlueyEventBus(),
            lifecycleInterval: const Duration(seconds: 10),
          );
          addTearDown(() async {
            await server.dispose();
            mockPlatform.dispose();
          });

          final gone = <String>[];
          server.disconnections.listen(gone.add);

          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'client-A',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            responseNeeded: false,
            offset: 0,
          ));
          async.flushMicrotasks();

          // 9s later, write-without-response arrives — extends timer.
          async.elapse(const Duration(seconds: 9));
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 50,
            centralId: 'client-A',
            characteristicUuid: '12345678-1234-1234-1234-123456789abc',
            value: Uint8List.fromList([0xEE]),
            responseNeeded: false,
            offset: 0,
          ));
          async.flushMicrotasks();

          // 9s after the write — total 18s since heartbeat, but only 9s
          // since the write-without-response refreshed the timer.
          async.elapse(const Duration(seconds: 9));
          expect(gone, isEmpty, reason: 'recordActivity should reset timer');

          // 2s more — past the window from the last activity.
          async.elapse(const Duration(seconds: 2));
          expect(gone, ['client-A']);
        });
      });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/bluey_server_test.dart --name "write-without-response uses recordActivity" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/bluey_server_test.dart
git commit -m "test(server): I079 — write-without-response stays on recordActivity path"
```

---

## Task 13: Test 9 — disconnect mid-pending leaves no leaked state

**Rationale:** Verifies the spec's "disconnect mid-request" caveat: a disconnect during a pending request clears state cleanly, and a late `respondToWrite` from the app is a no-op.

**Files:**
- Modify: `bluey/test/bluey_server_test.dart`

- [ ] **Step 1: Add the test in the same group**

```dart
      test('I079 — disconnect mid-pending request leaves no leaked state', () {
        fakeAsync((async) {
          final mockPlatform = MockBlueyPlatform();
          platform.BlueyPlatform.instance = mockPlatform;
          final server = BlueyServer(
            mockPlatform,
            BlueyEventBus(),
            lifecycleInterval: const Duration(seconds: 10),
          );
          addTearDown(() async {
            await server.dispose();
            mockPlatform.dispose();
          });

          final gone = <String>[];
          server.disconnections.listen(gone.add);

          // Track + arrive a pending write-with-response.
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'client-A',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            responseNeeded: false,
            offset: 0,
          ));
          WriteRequest? captured;
          server.writeRequests.listen((r) => captured = r);
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 99,
            centralId: 'client-A',
            characteristicUuid: '12345678-1234-1234-1234-123456789abc',
            value: Uint8List.fromList([0xAB]),
            responseNeeded: true,
            offset: 0,
          ));
          async.flushMicrotasks();
          expect(captured, isNotNull);

          // Platform disconnect mid-request.
          mockPlatform.emitCentralDisconnected('client-A');
          async.flushMicrotasks();
          expect(gone, ['client-A']);

          // Late respond from the app — must be a no-op (no throw, no
          // double-fire of disconnections).
          await server.respondToWrite(captured!,
              status: GattResponseStatus.success);
          async.flushMicrotasks();

          // Re-track the same client. Heartbeat-timer must run on its
          // own fresh entry, with no phantom pending state.
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 200,
            centralId: 'client-A',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            responseNeeded: false,
            offset: 0,
          ));
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 11));
          expect(gone, ['client-A', 'client-A'],
              reason: 'second timeout fires on the new entry');
        });
      });
```

- [ ] **Step 2: Run, expect pass**

```bash
cd bluey && flutter test test/bluey_server_test.dart --name "disconnect mid-pending" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add bluey/test/bluey_server_test.dart
git commit -m "test(server): I079 — disconnect mid-pending leaves no leaked state"
```

---

## Task 14: Test 10 — `requestCompleted` fires even if platform respond throws

**Rationale:** Verifies the spec's "drain pending before platform call" ordering. If the platform `respondToWriteRequest` throws, the pending set must already be drained.

**Files:**
- Modify: `bluey/test/bluey_server_test.dart`

- [ ] **Step 1: Add a throw-injection field to `MockBlueyPlatform`**

In `bluey/test/bluey_server_test.dart`, locate the `MockBlueyPlatform` class declaration (around line 14) and add a public field after the existing `respondToWriteCalls` field (around line 28):

```dart
  // I079: when set, the next respondToWriteRequest call throws this error
  // before recording the call. Used to verify that requestCompleted has
  // already drained pending state before the platform call.
  Object? throwOnRespondToWriteRequest;
```

Then locate the existing `respondToWriteRequest` override (around line 305) and replace its body so the injected error fires before any state mutation:

```dart
  @override
  Future<void> respondToWriteRequest(
    int requestId,
    platform.PlatformGattStatus status,
  ) async {
    final err = throwOnRespondToWriteRequest;
    if (err != null) {
      throwOnRespondToWriteRequest = null;
      throw err;
    }
    respondToWriteCalls.add(
      RespondToWriteCall(requestId: requestId, status: status),
    );
  }
```

- [ ] **Step 2: Add the test**

In the same group as Task 10's test, add:

```dart
      test('I079 — requestCompleted fires even if platform respond throws',
          () {
        fakeAsync((async) {
          final mockPlatform = MockBlueyPlatform();
          platform.BlueyPlatform.instance = mockPlatform;
          final server = BlueyServer(
            mockPlatform,
            BlueyEventBus(),
            lifecycleInterval: const Duration(seconds: 10),
          );
          addTearDown(() async {
            await server.dispose();
            mockPlatform.dispose();
          });

          final gone = <String>[];
          server.disconnections.listen(gone.add);

          // Track + arrive a pending write-with-response.
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'client-A',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            responseNeeded: false,
            offset: 0,
          ));
          WriteRequest? captured;
          server.writeRequests.listen((r) => captured = r);
          mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
            requestId: 99,
            centralId: 'client-A',
            characteristicUuid: '12345678-1234-1234-1234-123456789abc',
            value: Uint8List.fromList([0xAB]),
            responseNeeded: true,
            offset: 0,
          ));
          async.flushMicrotasks();
          expect(captured, isNotNull);

          // Configure the platform to throw on respondToWriteRequest.
          mockPlatform.throwOnRespondToWriteRequest =
              StateError('platform respond failed');

          // App responds — platform call throws, but pending must already
          // be drained.
          Object? thrown;
          unawaited(server
              .respondToWrite(captured!, status: GattResponseStatus.success)
              .catchError((Object e) {
            thrown = e;
          }));
          async.flushMicrotasks();
          expect(thrown, isA<StateError>());

          // If pending was drained correctly, the heartbeat clock has
          // restarted. After the interval elapses, gone fires.
          async.elapse(const Duration(seconds: 11));
          expect(gone, ['client-A'],
              reason:
                  'pending must drain before platform call; otherwise '
                  'the timer would stay paused forever');
        });
      });
```

If `unawaited` is not yet imported in this file, add `import 'dart:async';` to the imports if missing (it likely is already imported — check the top of the file).

- [ ] **Step 3: Run, expect pass**

```bash
cd bluey && flutter test test/bluey_server_test.dart --name "requestCompleted fires even if platform respond throws" 2>&1 | tail -5
```

Expected: `+1: All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add bluey/test/bluey_server_test.dart
git commit -m "test(server): I079 — pending drains even when platform respond throws"
```

---

## Task 15: Run the full bluey test suite and analyze

**Rationale:** Catch any regressions across the package before touching backlog docs.

- [ ] **Step 1: Run all bluey tests**

```bash
cd bluey && flutter test 2>&1 | tail -10
```

Expected: `All tests passed!` with the count up by ten new tests (5 LifecycleServer + 5 BlueyServer).

- [ ] **Step 2: Run the analyzer**

```bash
flutter analyze 2>&1 | tail -10
```

Expected: `No issues found!` (or at minimum, no new warnings introduced by the changes).

- [ ] **Step 3: If any test failed or analyzer warned — STOP and diagnose**

Do not proceed to backlog updates until the suite is fully green. Common issues:

- Forgot `addTearDown` — leaves a stream subscription leak across tests.
- `async.flushMicrotasks()` missing after a stream-emit — the listener hasn't run yet when assertions fire.
- `BlueyClient._platformId` is private — the cast `request.client as BlueyClient` is in the same library so `_platformId` is accessible. If you see a privacy error, you may have copied the cast into a test file by mistake.

---

## Task 16: Update the I079 backlog entry

**Rationale:** Per spec's "Backlog hygiene" section: replace the stale "Notes" prose, mark fixed.

**Files:**
- Modify: `docs/backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md`

- [ ] **Step 1: Get the SHA of the most recent fix commit so far (used for `fixed_in`)**

```bash
git log --oneline -1 --format=%H
```

Record this SHA. (After the squash-merge to main lands, you'll come back and update `fixed_in` to the squash SHA — the spec calls this out under "Backlog hygiene".)

- [ ] **Step 2: Update the frontmatter**

Replace the frontmatter block at the top of `docs/backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md`:

```yaml
---
id: I079
title: LifecycleServer declares clients gone while holding their pending requests
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-25
fixed_in: <pre-squash sha from step 1>
related: [I012, I077]
---
```

- [ ] **Step 3: Replace the "Notes" section**

Replace the entire `## Notes` section (currently lines 38–55) with:

```markdown
## Notes

Fixed in `<pre-squash sha>` by introducing pending-request tolerance in
`LifecycleServer`. The previous prose recommending a client-side fix
(routing successful user-op completions into `LivenessMonitor.recordActivity`)
described work that was already in tree (`bluey/lib/src/connection/bluey_connection.dart:317`,
`:364`, `:376`, `:619`) and did not address this scenario — during the 12 s
stall the user op has not yet *succeeded* on the client, so there is no
completion event to feed.

The actual fix, per
[the design doc](../superpowers/specs/2026-04-25-i079-lifecycle-server-pending-request-tolerance-design.md):

- `LifecycleServer` now tracks a per-client set of pending platform request
  IDs. While the set is non-empty, the heartbeat-timeout timer is paused.
  When the last pending request completes, the timer re-arms with a fresh
  interval.
- `BlueyServer` calls `requestStarted` on read / write-with-response arrival
  and `requestCompleted` *before* the platform `respondTo*` call (so the
  pending set drains even if the platform throws).
- iOS-server detection regression accepted: a client that drops its link
  while the iOS server is holding a pending request is detected only after
  the app responds + one full interval. Narrow corner; routine false-positive
  bug fixed.
```

- [ ] **Step 4: Commit**

```bash
git add docs/backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md
git commit -m "chore(backlog): mark I079 fixed; rewrite stale client-side notes"
```

---

## Task 17: Update the backlog README index

**Files:**
- Modify: `docs/backlog/README.md`

- [ ] **Step 1: Remove I079 from the "suggested order of attack"**

In `docs/backlog/README.md`, find the numbered list under `## Suggested order of attack`. Delete the entire entry that begins with `1. **I079**` (the multi-line bullet that is currently first in the list). Renumber the remaining entries so they start at `1.` again. The list goes from 5 items to 4.

- [ ] **Step 2: Move I079 from Open → Fixed in the index tables**

Find the `### Open — domain layer` table. Delete the row for I079 (`| [I079](I079-lifecycle-heartbeat-starves-behind-long-user-ops.md) | Heartbeat probe starves behind long user ops, causing spurious server-initiated disconnects | high |`).

Find the `### Fixed — verified in HEAD` table. Add a new row at the appropriate location (entries are roughly chronological; adding it after the I078 row is fine):

```markdown
| [I079](I079-lifecycle-heartbeat-starves-behind-long-user-ops.md) | LifecycleServer declares clients gone while holding their pending requests | `<pre-squash sha>` |
```

Use the same SHA recorded in Task 16 step 1.

- [ ] **Step 3: Verify the README still parses sanely**

```bash
head -130 docs/backlog/README.md | tail -50
```

Expected: the "Suggested order of attack" section reads cleanly, no orphan I079 references.

- [ ] **Step 4: Commit**

```bash
git add docs/backlog/README.md
git commit -m "chore(backlog): move I079 to fixed; drop from attack plan"
```

---

## Task 18: Final verification

- [ ] **Step 1: Re-run the full bluey test suite one more time**

```bash
cd bluey && flutter test 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 2: Re-run the analyzer**

```bash
flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 3: Inspect the commit log for the branch**

```bash
git log --oneline main..HEAD
```

Expected: roughly 13–15 commits, mix of `test(...)`, `feat(...)`, `refactor(...)`, `chore(backlog):`. No `fixup!` or `WIP` commits.

- [ ] **Step 4: Hand off to the user**

Report:
- Branch name (`fix/i079-server-pending-request-tolerance`)
- Number of commits added
- Test count delta (e.g., "added 10 tests")
- Pre-squash SHA used for the backlog entry's `fixed_in` (the user may need to update this after the squash-merge lands on `main`, matching the pattern in commit `36dc806`).

Do not push the branch unless explicitly asked. Per user preference (memory): user handles git pushes themselves.

---

## Self-review

**Spec coverage check:**

- Domain model — `_ClientLiveness` value class: Task 2.
- API surface — `requestStarted` / `requestCompleted`: Task 3.
- BlueyServer wiring — arrival paths: Task 8. Response paths drain-before-platform: Task 9.
- Disconnect clears pending: Task 6 (LifecycleServer level), Task 13 (BlueyServer level).
- Untracked-client guard: Task 7.
- Concurrent requests: Task 5.
- iOS-server detection-gap caveat: documented in spec; no test (cannot reproduce in unit tests since iOS lack-of-disconnect-callback is platform-specific behavior).
- Backlog hygiene: Task 16 (entry), Task 17 (README).
- I087 follow-up: deferred to a separate session per spec — not in this plan's scope.

**Placeholder scan:** `<pre-squash sha>` appears intentionally in Tasks 16 and 17 as a placeholder the executor fills in from `git log --oneline -1`. No `TBD` / `TODO` / "fill in details" / "similar to Task N" patterns elsewhere.

**Type / signature consistency:**

- `requestStarted(String clientId, int requestId)` and `requestCompleted(String clientId, int requestId)` — used identically in spec, plan, and tests.
- `_ClientLiveness` field names `timer` and `pendingRequests` — used consistently across Tasks 2, 3, and the existing `_resetTimer` rewrite.
- `(request.client as BlueyClient)._platformId` cast — used identically in `respondToRead` (Task 9 step 1) and `respondToWrite` (Task 9 step 2).
- Mock test injection field name `throwOnRespondToWriteRequest` — used identically in Task 14 step 1 (declaration + override) and step 2 (test usage).
