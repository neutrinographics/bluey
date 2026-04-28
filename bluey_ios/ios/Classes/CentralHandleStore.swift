import Foundation
import CoreBluetooth

/// I088 — per-device handle tables for the Central role.
///
/// CoreBluetooth has no public equivalent of Android's
/// `BluetoothGattCharacteristic.getInstanceId()`. Instead, every
/// attribute discovered via `peripheral(_, didDiscoverCharacteristicsFor:)`
/// or `peripheral(_, didDiscoverDescriptorsFor:)` is assigned a
/// minted `Int` from a per-device monotonic counter starting at 1.
/// Characteristics and descriptors share the same counter pool per
/// device — handles are unique within the device's discovered
/// attribute set, in encounter order.
///
/// CB returns the same object reference for a given attribute
/// across all callbacks for a peripheral, so reverse lookup uses
/// reference identity (`===`).
///
/// Cleared on:
///  - `centralManager(_, didDisconnectPeripheral:)` — link is gone,
///    attribute database goes with it.
///  - `peripheral(_, didModifyServices:)` — Service Changed; the
///    old layout is invalidated, re-discovery follows.
///
/// Generic on its value types so unit tests can exercise the
/// storage contract with `NSObject` stand-ins (CB types are not
/// publicly constructible).
internal final class CentralHandleStore<C: AnyObject, D: AnyObject> {

    /// Per-device characteristic table, keyed by minted handle.
    internal var characteristicByHandle: [String: [Int: C]] = [:]

    /// Per-device descriptor table, keyed by minted handle.
    internal var descriptorByHandle: [String: [Int: D]] = [:]

    /// Per-device next-handle counter. Starts at 1 (0 is reserved
    /// for "invalid handle" on the wire — see spec).
    private var nextHandle: [String: Int] = [:]

    /// Mints the next handle for `deviceId`.
    /// First call returns 1, subsequent calls return 2, 3, …
    internal func mintHandle(for deviceId: String) -> Int {
        let h = (nextHandle[deviceId] ?? 0) + 1
        nextHandle[deviceId] = h
        return h
    }

    /// Mints a handle and stores `characteristic` under it.
    /// Returns the minted handle.
    @discardableResult
    internal func recordCharacteristic(_ characteristic: C, for deviceId: String) -> Int {
        let h = mintHandle(for: deviceId)
        characteristicByHandle[deviceId, default: [:]][h] = characteristic
        return h
    }

    /// Mints a handle and stores `descriptor` under it.
    /// Returns the minted handle.
    @discardableResult
    internal func recordDescriptor(_ descriptor: D, for deviceId: String) -> Int {
        let h = mintHandle(for: deviceId)
        descriptorByHandle[deviceId, default: [:]][h] = descriptor
        return h
    }

    /// Reverse lookup: returns the minted handle previously
    /// assigned to `characteristic` for this device, or nil if not
    /// found. Compares by reference identity.
    internal func handleForCharacteristic(_ characteristic: C, deviceId: String) -> Int? {
        guard let map = characteristicByHandle[deviceId] else { return nil }
        for (h, c) in map where c === characteristic {
            return h
        }
        return nil
    }

    /// Reverse lookup: returns the minted handle previously
    /// assigned to `descriptor` for this device, or nil if not
    /// found. Compares by reference identity.
    internal func handleForDescriptor(_ descriptor: D, deviceId: String) -> Int? {
        guard let map = descriptorByHandle[deviceId] else { return nil }
        for (h, d) in map where d === descriptor {
            return h
        }
        return nil
    }

    /// Drops all per-device state — characteristic table, descriptor
    /// table, and the mint counter — for `deviceId`. After clear,
    /// the next `recordCharacteristic` / `recordDescriptor` /
    /// `mintHandle` for this device returns 1 again.
    /// Other devices' state is not affected.
    internal func clear(for deviceId: String) {
        characteristicByHandle.removeValue(forKey: deviceId)
        descriptorByHandle.removeValue(forKey: deviceId)
        nextHandle.removeValue(forKey: deviceId)
    }
}
