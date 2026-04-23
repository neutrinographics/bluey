import Foundation

/// Abstracts timer scheduling so tests can fire timers deterministically.
protocol TimerFactory {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> TimerHandle
}

protocol TimerHandle: AnyObject {
    func cancel()
}

/// Production timer factory backed by `DispatchQueue.main.asyncAfter`.
///
/// Cancellation safety relies on main-queue serial ordering: a fired
/// timer block and `OpSlot.completeHead` cannot interleave. The
/// `handleTimeout` id check provides defense-in-depth if cancel
/// races with a dispatched block.
final class RealTimerFactory: TimerFactory {
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> TimerHandle {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return DispatchWorkItemHandle(item: item)
    }

    private final class DispatchWorkItemHandle: TimerHandle {
        let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}

/// FIFO of pending completions for a single (device, key) pair.
///
/// At any time, at most one timer is live — the head entry's. Non-head
/// entries are "waiting their turn" and have no timer armed. This
/// matches Android's `GattOpQueue.startNext()` semantic.
///
/// Late-callback handling: when an op times out, its entry is popped
/// (so the next op's timer can arm immediately) and `pendingDrops` is
/// incremented. A subsequent `completeHead` for the timed-out op's
/// late CoreBluetooth delivery is dropped by consuming one pendingDrop.
/// This prevents the late ack from being misrouted to the next pending
/// op. `drainAll` resets the counter so stale drops don't leak across
/// connection lifetimes.
///
/// Thread-safety: all methods must be called on the main queue. The
/// iOS adapter's Pigeon handlers run on main, and CoreBluetooth delivers
/// delegate callbacks on main (default `CBCentralManager` queue).
final class OpSlot<T> {
    private let timerFactory: TimerFactory

    /// Entries are strong-referenced until popped or drained.
    private var entries: [Entry] = []

    /// Number of upcoming `completeHead` calls to drop, one per
    /// outstanding timed-out op whose late CB callback we haven't
    /// yet seen. Reset by `drainAll`.
    private var pendingDrops: Int = 0

    private final class Entry {
        let id: UInt64
        let completion: (Result<T, Error>) -> Void
        let timeoutSeconds: TimeInterval
        let makeTimeoutError: () -> Error
        var timer: TimerHandle?

        init(
            id: UInt64,
            completion: @escaping (Result<T, Error>) -> Void,
            timeoutSeconds: TimeInterval,
            makeTimeoutError: @escaping () -> Error
        ) {
            self.id = id
            self.completion = completion
            self.timeoutSeconds = timeoutSeconds
            self.makeTimeoutError = makeTimeoutError
        }
    }

    private var nextId: UInt64 = 0

    init(timerFactory: TimerFactory = RealTimerFactory()) {
        self.timerFactory = timerFactory
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Append a completion. If the appended entry becomes head (slot was
    /// empty), its timer is armed immediately.
    func enqueue(
        completion: @escaping (Result<T, Error>) -> Void,
        timeoutSeconds: TimeInterval,
        makeTimeoutError: @autoclosure @escaping () -> Error
    ) {
        nextId += 1
        let entry = Entry(
            id: nextId,
            completion: completion,
            timeoutSeconds: timeoutSeconds,
            makeTimeoutError: makeTimeoutError
        )
        let wasEmpty = entries.isEmpty
        entries.append(entry)
        if wasEmpty {
            armHeadTimer()
        }
    }

    /// Resolve the head entry with `result`. If there are outstanding
    /// pending-drops (late callbacks from previously timed-out ops),
    /// consume one and drop this call instead of resolving. Otherwise:
    /// pop head, cancel its timer, fire its completion, arm the next
    /// head's timer.
    func completeHead(_ result: Result<T, Error>) {
        if pendingDrops > 0 {
            pendingDrops -= 1
            return
        }
        guard let head = entries.first else { return }
        head.timer?.cancel()
        entries.removeFirst()
        head.completion(result)
        armHeadTimer()
    }

    /// Cancel all timers, fire every pending completion with `error`,
    /// clear the slot. Resets `pendingDrops` so stale drop-expectations
    /// don't leak across connection lifetimes.
    func drainAll(_ error: Error) {
        let toFire = entries
        entries.removeAll()
        pendingDrops = 0
        for entry in toFire {
            entry.timer?.cancel()
        }
        for entry in toFire {
            entry.completion(.failure(error))
        }
    }

    // MARK: - Private

    private func armHeadTimer() {
        guard let head = entries.first else { return }
        guard head.timer == nil else { return } // already armed
        let entryId = head.id
        head.timer = timerFactory.schedule(after: head.timeoutSeconds) { [weak self] in
            self?.handleTimeout(entryId: entryId)
        }
    }

    private func handleTimeout(entryId: UInt64) {
        guard let head = entries.first, head.id == entryId else { return }
        head.timer = nil
        let err = head.makeTimeoutError()
        // Pop the timed-out entry and expect one late CB delivery to drop.
        entries.removeFirst()
        pendingDrops += 1
        head.completion(.failure(err))
        armHeadTimer()
    }
}
