# iOS write-without-response flow control (I339) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop iOS central-role `writeValue(.withoutResponse)` from silently dropping/coalescing writes under burst by pacing them against CoreBluetooth's `canSendWriteWithoutResponse` gate.

**Architecture:** A standalone, unit-tested `PendingWriteQueue` (a deliberate interface twin of the existing `PendingNotificationQueue`, I040) holds deferred WriteNoResponse payloads. `CentralManagerImpl` drains it while the gate is open, re-pumps from the `peripheralIsReady(toSendWriteWithoutResponse:)` delegate, and fails the queue on disconnect via the existing `clearPendingCompletions` path. Completion is on hand-off to CoreBluetooth (not on enqueue), giving a serial consumer automatic back-pressure.

**Tech Stack:** Swift / CoreBluetooth (`bluey_ios` native), XCTest (`bluey_ios/example/ios/RunnerTests`).

**Spec:** `docs/superpowers/specs/2026-06-02-ios-write-without-response-flow-control-design.md`

> **Execution note — iOS test runs.** The XCTest red→green requires `xcodebuild test` against a simulator plus the example iOS build (CocoaPods + `flutter assemble`). If that toolchain isn't runnable in the execution sandbox, write test + implementation with careful review and confirm green on a Mac/CI (`cd bluey_ios/example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16'`). `PendingWriteQueue.swift` under `Classes/` is auto-included by the pod (glob); the **test file must be added to the `RunnerTests` target** (in Xcode: add to the RunnerTests group with the target checked; or add to its Sources build phase in `Runner.xcodeproj/project.pbxproj`) or `xcodebuild` won't compile it.

---

## Pre-step: branch

- [ ] Create the feature branch off `main`:

```bash
cd /Users/joel/git/neutrinographics/bluey
git checkout main && git checkout -b i339-ios-write-flow-control
```

---

## File Structure

- **Create** `bluey_ios/ios/Classes/PendingWriteQueue.swift` — the standalone FIFO/drain/`failAll` type. One responsibility: hold deferred WnR writes and drain them through an injected `send` closure. Generic over the characteristic type for testability. Auto-included by the pod.
- **Create** `bluey_ios/example/ios/RunnerTests/PendingWriteQueueTests.swift` — XCTest unit suite for the queue's contract. Mirrors `PendingNotificationQueueTests.swift`.
- **Modify** `bluey_ios/ios/Classes/CentralManagerImpl.swift` — hold one queue per `deviceId`; rewrite the `.withoutResponse` write branch to enqueue+pump; add `pumpWriteNoResponse`; add the forwarded `peripheralIsReadyToSendWriteWithoutResponse`; fail the queue in `clearPendingCompletions`.
- **Modify** `bluey_ios/ios/Classes/PeripheralDelegate.swift` — forward the raw `peripheralIsReady(toSendWriteWithoutResponse:)` delegate callback to the manager.
- **Modify (doc comment only)** `bluey_ios/ios/Classes/PendingNotificationQueue.swift` and `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt` — cross-reference the three flow-control queues.

---

## Task 1: `PendingWriteQueue` type + unit tests (TDD)

**Files:**
- Create: `bluey_ios/ios/Classes/PendingWriteQueue.swift`
- Create: `bluey_ios/example/ios/RunnerTests/PendingWriteQueueTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `bluey_ios/example/ios/RunnerTests/PendingWriteQueueTests.swift`:

