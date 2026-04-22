import XCTest
@testable import bluey_ios

final class BlueyErrorPigeonTests: XCTestCase {

  // MARK: - Client-side mappings

  func testNotFound_asClient_mapsToGattDisconnected() {
    let err = BlueyError.notFound.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-disconnected")
  }

  func testNotConnected_asClient_mapsToGattDisconnected() {
    let err = BlueyError.notConnected.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-disconnected")
  }

  func testUnsupported_asClient_mapsToGattStatusFailed0x06() {
    let err = BlueyError.unsupported.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x06)
  }

  func testTimeout_asClient_mapsToGattTimeout() {
    let err = BlueyError.timeout.toClientPigeonError()
    XCTAssertEqual(err.code, "gatt-timeout")
  }

  func testUnknown_asClient_mapsToBlueyUnknown() {
    let err = BlueyError.unknown.toClientPigeonError()
    XCTAssertEqual(err.code, "bluey-unknown")
  }

  // MARK: - Server-side mappings

  func testNotFound_asServer_mapsToGattStatusFailed0x0A() {
    let err = BlueyError.notFound.toServerPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x0A)
  }

  func testNotConnected_asServer_mapsToGattStatusFailed0x0A() {
    let err = BlueyError.notConnected.toServerPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x0A)
  }

  func testUnsupported_asServer_mapsToGattStatusFailed0x06() {
    let err = BlueyError.unsupported.toServerPigeonError()
    XCTAssertEqual(err.code, "gatt-status-failed")
    XCTAssertEqual(err.details as? Int, 0x06)
  }

  func testUnknown_asServer_mapsToBlueyUnknown() {
    let err = BlueyError.unknown.toServerPigeonError()
    XCTAssertEqual(err.code, "bluey-unknown")
  }
}
