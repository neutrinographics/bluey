import Foundation
import CoreBluetooth

extension NSError {
    /// Translates a CoreBluetooth `NSError` to a `PigeonError` the Dart
    /// adapter already knows how to handle. `CBATTErrorDomain` codes map
    /// to `gatt-status-failed` with the corresponding BLE ATT status
    /// byte (Bluetooth Core Spec v5.3 Vol 3 Part F §3.4.1.1). Any other
    /// domain — or a `CBATTErrorDomain` code we don't recognise — falls
    /// through to `bluey-unknown` so the user still never sees raw
    /// `PlatformException`.
    func toPigeonError() -> PigeonError {
        if self.domain == CBATTErrorDomain, let status = NSError.attStatusByte(for: self.code) {
            return PigeonError(code: "gatt-status-failed",
                               message: self.localizedDescription,
                               details: status)
        }
        return PigeonError(code: "bluey-unknown",
                           message: self.localizedDescription,
                           details: nil)
    }

    /// Maps a `CBATTError` code to its BLE ATT status byte. Returns nil
    /// for codes we don't explicitly recognise so the caller can fall
    /// through to `bluey-unknown`.
    private static func attStatusByte(for code: Int) -> Int? {
        switch code {
        case CBATTError.invalidHandle.rawValue:               return 0x01
        case CBATTError.readNotPermitted.rawValue:            return 0x02
        case CBATTError.writeNotPermitted.rawValue:           return 0x03
        case CBATTError.invalidPdu.rawValue:                  return 0x04
        case CBATTError.insufficientAuthentication.rawValue:  return 0x05
        case CBATTError.requestNotSupported.rawValue:         return 0x06
        case CBATTError.invalidOffset.rawValue:               return 0x07
        case CBATTError.insufficientAuthorization.rawValue:   return 0x08
        case CBATTError.attributeNotFound.rawValue:           return 0x0A
        case CBATTError.attributeNotLong.rawValue:            return 0x0B
        case CBATTError.invalidAttributeValueLength.rawValue: return 0x0D
        case CBATTError.insufficientEncryption.rawValue:      return 0x0F
        case CBATTError.insufficientResources.rawValue:       return 0x11
        default:                                               return nil
        }
    }
}