```swift
import XCTest
@testable import bluey_ios

/// I339 — Tests for the FIFO queue that paces central-role
/// WriteNoResponse writes against iOS's `canSendWriteWithoutResponse`
/// gate. Contract (twin of `PendingNotificationQueue`):
///
///   * `enqueue` accepts entries up to a cap; returns `false` at cap.
///   * `drain` walks the queue, popping entries whose `send` closure
///     returns `true` (handed to CoreBluetooth) and stopping at the
///     first `false` (gate shut).
///   * `failAll` fires `.failure` on each released entry.
final class PendingWriteQueueTests: XCTestCase {

    private typealias TestQueue = PendingWriteQueue<NSObject>
    private typealias TestEntry = TestQueue.Entry

    private func makeEntry(
        characteristic: NSObject = NSObject(),
        data: Data = Data([0x01]),
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) -> TestEntry {
        TestEntry(characteristic: characteristic, data: data, completion: completion)
    }

    private struct Boom: Error, Equatable { let tag: String }

    func test_drain_onEmptyQueue_isNoop() {
        let queue = TestQueue()
        var sendCalls = 0
        queue.drain(send: { _ in sendCalls += 1; return true })
        XCTAssertEqual(sendCalls, 0)
        XCTAssertEqual(queue.count, 0)
    }

    func test_enqueue_thenDrainSend_returnsTrue_firesSuccessAndEmpties() {
        let queue = TestQueue()
        var fired: Result<Void, Error>?
        let accepted = queue.enqueue(makeEntry(completion: { fired = $0 }))
        XCTAssertTrue(accepted)
        XCTAssertEqual(queue.count, 1)

        queue.drain(send: { _ in true })

        XCTAssertEqual(queue.count, 0)
        switch fired {
        case .success: break
        default: XCTFail("expected .success, got \(String(describing: fired))")
        }
    }

    func test_drain_sendReturnsFalse_leavesEntryAndDoesNotFireCompletion() {
        let queue = TestQueue()
        var fired = false
        queue.enqueue(makeEntry(completion: { _ in fired = true }))
        queue.enqueue(makeEntry())

        var sendCalls = 0
        queue.drain(send: { _ in sendCalls += 1; return false })

        XCTAssertEqual(sendCalls, 1, "drain must stop at first false")
        XCTAssertEqual(queue.count, 2, "both entries remain queued")
        XCTAssertFalse(fired, "completion must not fire when send returns false")
    }

    func test_drain_partialSuccess_thenFalse_stopsAndPreservesTail() {
        let queue = TestQueue()
        var fired: [Int] = []
        for i in 0..<4 { queue.enqueue(makeEntry(completion: { _ in fired.append(i) })) }

        var attempts = 0
        queue.drain(send: { _ in attempts += 1; return attempts <= 2 })

        XCTAssertEqual(attempts, 3, "send called for entries 0,1,2; 3rd returns false and halts")
        XCTAssertEqual(queue.count, 2, "entries 2 and 3 remain")
        XCTAssertEqual(fired, [0, 1], "only successful pops fire .success")
    }

    func test_reDrain_afterPartialDrain_resumesFromHead() {
        let queue = TestQueue()
        var fired: [Int] = []
        for i in 0..<3 { queue.enqueue(makeEntry(completion: { _ in fired.append(i) })) }

        var gateOpen = false
        queue.drain(send: { _ in gateOpen }) // gate shut → nothing drains
        XCTAssertEqual(fired, [])
        XCTAssertEqual(queue.count, 3)

        gateOpen = true
        queue.drain(send: { _ in gateOpen }) // gate open → drains from head in order
        XCTAssertEqual(fired, [0, 1, 2])
        XCTAssertEqual(queue.count, 0)
    }

    func test_failAll_firesFailureForEveryEntryAndEmpties() {
        let queue = TestQueue()
        var errors: [Boom] = []
        for _ in 0..<3 {
            queue.enqueue(makeEntry(completion: { result in
                if case .failure(let e) = result, let boom = e as? Boom { errors.append(boom) }
            }))
        }

        queue.failAll(error: Boom(tag: "disconnected"))

        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(errors, Array(repeating: Boom(tag: "disconnected"), count: 3))
    }

    func test_enqueue_atCap_returnsFalse_leavesEntryOutOfQueue() {
        let queue = TestQueue(cap: 2)
        XCTAssertTrue(queue.enqueue(makeEntry()))
        XCTAssertTrue(queue.enqueue(makeEntry()))

        var fired = false
        let accepted = queue.enqueue(makeEntry(completion: { _ in fired = true }))

        XCTAssertFalse(accepted, "enqueue returns false at cap")
        XCTAssertEqual(queue.count, 2, "the rejected entry is not stored")
        XCTAssertFalse(fired, "enqueue does not fire the completion in either branch")
    }
}
```

