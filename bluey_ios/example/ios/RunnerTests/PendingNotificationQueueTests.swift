import XCTest
@testable import bluey_ios

/// I040 — Tests for the FIFO retry queue that absorbs iOS notify-TX
/// backpressure. The queue's contract:
///
///   * `enqueue` accepts entries up to a cap; returns `false` at cap.
///   * `drain` walks the queue, popping entries whose `send` closure
///     returns `true` and stopping at the first `false`.
///   * `failAll` and `failEntries(matching:)` fire `.failure` on each
///     released entry.
///
/// All callbacks are exercised here so that the wiring in
/// `PeripheralManagerImpl` only has to provide the `send` closure.
final class PendingNotificationQueueTests: XCTestCase {

    // Convenience aliases so each test reads cleanly.
    private typealias TestQueue = PendingNotificationQueue<NSObject, NSObject>
    private typealias TestEntry = TestQueue.Entry

    private func makeEntry(
        characteristic: NSObject = NSObject(),
        central: NSObject? = nil,
        data: Data = Data([0x01]),
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) -> TestEntry {
        TestEntry(
            characteristic: characteristic,
            data: data,
            central: central,
            completion: completion
        )
    }

    private struct Boom: Error, Equatable {
        let tag: String
    }

    // MARK: - drain on empty queue

    /// drain on an empty queue must be a no-op: the send closure is
    /// never invoked and no completions fire.
    func test_drain_onEmptyQueue_isNoop() {
        let queue = TestQueue()
        var sendCalls = 0
        queue.drain(send: { _ in
            sendCalls += 1
            return true
        })
        XCTAssertEqual(sendCalls, 0)
        XCTAssertEqual(queue.count, 0)
    }

    // MARK: - enqueue + drain success

    /// enqueue followed by a draining `send` that returns true must
    /// pop the entry, fire its completion `.success`, and leave the
    /// queue empty.
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

    // MARK: - drain stops on first false

    /// When `send` returns false on the head entry, the entry must
    /// stay in the queue, the completion must NOT fire, and any
    /// entries behind it must not be sent (`send` is called once total).
    func test_drain_sendReturnsFalse_leavesEntryAndDoesNotFireCompletion() {
        let queue = TestQueue()
        var fired = false
        queue.enqueue(makeEntry(completion: { _ in fired = true }))
        queue.enqueue(makeEntry()) // second entry

        var sendCalls = 0
        queue.drain(send: { _ in
            sendCalls += 1
            return false
        })

        XCTAssertEqual(sendCalls, 1, "drain must stop at first false; second entry not attempted")
        XCTAssertEqual(queue.count, 2, "both entries remain queued")
        XCTAssertFalse(fired, "completion must not fire when send returns false")
    }

    // MARK: - drain partial then stop

    /// drain pops entries while `send` returns true; the first false
    /// halts draining. Already-popped entries' completions have fired;
    /// remaining entries' completions have not.
    func test_drain_partialSuccess_thenFalse_stopsAndPreservesTail() {
        let queue = TestQueue()
        var fired: [Int] = []
        for i in 0..<4 {
            queue.enqueue(makeEntry(completion: { _ in fired.append(i) }))
        }

        var attempts = 0
        queue.drain(send: { _ in
            attempts += 1
            return attempts <= 2 // succeed first 2, fail 3rd
        })

        XCTAssertEqual(attempts, 3, "send called for entries 0, 1, 2; 3rd returns false and halts")
        XCTAssertEqual(queue.count, 2, "entries 2 and 3 remain (entry 2 was attempted but rejected)")
        XCTAssertEqual(fired, [0, 1], "only successful pops fire .success")
    }

    // MARK: - re-drain resumes from front

