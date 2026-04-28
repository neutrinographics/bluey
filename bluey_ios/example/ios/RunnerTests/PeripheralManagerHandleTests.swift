import XCTest
import CoreBluetooth
@testable import bluey_ios

/// I088 Task D.6 — server-side handle minting in
/// `PeripheralHandleStore` (used by `PeripheralManagerImpl`).
///
/// The server role has only one local instance, so the counter is
/// module-wide (not per-device, unlike the central-side store). On
/// `addService`, every `CBMutableCharacteristic` in the service gets
/// a freshly minted `Int` handle, starting at 1 for the first ever
/// `addService` call and continuing across subsequent calls.
///
/// `removeService` clears only the entries for that service's
/// characteristics — other services' handles must remain intact.
///
/// `CBMutableCharacteristic` is publicly constructible, but the
/// store is generic so tests can use `NSObject` stand-ins where
/// reference identity is the only thing that matters.
final class PeripheralManagerHandleTests: XCTestCase {

    // MARK: - test_addService_mints_handles_for_each_characteristic

    /// First `addService` call: two characteristics get handles 1 and
    /// 2 in encounter order. The store maps both back to the original
    /// CBMutableCharacteristic instance by reference.
    func test_addService_mints_handles_for_each_characteristic() {
        let store = PeripheralHandleStore<NSObject>()
        let charA = NSObject()
        let charB = NSObject()

        let h1 = store.recordCharacteristic(charA)
        let h2 = store.recordCharacteristic(charB)

        XCTAssertEqual(h1, 1)
        XCTAssertEqual(h2, 2)
        XCTAssertEqual(Set(store.characteristicByHandle.keys), [1, 2])
        XCTAssertTrue(store.characteristicByHandle[1] === charA)
        XCTAssertTrue(store.characteristicByHandle[2] === charB)
    }

    // MARK: - test_addService_continues_minting_across_calls

    /// A second `addService` call (after a first that minted 1, 2)
    /// must continue from 3 — counter is module-wide.
    func test_addService_continues_minting_across_calls() {
        let store = PeripheralHandleStore<NSObject>()
        let charA = NSObject()
        let charB = NSObject()
        _ = store.recordCharacteristic(charA)
        _ = store.recordCharacteristic(charB)

        let charC = NSObject()
        let charD = NSObject()
        let h3 = store.recordCharacteristic(charC)
        let h4 = store.recordCharacteristic(charD)

        XCTAssertEqual(h3, 3, "module-wide counter must continue across addService calls")
        XCTAssertEqual(h4, 4)
        XCTAssertEqual(Set(store.characteristicByHandle.keys), [1, 2, 3, 4])
    }

    // MARK: - test_removeService_clears_handle_entries_for_that_service

    /// After two `addService` calls populate handles 1, 2 and 3, 4,
    /// removing the second service's characteristics must drop only
    /// {3, 4} from the map. {1, 2} are untouched. The counter does
    /// NOT reset — a subsequent add mints 5 (not 3 or 1).
    func test_removeService_clears_handle_entries_for_that_service() {
        let store = PeripheralHandleStore<NSObject>()
        let charA = NSObject()
        let charB = NSObject()
        let charC = NSObject()
        let charD = NSObject()
        _ = store.recordCharacteristic(charA)
        _ = store.recordCharacteristic(charB)
        _ = store.recordCharacteristic(charC)
        _ = store.recordCharacteristic(charD)

        store.removeCharacteristics([charC, charD])

        XCTAssertEqual(Set(store.characteristicByHandle.keys), [1, 2],
                       "only removed service's handles must be gone")
        XCTAssertTrue(store.characteristicByHandle[1] === charA)
        XCTAssertTrue(store.characteristicByHandle[2] === charB)

        // Counter still advances — re-adding does not recycle handles.
        let charE = NSObject()
        let h5 = store.recordCharacteristic(charE)
        XCTAssertEqual(h5, 5, "counter must NOT reset on removeService")
    }

    // MARK: - test_handleForCharacteristic_returnsMintedHandle

    /// Reverse lookup by reference identity — used at the DTO mapping
    /// path (didReceiveRead / didReceiveWrite) to surface the minted
    /// handle for a given CBMutableCharacteristic.
    func test_handleForCharacteristic_returnsMintedHandle() {
        let store = PeripheralHandleStore<NSObject>()
        let charA = NSObject()
        let charB = NSObject()
        let h1 = store.recordCharacteristic(charA)
        let h2 = store.recordCharacteristic(charB)

        XCTAssertEqual(store.handleForCharacteristic(charA), h1)
        XCTAssertEqual(store.handleForCharacteristic(charB), h2)
        XCTAssertNil(store.handleForCharacteristic(NSObject()))
    }
}
