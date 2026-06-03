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
