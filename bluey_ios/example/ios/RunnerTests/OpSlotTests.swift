import XCTest
@testable import bluey_ios

/// Deterministic timer factory for tests. Call `advance(by:)` to fire
/// any timers whose deadline has passed.
final class FakeTimerFactory: TimerFactory {
    private struct Scheduled {
        let handle: Handle
        let fireAt: TimeInterval
        let work: () -> Void
    }

    final class Handle: TimerHandle {
        var cancelled: Bool = false
        func cancel() { cancelled = true }
    }

    private var now: TimeInterval = 0
    private var scheduled: [Scheduled] = []

    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> TimerHandle {
        let handle = Handle()
        scheduled.append(Scheduled(handle: handle, fireAt: now + seconds, work: work))
        return handle
    }

    func advance(by seconds: TimeInterval) {
        now += seconds
        let due = scheduled.filter { !$0.handle.cancelled && $0.fireAt <= now }
        scheduled.removeAll(where: { $0.fireAt <= now || $0.handle.cancelled })
        for s in due {
            s.work()
        }
    }
}

struct TestError: Error, Equatable {
    let tag: String
}

final class OpSlotTests: XCTestCase {

    // MARK: - enqueue

    func test_enqueue_intoEmptySlot_armsHeadTimer() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var result: Result<Int, Error>?

        slot.enqueue(
            completion: { result = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "timeout")
        )