- [ ] **Step 2: Run the tests, verify they FAIL**

Run: `cd bluey_ios/example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RunnerTests/PendingWriteQueueTests`
Expected: FAIL — `cannot find 'PendingWriteQueue' in scope` (type does not exist yet).
(If `xcodebuild` is unavailable in the sandbox, confirm by inspection that `PendingWriteQueue` is undefined and proceed; run for real on Mac/CI.)

- [ ] **Step 3: Write the type to make the tests pass**

Create `bluey_ios/ios/Classes/PendingWriteQueue.swift`:

```swift
import Foundation

/// I339 — FIFO queue of central-role WriteNoResponse payloads paced by
/// iOS's TX flow-control gate.
///
/// `CBPeripheral.writeValue(_:for:type: .withoutResponse)` has no
/// completion callback, and `CBPeripheral.canSendWriteWithoutResponse`
/// gates whether the local TX queue can accept another write. Pushing
/// past a shut gate lets CoreBluetooth silently drop or coalesce writes
/// (I339). This queue defers writes when the gate is shut and drains them
/// when it reopens (`peripheralIsReady(toSendWriteWithoutResponse:)`).
///
/// Twin of `PendingNotificationQueue` (I040 — the peripheral-notify side):
/// same drain-while-the-gate-is-open shape. Both are the iOS counterpart
/// of Android's `GattOpQueue` (`bluey_android/.../GattOpQueue.kt`), which
/// is shaped differently (serial, one-op-in-flight, advance-on-
/// `onCharacteristicWrite`, per-op timeout) because Android delivers a
/// completion callback per write whereas iOS gives only a batch gate plus
/// a single readiness callback.
///
/// Result reporting is per-entry: `.success(())` fires when a drain hands
/// the write to CoreBluetooth; `.failure(error)` fires when `failAll`
/// releases the entry (link lost / disconnect / teardown). The Dart
/// caller's `Future<void>` thus resolves only when the write reached the
/// radio or the link is gone — never on mere enqueue — which gives a
/// serial consumer automatic back-pressure.
///
/// Recovery model matches `PendingNotificationQueue`: there is no per-entry
/// timer. A stuck write is bounded by the central-role
/// `didDisconnectPeripheral` callback (a first-class CoreBluetooth signal,
/// no I201-style gap) which fires `failAll` — so a write cannot hang
/// indefinitely.
///
/// Generic over the characteristic type so unit tests can exercise the
/// storage contract with `NSObject` stand-ins (`CBCharacteristic` is not
/// cleanly constructible in tests), mirroring `PendingNotificationQueue`.
internal final class PendingWriteQueue<Char: AnyObject> {

    struct Entry {
        let characteristic: Char
        let data: Data
        let completion: (Result<Void, Error>) -> Void
    }

    private var entries: [Entry] = []
    private let cap: Int

    /// Default cap (1024) is a runaway-memory backstop, not the back-pressure
    /// mechanism (that is complete-on-hand-off + the gate). Under a serial
    /// consumer the depth stays at ~1, so the cap is effectively unreachable.
    internal init(cap: Int = 1024) {
        self.cap = cap
    }

    internal var count: Int { entries.count }
    internal var isEmpty: Bool { entries.isEmpty }

    /// Enqueue [entry] in arrival order. Returns `true` if accepted,
    /// `false` if the queue is at its cap. At-cap callers must fire their
    /// own `.failure` completion — `enqueue` does not invoke the entry's
    /// completion in either branch.
    @discardableResult
    internal func enqueue(_ entry: Entry) -> Bool {
        guard entries.count < cap else { return false }
        entries.append(entry)
        return true
    }

    /// Walk the queue in FIFO order. For each head entry, call `send(entry)`
    /// once. If it returns `true` (handed to CoreBluetooth), pop the entry
    /// and fire `.success(())`. If `false` (gate shut), leave the entry in
    /// place and stop — `peripheralIsReady(...)` drives the next drain when
    /// capacity returns.
    internal func drain(send: (Entry) -> Bool) {
        while let head = entries.first {
            if send(head) {
                entries.removeFirst()
                head.completion(.success(()))
            } else {
                return
            }
        }
    }

    /// Fail every queued entry with `error` and clear the queue. Used by the
    /// disconnect/teardown path so no caller's `Future` is orphaned.
    internal func failAll(error: Error) {
        let snapshot = entries
        entries.removeAll()
        for entry in snapshot {
            entry.completion(.failure(error))
        }
    }
}
```

