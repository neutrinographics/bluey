import Foundation

/// I040 — FIFO queue of notifications deferred by iOS's TX backpressure.
///
/// `CBPeripheralManager.updateValue(_:for:onSubscribedCentrals:)` returns
/// `false` when the OS-level transmit queue is full. Pre-I040 the iOS
/// plugin surfaced that as `BlueyError.unknown` to Dart, dropping the
/// notification entirely. The retry hook
/// (`peripheralManagerIsReady(toUpdateSubscribers:)`) was a no-op so
/// nothing recovered.
///
/// Post-I040 the plugin enqueues a deferred entry instead. When iOS
/// signals capacity, `drain(send:)` walks the queue in arrival order
/// and re-attempts each entry; the first re-attempt that returns
/// `false` halts draining and waits for the next ready callback.
///
/// Result reporting is per-entry: each entry carries the original
/// Pigeon completion handler. `.success(())` fires when a re-attempt
/// actually delivers; `.failure(error)` fires when the entry is
/// failed-out by `failAll` (e.g. `closeServer`) or
/// `failEntries(matching:)` (e.g. `removeService` tearing down the
/// targeted characteristic). The Dart-side caller's `Future<void>`
/// resolves only when delivery is confirmed or definitively abandoned
/// — preserving the I099 / I311 contract that success means delivery.
///
/// Cap: a hard upper bound on queued entries. Reaching it indicates
/// runaway backpressure (caller outpacing iOS far beyond what
/// `isReadyToUpdateSubscribers` can drain in normal operation). When
/// at cap, `enqueue` returns `false` and the caller is expected to
/// fire its own `.failure` completion. Guards memory growth without
/// silently dropping data.
///
/// Generic on its value types so unit tests can exercise the storage
/// contract with `NSObject` stand-ins (CB types are not publicly
/// constructible enough for clean unit tests).
internal final class PendingNotificationQueue<C: AnyObject, Central: AnyObject> {

    struct Entry {
        let characteristic: C
        let data: Data
        let central: Central?
        let completion: (Result<Void, Error>) -> Void
    }

    private var entries: [Entry] = []
    private let cap: Int

    /// Default cap (1024) accommodates burst stress workloads; iOS's
    /// drain rate is sub-millisecond per entry when subscribers are
    /// reading, so the steady-state depth stays small. At 1024 entries
    /// the memory footprint is ~1–2 MB even with 512-byte payloads.
    internal init(cap: Int = 1024) {
        self.cap = cap
    }

    internal var count: Int { entries.count }
    internal var isEmpty: Bool { entries.isEmpty }

    /// Enqueue [entry] in arrival order. Returns `true` if accepted,
    /// `false` if the queue is at its cap. At-cap callers must fire
    /// their own `.failure` completion — `enqueue` does not invoke
    /// the entry's completion in either branch.
    @discardableResult
    internal func enqueue(_ entry: Entry) -> Bool {
        guard entries.count < cap else { return false }
        entries.append(entry)
        return true
    }

    /// Walk the queue in FIFO order. For each entry, calls `send(entry)`
    /// once. If `send` returns `true` (the OS accepted the notification),
    /// pop the entry and fire its completion `.success(())`. If `false`
    /// (queue still backpressured), leave the entry in place and stop
    /// draining — iOS will fire `isReadyToUpdateSubscribers` again when
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

    /// Fail every queued entry with `error` and clear the queue.
    /// Used by `closeServer` to release every pending caller's Future.
    internal func failAll(error: Error) {
        let snapshot = entries
        entries.removeAll()
        for entry in snapshot {
            entry.completion(.failure(error))
        }
    }

    /// Fail entries for which `predicate` returns `true`, leaving the
    /// rest in place. Used by `removeService` to release queued
    /// notifications targeting characteristics being torn down without
    /// affecting unrelated entries.
    internal func failEntries(matching predicate: (Entry) -> Bool, error: Error) {
        var failed: [Entry] = []
        var remaining: [Entry] = []
        for entry in entries {
            if predicate(entry) {
                failed.append(entry)
            } else {
                remaining.append(entry)
            }
        }
        entries = remaining
        for entry in failed {
            entry.completion(.failure(error))
        }
    }
}
