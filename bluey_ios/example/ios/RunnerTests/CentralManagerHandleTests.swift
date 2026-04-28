import XCTest
import CoreBluetooth
@testable import bluey_ios

/// I088 Task D.5 — handle-table population/clearing in
/// `CentralHandleStore` (used by `CentralManagerImpl`).
///
/// CoreBluetooth types (`CBCharacteristic`, `CBDescriptor`,
/// `CBPeripheral`) cannot be instantiated by client code, so the
/// store is generic on its value types and these tests exercise it
/// with `NSObject` stand-ins. The wiring of the store into
/// `CentralManagerImpl` callbacks is exercised separately at
/// integration level — what matters here is the contract: handles
/// are minted from a per-device monotonic counter starting at 1,
/// shared between characteristics and descriptors in encounter
/// order, and cleared on disconnect / didModifyServices.
final class CentralManagerHandleTests: XCTestCase {

    // MARK: - test_populates_handle_maps_at_didDiscoverCharacteristicsFor

    /// Fire two characteristic-records for one device. Handles must
    /// be {1, 2}; the device's characteristic map contains both, in
    /// the order encountered.
    func test_populates_handle_maps_at_didDiscoverCharacteristicsFor() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceId = "AA:BB:CC:DD:EE:01"
        let charA = NSObject()
        let charB = NSObject()

        let h1 = store.recordCharacteristic(charA, for: deviceId)
        let h2 = store.recordCharacteristic(charB, for: deviceId)

        XCTAssertEqual(h1, 1)
        XCTAssertEqual(h2, 2)
        XCTAssertEqual(Set(store.characteristicByHandle[deviceId]?.keys ?? [:].keys), [1, 2])
        XCTAssertTrue(store.characteristicByHandle[deviceId]?[1] === charA)
        XCTAssertTrue(store.characteristicByHandle[deviceId]?[2] === charB)
    }

    // MARK: - test_populates_descriptor_handles_at_didDiscoverDescriptorsFor

    /// After two characteristics get handles 1 and 2, descriptors
    /// minted for the same device must continue from 3 — chars and
    /// descs share the same per-device mint pool, in encounter order.
    func test_populates_descriptor_handles_at_didDiscoverDescriptorsFor() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceId = "AA:BB:CC:DD:EE:01"
        let char1 = NSObject()
        let char2 = NSObject()
        let desc1 = NSObject()
        let desc2 = NSObject()

        _ = store.recordCharacteristic(char1, for: deviceId)
        _ = store.recordCharacteristic(char2, for: deviceId)
        let dh1 = store.recordDescriptor(desc1, for: deviceId)
        let dh2 = store.recordDescriptor(desc2, for: deviceId)

        XCTAssertEqual(dh1, 3, "descriptor minting must continue from where chars left off")
        XCTAssertEqual(dh2, 4)
        XCTAssertEqual(Set(store.descriptorByHandle[deviceId]?.keys ?? [:].keys), [3, 4])
        XCTAssertTrue(store.descriptorByHandle[deviceId]?[3] === desc1)
        XCTAssertTrue(store.descriptorByHandle[deviceId]?[4] === desc2)
    }

    /// Per-device counters must be independent — minting on device B
    /// must not see device A's counter.
    func test_perDevice_counters_are_independent() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceA = "AA:BB:CC:DD:EE:01"
        let deviceB = "AA:BB:CC:DD:EE:02"

        let a1 = store.recordCharacteristic(NSObject(), for: deviceA)
        let a2 = store.recordCharacteristic(NSObject(), for: deviceA)
        let b1 = store.recordCharacteristic(NSObject(), for: deviceB)

        XCTAssertEqual(a1, 1)
        XCTAssertEqual(a2, 2)
        XCTAssertEqual(b1, 1, "device B's counter must start at 1, not at 3")
    }

    // MARK: - test_clears_handle_maps_on_didDisconnectPeripheral

    /// On disconnect, all three maps for that device must be wiped
    /// AND the counter reset so that a subsequent reconnect-and-
    /// rediscover starts back at 1. Other devices' state must not
    /// be touched.
    func test_clears_handle_maps_on_didDisconnectPeripheral() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceA = "AA:BB:CC:DD:EE:01"
        let deviceB = "AA:BB:CC:DD:EE:02"

        _ = store.recordCharacteristic(NSObject(), for: deviceA)
        _ = store.recordDescriptor(NSObject(), for: deviceA)
        _ = store.recordCharacteristic(NSObject(), for: deviceB)

        store.clear(for: deviceA)

        XCTAssertNil(store.characteristicByHandle[deviceA])
        XCTAssertNil(store.descriptorByHandle[deviceA])
        // device B untouched
        XCTAssertEqual(store.characteristicByHandle[deviceB]?.count, 1)

        // Counter for device A reset — re-record returns 1.
        let h = store.recordCharacteristic(NSObject(), for: deviceA)
        XCTAssertEqual(h, 1, "counter for cleared device must reset to 1")
    }

    // MARK: - test_clears_handle_maps_on_didModifyServices

    /// `didModifyServices` clears in exactly the same way as
    /// `didDisconnectPeripheral` — same `clear(for:)` API. The
    /// distinction is at the call site, not in the store.
    func test_clears_handle_maps_on_didModifyServices() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceId = "AA:BB:CC:DD:EE:01"

        _ = store.recordCharacteristic(NSObject(), for: deviceId)
        _ = store.recordCharacteristic(NSObject(), for: deviceId)
        _ = store.recordDescriptor(NSObject(), for: deviceId)

        // Simulating didModifyServices: same clear API, same effect.
        store.clear(for: deviceId)

        XCTAssertNil(store.characteristicByHandle[deviceId])
        XCTAssertNil(store.descriptorByHandle[deviceId])

        // Subsequent re-discovery starts a fresh handle pool.
        let h = store.recordCharacteristic(NSObject(), for: deviceId)
        XCTAssertEqual(h, 1)
    }

    // MARK: - lookup

    /// Reverse lookup by reference identity — used by the DTO
    /// mapping path to find a descriptor's minted handle from the
    /// CB object reference.
    func test_handleForDescriptor_returnsMintedHandle() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceId = "AA:BB:CC:DD:EE:01"
        _ = store.recordCharacteristic(NSObject(), for: deviceId)
        let desc = NSObject()
        let mintedH = store.recordDescriptor(desc, for: deviceId)

        XCTAssertEqual(store.handleForDescriptor(desc, deviceId: deviceId), mintedH)
        XCTAssertNil(store.handleForDescriptor(NSObject(), deviceId: deviceId))
    }

    func test_handleForCharacteristic_returnsMintedHandle() {
        let store = CentralHandleStore<NSObject, NSObject>()
        let deviceId = "AA:BB:CC:DD:EE:01"
        let charA = NSObject()
        let charB = NSObject()
        let h1 = store.recordCharacteristic(charA, for: deviceId)
        let h2 = store.recordCharacteristic(charB, for: deviceId)

        XCTAssertEqual(store.handleForCharacteristic(charA, deviceId: deviceId), h1)
        XCTAssertEqual(store.handleForCharacteristic(charB, deviceId: deviceId), h2)
        XCTAssertNil(store.handleForCharacteristic(NSObject(), deviceId: deviceId))
    }
}