- [ ] **Step 4: Run the tests, verify they PASS**

Run: `cd bluey_ios/example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RunnerTests/PendingWriteQueueTests`
Expected: PASS — 7 tests green. (If `xcodebuild` is unavailable in the sandbox, mark this to be confirmed on Mac/CI and proceed.)

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_ios/ios/Classes/PendingWriteQueue.swift bluey_ios/example/ios/RunnerTests/PendingWriteQueueTests.swift
git commit -m "feat(ios): PendingWriteQueue — WriteNoResponse flow-control FIFO + unit tests (I339)"
```

---

## Task 2: Wire `PendingWriteQueue` into `CentralManagerImpl` + `PeripheralDelegate`

This is the thin native wiring below the unit-test seam — verified by review + the Task 4 dogfood, not by an automated test (the queue logic is covered in Task 1).

**Files:**
- Modify: `bluey_ios/ios/Classes/CentralManagerImpl.swift` (write path ~320–353; `clearPendingCompletions` ~912–947; a new stored property ~line 36; a new method)
- Modify: `bluey_ios/ios/Classes/PeripheralDelegate.swift`

- [ ] **Step 1: Add the per-device queue store**

In `CentralManagerImpl.swift`, next to the `writeCharacteristicSlots` declaration (around line 36), add:

```swift
    /// I339 — per-device WriteNoResponse flow-control queue. See PendingWriteQueue.
    private var pendingWriteQueues: [String: PendingWriteQueue<CBCharacteristic>] = [:]
```

- [ ] **Step 2: Rewrite the write branch to enqueue + pump**

In `CentralManagerImpl.writeCharacteristic(...)`, replace the tail of the method — from `let type:` through the closing of the `.withoutResponse` completion (currently):

```swift
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse

        if withResponse {
            let cacheKey = characteristic.uuid.uuidString.lowercased()
            let slot = writeCharacteristicSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<Void>()
            writeCharacteristicSlots[deviceId, default: [:]][cacheKey] = slot
            slot.enqueue(
                completion: completion,
                timeoutSeconds: writeCharacteristicTimeout,
                makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Write characteristic timed out", details: nil)
            )
        }

        peripheral.writeValue(value.data, for: characteristic, type: type)

        if !withResponse {
            completion(.success(()))
        }
```

with:

```swift
        if withResponse {
            let cacheKey = characteristic.uuid.uuidString.lowercased()
            let slot = writeCharacteristicSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<Void>()
            writeCharacteristicSlots[deviceId, default: [:]][cacheKey] = slot
            slot.enqueue(
                completion: completion,
                timeoutSeconds: writeCharacteristicTimeout,
                makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Write characteristic timed out", details: nil)
            )
            peripheral.writeValue(value.data, for: characteristic, type: .withResponse)
            return
        }

        // .withoutResponse — pace against CoreBluetooth's TX gate so bursts
        // are not silently dropped/coalesced (I339). The queue fires the
        // Pigeon completion only when the write is actually handed off.
        let queue = pendingWriteQueues[deviceId] ?? PendingWriteQueue<CBCharacteristic>()
        pendingWriteQueues[deviceId] = queue
        let accepted = queue.enqueue(
            PendingWriteQueue.Entry(
                characteristic: characteristic,
                data: value.data,
                completion: completion
            )
        )
        guard accepted else {
            // Runaway back-pressure past the 1024 cap (effectively unreachable
            // under complete-on-hand-off). Surface rather than silently drop.
            completion(.failure(PigeonError(code: "gatt-busy", message: "Write-without-response queue saturated", details: nil)))
            return
        }
        pumpWriteNoResponse(deviceId: deviceId, peripheral: peripheral)
