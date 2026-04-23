import XCTest
import CoreBluetooth
@testable import bluey_ios

final class CBErrorPigeonTests: XCTestCase {

  private func makeError(code: Int) -> NSError {
    return NSError(domain: CBATTErrorDomain, code: code, userInfo: nil)
  }

  // MARK: - CBATTErrorDomain mapping

  func testInvalidHandle_mapsToStatus0x01() {
    let pe = makeError(code: CBATTError.invalidHandle.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x01)
  }

  func testReadNotPermitted_mapsToStatus0x02() {
    let pe = makeError(code: CBATTError.readNotPermitted.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x02)
  }

  func testWriteNotPermitted_mapsToStatus0x03() {
    let pe = makeError(code: CBATTError.writeNotPermitted.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x03)
  }

  func testInvalidPdu_mapsToStatus0x04() {
    let pe = makeError(code: CBATTError.invalidPdu.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x04)
  }

  func testInsufficientAuthentication_mapsToStatus0x05() {
    let pe = makeError(code: CBATTError.insufficientAuthentication.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x05)
  }

  func testRequestNotSupported_mapsToStatus0x06() {
    let pe = makeError(code: CBATTError.requestNotSupported.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x06)
  }

  func testInvalidOffset_mapsToStatus0x07() {
    let pe = makeError(code: CBATTError.invalidOffset.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x07)
  }

  func testInsufficientAuthorization_mapsToStatus0x08() {
    let pe = makeError(code: CBATTError.insufficientAuthorization.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x08)
  }

  func testAttributeNotFound_mapsToStatus0x0A() {
    let pe = makeError(code: CBATTError.attributeNotFound.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0A)
  }

  func testAttributeNotLong_mapsToStatus0x0B() {
    let pe = makeError(code: CBATTError.attributeNotLong.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0B)
  }

  func testInvalidAttributeValueLength_mapsToStatus0x0D() {
    let pe = makeError(code: CBATTError.invalidAttributeValueLength.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0D)
  }

  func testInsufficientEncryption_mapsToStatus0x0F() {
    let pe = makeError(code: CBATTError.insufficientEncryption.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x0F)
  }

  func testInsufficientResources_mapsToStatus0x11() {
    let pe = makeError(code: CBATTError.insufficientResources.rawValue).toPigeonError()
    XCTAssertEqual(pe.code, "gatt-status-failed")
    XCTAssertEqual(pe.details as? Int, 0x11)
  }

  // MARK: - Unknown domain/code

  func testUnknownDomain_mapsToBlueyUnknown() {
    let err = NSError(domain: "org.example.Unknown", code: 42, userInfo: nil)
    let pe = err.toPigeonError()
    XCTAssertEqual(pe.code, "bluey-unknown")
  }

  func testUnknownCBATTErrorCode_mapsToBlueyUnknown() {
    let err = NSError(domain: CBATTErrorDomain, code: 0xFF, userInfo: nil)
    let pe = err.toPigeonError()
    XCTAssertEqual(pe.code, "bluey-unknown")
  }
}
