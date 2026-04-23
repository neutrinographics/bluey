import XCTest
@testable import bluey_ios

final class PeripheralManagerErrorTests: XCTestCase {

  /// Server-side notFound must map to gatt-status-failed(0x0A), NOT
  /// gatt-disconnected. Mapping it to gatt-disconnected would mean a
  /// server programming error (e.g. responding to a request for an
  /// unregistered characteristic) looks like a peer disappearance on
  /// the Dart side, which confuses the caller and could (if any code
  /// path ever fed such an error into a client-side heartbeat write)
  /// trip LifecycleClient's dead-peer counter.
  func testNotFound_onServerSide_doesNotMapToDisconnected() {
    let pe = BlueyError.notFound.toServerPigeonError()
    XCTAssertNotEqual(pe.code, "gatt-disconnected",
                      "Server-side notFound must not look like a disconnect")
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0A)
  }

  func testNotConnected_onServerSide_doesNotMapToDisconnected() {
    let pe = BlueyError.notConnected.toServerPigeonError()
    XCTAssertNotEqual(pe.code, "gatt-disconnected")
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0A)
  }
}