```

- [ ] **Step 3: Add the pump helper**

In `CentralManagerImpl.swift`, in the `// MARK: - Helpers` section (next to `clearPendingCompletions`, ~line 910), add:

```swift
    /// I339 — drain the device's WriteNoResponse queue while CoreBluetooth's
    /// TX gate is open. Each accepted write fires its Pigeon completion
    /// `.success`. Stops at the first shut gate; `peripheralIsReady` re-pumps.
    private func pumpWriteNoResponse(deviceId: String, peripheral: CBPeripheral) {
        guard let queue = pendingWriteQueues[deviceId] else { return }
        queue.drain(send: { entry in
            guard peripheral.canSendWriteWithoutResponse else { return false }
            peripheral.writeValue(entry.data, for: entry.characteristic, type: .withoutResponse)
            return true
        })
    }
```

- [ ] **Step 4: Add the forwarded readiness handler + fail-on-disconnect**

In `CentralManagerImpl.swift`, in the `// MARK: - CBPeripheralDelegate callbacks` section, add:

```swift
    /// I339 — CoreBluetooth's TX gate reopened; resume draining this
    /// peripheral's deferred WriteNoResponse writes.
    func peripheralIsReadyToSendWriteWithoutResponse(peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        pumpWriteNoResponse(deviceId: deviceId, peripheral: peripheral)
    }
```

Then in `clearPendingCompletions(for:error:)`, after the `writeCharacteristicSlots` drain block (the `if let slots = writeCharacteristicSlots.removeValue(...)` loop, ~line 931), add:

```swift
        // I339 — fail any deferred WriteNoResponse writes; the link is gone.
        pendingWriteQueues.removeValue(forKey: deviceId)?.failAll(error: error)
```

- [ ] **Step 5: Forward the raw delegate callback**

In `PeripheralDelegate.swift`, add (after the `didModifyServices` method, before the closing brace):

```swift
    // MARK: - Write-Without-Response Flow Control

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        manager?.peripheralIsReadyToSendWriteWithoutResponse(peripheral: peripheral)
    }
```

- [ ] **Step 6: Verify the Dart side is unaffected**

Run: `cd bluey_ios && flutter analyze && flutter test`
Expected: analyze clean; the Dart suite passes (this change is native-only; no Dart behavior changed).

- [ ] **Step 7: Build the Swift to catch compile errors (if toolchain available)**

Run: `cd bluey_ios/example/ios && xcodebuild build -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED. (If `xcodebuild` is unavailable in the sandbox, do a careful manual read of the diff and confirm on Mac/CI.)

- [ ] **Step 8: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_ios/ios/Classes/CentralManagerImpl.swift bluey_ios/ios/Classes/PeripheralDelegate.swift
git commit -m "feat(ios): pace WriteNoResponse via PendingWriteQueue + canSendWriteWithoutResponse gate (I339)"
```

---

## Task 3: Cross-reference doc comments (bridge Android ↔ iOS understanding)

**Files:**
- Modify (doc comment only): `bluey_ios/ios/Classes/PendingNotificationQueue.swift`
- Modify (doc comment only): `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt`