    /// After a halted drain leaves the head entry in place, a second
    /// drain call must start from that same head entry.
    func test_reDrain_afterPartialDrain_resumesFromHead() {
        let queue = TestQueue()
        var fired: [Int] = []
        for i in 0..<3 {
            queue.enqueue(makeEntry(completion: { _ in fired.append(i) }))
        }

        // First drain: succeed 0, fail 1.
        var firstAttempts = 0
        queue.drain(send: { _ in
            firstAttempts += 1
            return firstAttempts <= 1
        })
        XCTAssertEqual(fired, [0])
        XCTAssertEqual(queue.count, 2)

        // Second drain: succeed both remaining.
        queue.drain(send: { _ in true })
        XCTAssertEqual(fired, [0, 1, 2], "re-drain resumed from entry 1")
        XCTAssertEqual(queue.count, 0)
    }

    // MARK: - failAll fires every completion and clears

    /// failAll must fire `.failure(error)` for every queued entry and
    /// leave the queue empty.
    func test_failAll_firesFailureForEveryEntryAndEmpties() {
        let queue = TestQueue()
        var fired: [Result<Void, Error>] = []
        for _ in 0..<3 {
            queue.enqueue(makeEntry(completion: { fired.append($0) }))
        }

        queue.failAll(error: Boom(tag: "shutdown"))

        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(fired.count, 3)
        for f in fired {
            switch f {
            case .failure(let e as Boom):
                XCTAssertEqual(e, Boom(tag: "shutdown"))
            default:
                XCTFail("expected .failure(Boom), got \(f)")
            }
        }
    }

    // MARK: - failEntries(matching:) fires only matching, leaves rest

    /// failEntries fires `.failure` for entries whose predicate
    /// matches and leaves the rest in queue order.
    func test_failEntries_matching_firesOnlyMatchedAndPreservesRemainder() {
        let queue = TestQueue()
        let charA = NSObject()
        let charB = NSObject()
        var firedFor: [String: Result<Void, Error>] = [:]

        queue.enqueue(makeEntry(characteristic: charA, completion: { firedFor["a1"] = $0 }))
        queue.enqueue(makeEntry(characteristic: charB, completion: { firedFor["b1"] = $0 }))
        queue.enqueue(makeEntry(characteristic: charA, completion: { firedFor["a2"] = $0 }))

        queue.failEntries(
            matching: { $0.characteristic === charA },
            error: Boom(tag: "removeService")
        )

        XCTAssertEqual(queue.count, 1, "only the charB entry remains")
        XCTAssertEqual(Set(firedFor.keys), ["a1", "a2"])
        XCTAssertNil(firedFor["b1"], "non-matching entry's completion must not fire")

        // The surviving entry is still drainable.
        var survivorFired: Result<Void, Error>?
        queue.drain(send: { _ in true })
        // Re-checking firedFor since the surviving entry's completion
        // is the one keyed "b1" above.
        survivorFired = firedFor["b1"]
        switch survivorFired {
        case .success: break
        default: XCTFail("surviving entry must drain to .success after failEntries")
        }
    }

    // MARK: - cap behavior

    /// At-cap enqueue returns false; the entry is NOT added; existing
    /// entries are untouched. Caller is expected to fire its own
    /// .failure (the queue does not invoke `entry.completion` here —
    /// it returns the rejection signal so the call site can craft the
    /// right error code at its own boundary).
    func test_enqueue_atCap_returnsFalse_leavesEntryOutOfQueue() {
        let queue = PendingNotificationQueue<NSObject, NSObject>(cap: 2)
        XCTAssertTrue(queue.enqueue(makeEntry()))
        XCTAssertTrue(queue.enqueue(makeEntry()))

        var rejectedCompletionFired = false
        let accepted = queue.enqueue(makeEntry(completion: { _ in
            rejectedCompletionFired = true
        }))

        XCTAssertFalse(accepted, "cap=2 with 2 entries already enqueued must reject")
        XCTAssertEqual(queue.count, 2, "queue depth must not grow past cap")
        XCTAssertFalse(rejectedCompletionFired,
                       "queue does not fire completion on cap-rejection — caller does")
    }
}
