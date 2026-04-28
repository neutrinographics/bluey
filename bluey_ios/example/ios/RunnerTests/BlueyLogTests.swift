import XCTest
@testable import bluey_ios

/// Captures `BlueyFlutterApiProtocol.onLog` calls for assertion.
///
/// We can't subclass the Pigeon-generated `BlueyFlutterApi` (its initializer
/// requires a `FlutterBinaryMessenger`) so we satisfy the protocol directly.
/// All non-onLog methods are no-ops; tests only inspect onLog.
final class FakeBlueyFlutterApi: BlueyFlutterApiProtocol {
    private(set) var capturedEvents: [LogEventDto] = []

    func onLog(event eventArg: LogEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        capturedEvents.append(eventArg)
        completion(.success(()))
    }

    // MARK: - Unused methods (no-op stubs)
    func onStateChanged(state stateArg: BluetoothStateDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onDeviceDiscovered(device deviceArg: DeviceDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onScanComplete(completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onConnectionStateChanged(event eventArg: ConnectionStateEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onNotification(event eventArg: NotificationEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onMtuChanged(event eventArg: MtuChangedEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onCentralConnected(central centralArg: CentralDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onCentralDisconnected(centralId centralIdArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onReadRequest(request requestArg: ReadRequestDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onWriteRequest(request requestArg: WriteRequestDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onCharacteristicSubscribed(centralId centralIdArg: String, characteristicUuid characteristicUuidArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onCharacteristicUnsubscribed(centralId centralIdArg: String, characteristicUuid characteristicUuidArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onServicesChanged(deviceId deviceIdArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
}

/// Unit tests for `BlueyLog` Swift singleton.
final class BlueyLogTests: XCTestCase {

    private var fakeApi: FakeBlueyFlutterApi!

    override func setUp() {
        super.setUp()
        BlueyLog.shared.resetForTest()
        fakeApi = FakeBlueyFlutterApi()
    }

    override func tearDown() {
        BlueyLog.shared.resetForTest()
        fakeApi = nil
        super.tearDown()
    }

    func test_log_emits_via_flutterApi_onLog_when_level_is_met() {
        BlueyLog.shared.bind(fakeApi)
        BlueyLog.shared.setLevel(.info)

        BlueyLog.shared.log(
            .info,
            "bluey.ios.test",
            "hello",
            data: ["k": "v"],
            errorCode: "E1"
        )

        XCTAssertEqual(fakeApi.capturedEvents.count, 1)
        let event = fakeApi.capturedEvents[0]
        XCTAssertEqual(event.context, "bluey.ios.test")
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.message, "hello")
        XCTAssertEqual(event.errorCode, "E1")
        // data is [String?: Any?] post-bridge
        XCTAssertEqual(event.data["k"] as? String, "v")
        XCTAssertGreaterThan(event.timestampMicros, 0)
    }

    func test_log_does_NOT_emit_when_level_is_filtered() {
        BlueyLog.shared.bind(fakeApi)
        BlueyLog.shared.setLevel(.info)

        BlueyLog.shared.log(.trace, "ctx", "filtered-trace")
        BlueyLog.shared.log(.debug, "ctx", "filtered-debug")

        XCTAssertEqual(fakeApi.capturedEvents.count, 0)
    }

    func test_setLevel_updates_threshold() {
        BlueyLog.shared.bind(fakeApi)

        BlueyLog.shared.setLevel(.warn)
        BlueyLog.shared.log(.info, "ctx", "info-suppressed")
        XCTAssertEqual(fakeApi.capturedEvents.count, 0)

        BlueyLog.shared.log(.warn, "ctx", "warn-emitted")
        XCTAssertEqual(fakeApi.capturedEvents.count, 1)
        XCTAssertEqual(fakeApi.capturedEvents[0].message, "warn-emitted")
    }

    func test_log_with_no_flutterApi_bound_silently_no_ops() {
        // No bind() call; setLevel only.
        BlueyLog.shared.setLevel(.trace)

        // Must not crash.
        BlueyLog.shared.log(.info, "ctx", "early-log")

        // After binding, subsequent log emits.
        BlueyLog.shared.bind(fakeApi)
        BlueyLog.shared.log(.info, "ctx", "later-log")
        XCTAssertEqual(fakeApi.capturedEvents.count, 1)
        XCTAssertEqual(fakeApi.capturedEvents[0].message, "later-log")
    }
}