        // Timer armed: advancing past deadline fires the timeout.
        timers.advance(by: 1.1)
        guard case .failure = result else {
            XCTFail("expected timeout failure")
            return
        }
    }

    func test_enqueue_intoNonEmptySlot_doesNotArmSecondTimer() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?
        var r2: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "t1")
        )
        slot.enqueue(
            completion: { r2 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "t2")
        )

        // Advance past the timeout. Only the head's timer fires.
        timers.advance(by: 1.1)
        XCTAssertNotNil(r1)
        // r2 now becomes head; its timer arms on advance. Advance
        // again to confirm r2's timer is live (not already fired).
        XCTAssertNil(r2)
        timers.advance(by: 1.1)
        XCTAssertNotNil(r2)
    }

    // MARK: - completeHead

    func test_completeHead_popsFIFO_inOrder() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var results: [Int] = []

        slot.enqueue(
            completion: { if case .success(let v) = $0 { results.append(v) } },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )
        slot.enqueue(
            completion: { if case .success(let v) = $0 { results.append(v) } },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )
        slot.enqueue(
            completion: { if case .success(let v) = $0 { results.append(v) } },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )

        slot.completeHead(.success(1))
        slot.completeHead(.success(2))
        slot.completeHead(.success(3))

        XCTAssertEqual(results, [1, 2, 3])
    }

    func test_completeHead_armsNextHeadTimer() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?
        var r2: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "t1")
        )
        slot.enqueue(
            completion: { r2 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "t2")
        )

        // Resolve head before its timer fires.
        slot.completeHead(.success(42))
        XCTAssertEqual(try? r1?.get(), 42)
        XCTAssertNil(r2)

        // Advance: r2's timer should now fire.
        timers.advance(by: 1.1)
        XCTAssertNotNil(r2)
    }

    func test_completeHead_cancelsHeadTimer_noSpuriousFire() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var fireCount = 0
        var result: Result<Int, Error>?

        slot.enqueue(
            completion: { r in
                fireCount += 1
                result = r
            },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "should-not-fire")
        )

        // Resolve before timeout.
        slot.completeHead(.success(7))
        XCTAssertEqual(fireCount, 1)
        XCTAssertEqual(try? result?.get(), 7)

        // Advance past the original deadline. Timer should have been
        // cancelled — completion must not fire a second time.
        timers.advance(by: 2.0)
        XCTAssertEqual(fireCount, 1, "completion fired again after timer should have been cancelled")
    }

    func test_completeHead_onEmptySlot_isNoOp() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        slot.completeHead(.success(1)) // must not crash
        XCTAssertTrue(slot.isEmpty)
    }

    // MARK: - timeout

    func test_timeout_firesHeadCompletion_andAdvancesQueue() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?
        var r2: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "timed-out-1")
        )
        slot.enqueue(
            completion: { r2 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "timed-out-2")
        )

        timers.advance(by: 1.1)

        // r1 timed out.
        if case .failure(let err) = r1 {
            XCTAssertEqual((err as? TestError)?.tag, "timed-out-1")
        } else {
            XCTFail("r1 should have timed out")
        }
        // r2 now head, not yet timed out.
        XCTAssertNil(r2)
    }

    func test_timeout_thenLateCallback_isDroppedNotMisrouted() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?
        var r2: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "timed-out")
        )
        slot.enqueue(
            completion: { r2 = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "not-fired")
        )

        // Timeout r1.
        timers.advance(by: 1.1)
        // r1 received the timeout failure.
        guard case .failure = r1 else {
            XCTFail("r1 should have timed out")
            return
        }
        // r2 is now head but not yet resolved.
        XCTAssertNil(r2)

        // Late CoreBluetooth callback arrives for r1. This represents
        // CB's late delivery of the r1 ack after our internal timer
        // fired. The slot must DROP this — r2 must remain pending.
        slot.completeHead(.success(99))
        XCTAssertNil(r2, "late callback for timed-out op must not be routed to next op")

        // Subsequent legitimate completion for r2 resolves normally.
        slot.completeHead(.success(42))
        XCTAssertEqual(try? r2?.get(), 42)
    }

    // MARK: - drainAll

    func test_drainAll_firesAllPendingWithError() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?
        var r2: Result<Int, Error>?
        var r3: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )
        slot.enqueue(
            completion: { r2 = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )
        slot.enqueue(
            completion: { r3 = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )

        slot.drainAll(TestError(tag: "drained"))

        for (idx, r) in [r1, r2, r3].enumerated() {
            guard case .failure(let err) = r else {
                XCTFail("entry \(idx) should have failed")
                continue
            }
            XCTAssertEqual((err as? TestError)?.tag, "drained")
        }
        XCTAssertTrue(slot.isEmpty)
    }

    func test_drainAll_cancelsAllTimers() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "should-not-fire")
        )

        slot.drainAll(TestError(tag: "drained"))
        // Advance past original timer deadline; it must have been
        // cancelled.
        timers.advance(by: 2.0)

        // r1 should have fired exactly once with the drain error.
        guard case .failure(let err) = r1 else {
            XCTFail("r1 should have failed")
            return
        }
        XCTAssertEqual((err as? TestError)?.tag, "drained")
    }

    func test_drainAll_onEmptySlot_isNoOp() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        slot.drainAll(TestError(tag: "t")) // must not crash
        XCTAssertTrue(slot.isEmpty)
    }

    func test_pendingDrops_consumedBeforeFreshOpIsResolved() {
        // Scenario: op A times out (pendingDrops=1). Then op B is
        // enqueued. Then a late CB callback arrives for A (represented
        // as completeHead). pendingDrops must be consumed first so B
        // is NOT resolved by A's late result. The subsequent CB for B
        // then resolves B normally.
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var rA: Result<Int, Error>?
        var rB: Result<Int, Error>?

        slot.enqueue(
            completion: { rA = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "A-timed-out")
        )
        timers.advance(by: 1.1) // A times out, pendingDrops = 1
        guard case .failure = rA else {
            XCTFail("A should have timed out")
            return
        }

        slot.enqueue(
            completion: { rB = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "B-should-not-fire")
        )

        // Late CB for A arrives: must be dropped, NOT route to B.
        slot.completeHead(.success(999))
        XCTAssertNil(rB, "pendingDrop must be consumed before fresh op is resolved")

        // Genuine CB for B now resolves normally.
        slot.completeHead(.success(42))
        XCTAssertEqual(try? rB?.get(), 42)
    }

    func test_pendingDrops_accumulateAcrossMultipleTimeouts() {
        // Scenario: three ops timeout back-to-back, leaving
        // pendingDrops = 3. The next three completeHead calls are all
        // dropped; the fourth (for a fresh op) resolves.
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)

        for i in 1...3 {
            slot.enqueue(
                completion: { _ in },
                timeoutSeconds: 1,
                makeTimeoutError: TestError(tag: "t\(i)")
            )
        }
        // Advance enough for all three to time out in sequence.
        // Each timeout arms the next head's timer (still 1s from its
        // own head-start), so we advance in 1.1s slices.
        timers.advance(by: 1.1) // head t1 times out, t2 head, timer armed
        timers.advance(by: 1.1) // t2 times out, t3 head
        timers.advance(by: 1.1) // t3 times out
        XCTAssertTrue(slot.isEmpty)

        // Three late CB deliveries: each must be dropped.
        var fresh: Result<Int, Error>?
        slot.enqueue(
            completion: { fresh = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "should-not-fire")
        )
        slot.completeHead(.success(101)) // drops pendingDrop #1
        slot.completeHead(.success(102)) // drops pendingDrop #2
        slot.completeHead(.success(103)) // drops pendingDrop #3
        XCTAssertNil(fresh, "fresh op must not be resolved while pendingDrops > 0")

        // Next legitimate CB resolves the fresh op.
        slot.completeHead(.success(200))
        XCTAssertEqual(try? fresh?.get(), 200)
    }

    func test_drainAll_resetsPendingDrops() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var r1: Result<Int, Error>?
        var r2: Result<Int, Error>?

        slot.enqueue(
            completion: { r1 = $0 },
            timeoutSeconds: 1,
            makeTimeoutError: TestError(tag: "t1")
        )
        // Trigger timeout → pendingDrops = 1.
        timers.advance(by: 1.1)
        guard case .failure = r1 else {
            XCTFail("r1 should have timed out")
            return
        }

        // drainAll must reset pendingDrops.
        slot.drainAll(TestError(tag: "drained"))

        // After drain, a fresh op should resolve normally — not be
        // dropped by stale pendingDrops.
        slot.enqueue(
            completion: { r2 = $0 },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "should-not-fire")
        )
        slot.completeHead(.success(100))
        XCTAssertEqual(try? r2?.get(), 100, "pendingDrops leaked across drainAll")
    }

    // MARK: - reentrancy

    func test_reentrantEnqueue_duringCompletion_preservesOrder() {
        let timers = FakeTimerFactory()
        let slot = OpSlot<Int>(timerFactory: timers)
        var log: [String] = []

        // When r1 resolves, it enqueues r3.
        slot.enqueue(
            completion: { result in
                if case .success(let v) = result {
                    log.append("r1=\(v)")
                    slot.enqueue(
                        completion: { inner in
                            if case .success(let iv) = inner {
                                log.append("r3=\(iv)")
                            }
                        },
                        timeoutSeconds: 10,
                        makeTimeoutError: TestError(tag: "t")
                    )
                }
            },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )
        slot.enqueue(
            completion: { result in
                if case .success(let v) = result {
                    log.append("r2=\(v)")
                }
            },
            timeoutSeconds: 10,
            makeTimeoutError: TestError(tag: "t")
        )

        slot.completeHead(.success(1))  // fires r1, enqueues r3 (now [r2, r3])
        slot.completeHead(.success(2))  // fires r2 (now [r3])
        slot.completeHead(.success(3))  // fires r3

        XCTAssertEqual(log, ["r1=1", "r2=2", "r3=3"])
    }
}
