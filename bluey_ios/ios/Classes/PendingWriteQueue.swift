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
