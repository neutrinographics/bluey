import Foundation
import CoreBluetooth

extension NSError {
    /// Translates a CoreBluetooth `NSError` to a `PigeonError` the Dart
    /// adapter already knows how to handle. Any `CBATTErrorDomain` error
    /// becomes `gatt-status-failed` with `details` set to the numeric ATT
    /// status byte (Bluetooth Core Spec v5.3 Vol 3 Part F §3.4.1.1) — the
    /// domain itself is the contract, so future Apple-added codes are
    /// forwarded automatically without an allowlist. Any other domain
    /// falls through to `bluey-unknown` so user code never sees raw
    /// `PlatformException`.
    ///
    /// Mirrors Android's `ConnectionManager.statusFailedError` pattern,
    /// which forwards the raw `BluetoothGatt.GATT_*` status without an
    /// allowlist.
    func toPigeonError() -> PigeonError {
        if self.domain == CBATTErrorDomain {
            return PigeonError(code: "gatt-status-failed",
                               message: self.localizedDescription,
                               details: self.code)
        }
        return PigeonError(code: "bluey-unknown",
                           message: self.localizedDescription,
                           details: nil)
    }
}
