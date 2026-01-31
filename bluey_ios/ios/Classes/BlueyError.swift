import Foundation

/// Custom errors for the Bluey iOS plugin.
enum BlueyError: Error {
    case unknown
    case illegalArgument
    case unsupported
    case notConnected
    case notFound
}

extension BlueyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknown:
            return "An unknown error occurred"
        case .illegalArgument:
            return "Invalid argument"
        case .unsupported:
            return "Operation not supported"
        case .notConnected:
            return "Device not connected"
        case .notFound:
            return "Resource not found"
        }
    }
}
