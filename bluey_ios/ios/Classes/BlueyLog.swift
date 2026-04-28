import Foundation

/// Process-wide structured logger for the Bluey iOS plugin.
///
/// Forwards log events to the Dart side via `BlueyFlutterApi.onLog(...)` so
/// they reach the unified `Bluey.logEvents` stream. The bridge is
/// best-effort: if no api is bound (e.g. very early plugin attach, or
/// after detach), emits are silently dropped per the bootstrap-loss
/// policy of the structured-logging plan (I307).
///
/// Level filtering is applied before forwarding — events below the
/// current level are dropped entirely. Default threshold is `.info`;
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
        // Pigeon FlutterApi calls require the main thread. CB delegate
        // callbacks run on CB's own queue, so always hop to main.
        if Thread.isMainThread {
            api.onLog(event: event) { _ in }
        } else {
            DispatchQueue.main.async {
                api.onLog(event: event) { _ in }
            }
        }
    }
}