(`PendingWriteQueue.swift`'s own header already cross-references the other two — added in Task 1.)

- [ ] **Step 1: Cross-reference from `PendingNotificationQueue`**

In `PendingNotificationQueue.swift`, append to the end of the class doc comment (after the "Generic on its value types…" paragraph, before `internal final class`):

```swift
///
/// Sibling: `PendingWriteQueue` (I339) applies this same
/// drain-while-the-gate-is-open shape to central-role WriteNoResponse
/// writes. Android's `GattOpQueue` is the cross-platform analog, shaped
/// differently (serial, advance-on-callback) for its per-op-callback API.
```

- [ ] **Step 2: Cross-reference from `GattOpQueue.kt`**

In `GattOpQueue.kt`, append to the end of the class KDoc (after the "Thread safety:" paragraph, before `internal class GattOpQueue`):

```kotlin
 *
 * iOS analogs: `PendingWriteQueue` (central WriteNoResponse) and
 * `PendingNotificationQueue` (peripheral notify) in `bluey_ios`. They are
 * shaped differently — drain-while-`canSendWriteWithoutResponse`-is-open
 * rather than serial one-op-in-flight — because CoreBluetooth gives a
 * batch gate plus a single readiness callback instead of a completion
 * callback per write.
```

- [ ] **Step 3: Verify analyze (Dart) still clean**

Run: `cd bluey_android && flutter analyze`
Expected: No issues (Kotlin doc-comment-only change does not affect Dart analysis; this is a no-regression check).

- [ ] **Step 4: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey_ios/ios/Classes/PendingNotificationQueue.swift bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt
git commit -m "docs: cross-reference the three flow-control queues (GattOpQueue / PendingWriteQueue / PendingNotificationQueue) (I339)"
```

---

## Task 4: Full verification + dogfood handoff

- [ ] **Step 1: All Dart suites + analyze**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey && flutter test && flutter analyze
cd ../bluey_platform_interface && flutter test && flutter analyze
cd ../bluey_android && flutter test && flutter analyze
cd ../bluey_ios && flutter test && flutter analyze
```
Expected: all green, analyze clean. (No Dart behavior changed; this confirms no regression.)

- [ ] **Step 2: iOS unit tests (Mac/CI)**

```bash
cd bluey_ios/example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RunnerTests/PendingWriteQueueTests
```
Expected: 7 `PendingWriteQueueTests` green. (Also run the full `RunnerTests` suite to confirm no regression in `PendingNotificationQueueTests` / `OpSlotTests`.)

- [ ] **Step 3: Dogfood (user-driven, gating)**

Re-run the I339 corruption scenario in `gossip_chat`, iPhone (central) ↔ Pixel 6a (peripheral):
1. Induce a ≥10 s Dart isolate hang on the iOS side (the keyboard XPC reconnect via the QR-scan flow is the known trigger), so the in-app send queue accumulates ≥10 framed writes that then flush as a burst.
2. Confirm on the Android (peripheral) side: **no** `Malformed gossip message … FormatException` with a `…}]}GS` tail, and **no** `frame decoder recovered from corruption` events after the burst.
3. Confirm the iOS-central → Android-peripheral data path keeps working after the hang (messages/typing from iOS continue to land on Android — no permanent one-way degradation).
4. Confirm normal (non-burst) writes and steady-state behavior are unaffected.

Capture iOS logs (`bluey.ios.central`) for the burst window. If corruption still appears, the wiring (Task 2) needs revisiting before merge.

---

## Self-Review

**Spec coverage:**
- Native flow-control in `CentralManagerImpl` (fix A) → Tasks 1–2. ✅
- `PendingWriteQueue` as the testable twin of `PendingNotificationQueue` → Task 1. ✅
- Complete-on-hand-off semantics → Task 2 Step 2 (completion fires inside `drain`'s `send`-true branch, i.e. on hand-off; enqueue does not complete). ✅
- Edge handling: disconnect `failAll` → Task 2 Step 4; gate re-pump → Task 2 Steps 3–5; defensive cap + at-cap failure → Task 1 type + Task 2 Step 2; **no per-write timeout** → reflected by its absence. ✅
- Cross-reference doc comments → Task 3. ✅
- Verification: XCTest unit tests → Task 1; dogfood → Task 4. ✅
- Out of scope (Option B, peripheral `notifyTo`, Android logic, I050) → not touched. ✅

**Placeholder scan:** every code step contains complete code; commands have expected output; no TBD/"handle edge cases"/"similar to". ✅

**Type consistency:** `PendingWriteQueue<Char: AnyObject>`, `Entry(characteristic:data:completion:)`, `enqueue(_) -> Bool`, `drain(send:)`, `failAll(error:)`, `pumpWriteNoResponse(deviceId:peripheral:)`, `peripheralIsReadyToSendWriteWithoutResponse(peripheral:)`, `pendingWriteQueues` — used identically across the type definition (Task 1), the tests (Task 1), and the wiring (Task 2). ✅
