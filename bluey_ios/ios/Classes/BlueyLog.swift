import Foundation
import os.log

/// Process-wide structured logger for the Bluey iOS plugin.
///
/// Emits log events along two paths:
///   1. **`os_log` tee** — visible in Console.app / `xcrun simctl spawn ... log stream`.
///   2. **Pigeon bridge** — `BlueyFlutterApi.onLog(...)` for forwarding into
///      the Dart side's `Bluey.logEvents` stream. The bridge is best-effort:
///      if no api is bound (e.g. very early plugin attach, or after detach),
///      bridge emits are silently dropped per the bootstrap-loss policy of
///      the structured-logging plan (I307).
///
/// Level filtering is applied before either path runs — events below
/// the current level are dropped entirely. Default threshold is `.info`;
/// Dart side updates it via the `BlueyHostApi.setLogLevel` channel.
///
/// Singleton because there is exactly one Flutter engine per process. Tests
/// use `resetForTest()` to clear state between runs.
final class BlueyLog {
    static let shared = BlueyLog()
    private init() {}

    private let queue = DispatchQueue(label: "com.neutrinographics.bluey.log", qos: .utility)
    private var minLevel: LogLevelDto = .info
    private var flutterApi: BlueyFlutterApiProtocol?

    /// Bind the Pigeon FlutterApi for native→Dart log forwarding.
    func bind(_ api: BlueyFlutterApiProtocol) {
        queue.sync { self.flutterApi = api }
    }

    /// Update the minimum severity threshold. Events below this level are dropped.
    func setLevel(_ level: LogLevelDto) {
        queue.sync { self.minLevel = level }
    }

    /// Reset state. Test-only.
    internal func resetForTest() {
        queue.sync {
            self.minLevel = .info
            self.flutterApi = nil
        }
    }

    /// Emit a structured log event.
    ///
    /// - Parameters:
    ///   - level: severity; events below the configured threshold are dropped.
    ///   - context: coarse subsystem tag (e.g. `"bluey.ios.central"`).
    ///   - message: human-readable message; do not embed secrets or full payload bytes.
    ///   - data: optional structured key/value pairs (preferred over string interpolation).
    ///   - errorCode: optional stable error code (e.g. `"GATT_133"`).
    func log(
        _ level: LogLevelDto,
        _ context: String,
        _ message: String,
        data: [String: Any?] = [:],
        errorCode: String? = nil
    ) {
        let (current, api) = queue.sync { (minLevel, flutterApi) }
        guard level.rawValue >= current.rawValue else { return }

        // Tee to os_log.
        let osType: OSLogType = {
            switch level {
            case .trace, .debug: return .debug
            case .info: return .info
            case .warn: return .default  // os_log has no dedicated warn level
            case .error: return .error
            }
        }()
        let logger = OSLog(subsystem: "com.neutrinographics.bluey", category: context)
        os_log("%{public}@", log: logger, type: osType, message)

        // Bridge to Dart (best-effort).
        guard let api = api else { return }
        // Pigeon generates `data` as `[String?: Any?]` (nullable key per Pigeon
        // Map convention); widen the key type so callers can pass plain
        // `[String: Any?]`.
        let pigeonData: [String?: Any?] = data.reduce(into: [:]) { result, kv in
            result[kv.key] = kv.value
        }
        let event = LogEventDto(
            context: context,
            level: level,
            message: message,
            data: pigeonData,
            errorCode: errorCode,
            timestampMicros: Int64(Date().timeIntervalSince1970 * 1_000_000)
        )
        api.onLog(event: event) { _ in }
    }
}
