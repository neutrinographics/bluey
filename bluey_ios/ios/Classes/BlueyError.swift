import Foundation

/// Swift-internal error vocabulary for the Bluey iOS plugin. Never crosses
/// the Pigeon FFI boundary — use `toClientPigeonError()` or
/// `toServerPigeonError()` at the call site to translate into one of the
/// well-known Pigeon error codes Dart knows how to handle.
enum BlueyError: Error {
    case unknown
    case unsupported
    case notConnected
    case notFound
    case timeout
    /// I088 D.11 — Dart passed a non-null `characteristicHandle` /
    /// `descriptorHandle` but the per-device `CentralHandleStore` no
    /// longer recognises it. Indicates Service Changed
    /// (`peripheral(_, didModifyServices:)`) cleared the table and the
    /// caller is holding a stale reference. Distinct from `notFound`,
    /// which is the legacy null-handle / UUID-miss path.
    case handleInvalidated
}

extension BlueyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred"
        case .unsupported:
            return "Operation not supported"
        case .notConnected:
            return "Device not connected"
        case .notFound:
            return "Resource not found"
        case .timeout:
            return "Operation timed out"
        case .handleInvalidated:
            return "GATT attribute handle invalidated by Service Changed"
        }
    }
}

extension BlueyError {
    /// Client-side translation (used by `CentralManagerImpl`). `notFound`
    /// and `notConnected` signal a vanished peer on the client side
    /// (iOS invalidates cached handles synchronously on disconnect), so
    /// they map to `gatt-disconnected` which the Dart lifecycle layer
    /// treats as a dead-peer signal.
    func toClientPigeonError() -> PigeonError {
        switch self {
        case .notFound, .notConnected:
            return PigeonError(code: "gatt-disconnected",
                               message: self.errorDescription,
                               details: nil)
        case .unsupported:
            return PigeonError(code: "gatt-status-failed",
                               message: self.errorDescription,
                               details: 0x06)
        case .timeout:
            return PigeonError(code: "gatt-timeout",
                               message: self.errorDescription,
                               details: nil)
        case .unknown:
            return PigeonError(code: "bluey-unknown",
                               message: self.errorDescription,
                               details: nil)
        case .handleInvalidated:
            return PigeonError(code: "gatt-handle-invalidated",
                               message: self.errorDescription,
                               details: nil)
        }
    }

    /// Server-side translation (used by `PeripheralManagerImpl`). On the
    /// server side, `notFound`/`notConnected` mean "attribute the peer
    /// requested wasn't registered" — a programming error in the user's
    /// hosted-service setup, NOT a disconnect. Map to ATT
    /// ATTRIBUTE_NOT_FOUND (0x0A) so callers see a typed status-failed
    /// exception rather than a fake disconnect.
    func toServerPigeonError() -> PigeonError {
        switch self {
        case .notFound, .notConnected:
            return PigeonError(code: "gatt-status-failed",
                               message: self.errorDescription,
                               details: 0x0A)
        case .unsupported:
            return PigeonError(code: "gatt-status-failed",
                               message: self.errorDescription,
                               details: 0x06)
        case .timeout:
            return PigeonError(code: "gatt-timeout",
                               message: self.errorDescription,
                               details: nil)
        case .unknown:
            return PigeonError(code: "bluey-unknown",
                               message: self.errorDescription,
                               details: nil)
        case .handleInvalidated:
            // I088 D.13 — server-side handle miss now real: e.g. a
            // notify after removeService. Surface as the typed
            // gatt-handle-invalidated code so Dart converts it into
            // AttributeHandleInvalidatedException, same as the client
            // side.
            return PigeonError(code: "gatt-handle-invalidated",
                               message: self.errorDescription,
                               details: nil)
        }
    }
}
