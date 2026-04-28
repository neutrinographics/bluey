import Foundation
import CoreBluetooth

/// I088 — module-wide handle table for the Peripheral (server) role.
///
/// Unlike `CentralHandleStore` (per-device counters), the server has
/// only one local instance, so handles are minted from a single
/// monotonic counter starting at 1. Every `addService` call mints
/// fresh handles for that service's `CBMutableCharacteristic`s and
/// they continue from where the previous call left off.
///
/// `removeService` clears only the entries for that service's
/// characteristics — other services' handles must remain intact.
/// The counter does NOT reset on `removeService`; once a handle has
/// been issued, that integer is never reused for the lifetime of the
/// store, so observers caching old handles see a clean
/// "not found" rather than aliasing onto an unrelated characteristic.
///
/// Reverse lookup (`handleForCharacteristic`) is by reference
/// identity — `CBMutableCharacteristic` instances are kept alive by
/// the manager and CB returns the same reference across all
/// callbacks for a given attribute, so identity is reliable.
///
/// A full clear on `peripheralManagerDidUpdateState(.poweredOff)` is
/// its own future fix — see backlog item I083 — and is intentionally
/// NOT done here.
///
/// Generic on its value type so unit tests can exercise the storage
/// contract with `NSObject` stand-ins.
internal final class PeripheralHandleStore<C: AnyObject> {

    /// Module-wide characteristic table, keyed by minted handle.
    internal var characteristicByHandle: [Int: C] = [:]

    /// Module-wide next-handle counter. Starts at 1 (0 is reserved
    /// for "invalid handle" on the wire — see spec).
    private var nextHandle: Int = 1

    /// Mints the next handle and stores `characteristic` under it.
    /// Returns the minted handle.
    @discardableResult
    internal func recordCharacteristic(_ characteristic: C) -> Int {
        let h = nextHandle
        nextHandle += 1
        characteristicByHandle[h] = characteristic
        return h
    }

    /// Reverse lookup: returns the minted handle previously assigned
    /// to `characteristic`, or nil if not found. Compares by
    /// reference identity.
    internal func handleForCharacteristic(_ characteristic: C) -> Int? {
        for (h, c) in characteristicByHandle where c === characteristic {
            return h
        }
        return nil
    }

    /// Drops the entries for the given characteristics from the
    /// table. Other characteristics' entries are not touched. The
    /// counter does NOT reset.
    internal func removeCharacteristics(_ characteristics: [C]) {
        for c in characteristics {
            if let h = handleForCharacteristic(c) {
                characteristicByHandle.removeValue(forKey: h)
            }
        }
    }
}
