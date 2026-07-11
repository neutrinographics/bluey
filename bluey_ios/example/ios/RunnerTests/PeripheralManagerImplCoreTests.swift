import XCTest
import CoreBluetooth
import Flutter
@testable import bluey_ios

// MARK: - Instantiable stand-ins (audit R5)
//
// CBCentral and CBATTRequest cannot be created by client code, so the
// generic core is driven with these fakes — the Swift equivalent of the
// Kotlin captured-callback harness. CBMutableCharacteristic /
// CBMutableService ARE instantiable and are used directly.

final class FakeCentral: CentralLike {
    let identifier: UUID
    var maximumUpdateValueLength: Int

    init(identifier: UUID = UUID(), mtu: Int = 23) {
        self.identifier = identifier
        self.maximumUpdateValueLength = mtu
    }
}

final class FakeATTRequest: ATTRequestLike {
    let central: FakeCentral
    let characteristic: CBCharacteristic
    let offset: Int
    var value: Data?

    init(
        central: FakeCentral,
        characteristic: CBCharacteristic,
        offset: Int = 0,
        value: Data? = nil
    ) {
        self.central = central
        self.characteristic = characteristic
        self.offset = offset
        self.value = value
    }
}

/// Records every manager call; `updateValueResults` scripts the TX gate
/// (`true` = sent, `false` = queue full) — defaults to `true` when empty.
final class FakePeripheralManager: PeripheralManaging {
    typealias Central = FakeCentral
    typealias Request = FakeATTRequest

    var state: CBManagerState = .poweredOn
    var updateValueResults: [Bool] = []

    private(set) var addedServices: [CBMutableService] = []
    private(set) var removedServices: [CBMutableService] = []
    private(set) var removedAll = false
    private(set) var advertisingPayloads: [[String: Any]?] = []
    private(set) var stopAdvertisingCount = 0
    private(set) var updates: [(data: Data, characteristic: CBMutableCharacteristic, centrals: [FakeCentral]?)] = []
    private(set) var responses: [(request: FakeATTRequest, result: CBATTError.Code)] = []

    func add(_ service: CBMutableService) { addedServices.append(service) }
    func remove(_ service: CBMutableService) { removedServices.append(service) }
    func removeAllServices() { removedAll = true }
    func startAdvertising(_ advertisementData: [String: Any]?) {
        advertisingPayloads.append(advertisementData)
    }
    func stopAdvertising() { stopAdvertisingCount += 1 }
    func updateValue(
        _ value: Data,
        for characteristic: CBMutableCharacteristic,
        onSubscribedCentrals centrals: [FakeCentral]?
    ) -> Bool {
        updates.append((value, characteristic, centrals))
        return updateValueResults.isEmpty ? true : updateValueResults.removeFirst()
    }
    func respond(to request: FakeATTRequest, withResult result: CBATTError.Code) {
        responses.append((request, result))
    }
}

/// Captures the Flutter-facing events the server core emits.
final class CapturingFlutterApi: BlueyFlutterApiProtocol {
    private(set) var connectedCentrals: [CentralDto] = []
    private(set) var disconnectedCentralIds: [String] = []
    private(set) var subscribed: [(centralId: String, charUuid: String)] = []
    private(set) var unsubscribed: [(centralId: String, charUuid: String)] = []
    private(set) var readRequests: [ReadRequestDto] = []
    private(set) var writeRequests: [WriteRequestDto] = []
    private(set) var states: [BluetoothStateDto] = []

    func onCentralConnected(central centralArg: CentralDto, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        connectedCentrals.append(centralArg); completion(.success(()))
    }
    func onCentralDisconnected(centralId centralIdArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        disconnectedCentralIds.append(centralIdArg); completion(.success(()))
    }
    func onCharacteristicSubscribed(centralId centralIdArg: String, characteristicUuid characteristicUuidArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        subscribed.append((centralIdArg, characteristicUuidArg)); completion(.success(()))
    }
    func onCharacteristicUnsubscribed(centralId centralIdArg: String, characteristicUuid characteristicUuidArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        unsubscribed.append((centralIdArg, characteristicUuidArg)); completion(.success(()))
    }
    func onReadRequest(request requestArg: ReadRequestDto, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        readRequests.append(requestArg); completion(.success(()))
    }
    func onWriteRequest(request requestArg: WriteRequestDto, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        writeRequests.append(requestArg); completion(.success(()))
    }
    func onStateChanged(state stateArg: BluetoothStateDto, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        states.append(stateArg); completion(.success(()))
    }

    // Unused in these tests.
    func onLog(event eventArg: LogEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onDeviceDiscovered(device deviceArg: DeviceDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onScanComplete(completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onConnectionStateChanged(event eventArg: ConnectionStateEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onNotification(event eventArg: NotificationEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onMtuChanged(event eventArg: MtuChangedEventDto, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
    func onServicesChanged(deviceId deviceIdArg: String, completion: @escaping (Result<Void, PigeonError>) -> Void) { completion(.success(())) }
}

// MARK: - Tests

/// Delegate-sequence tests for the server core (audit R5 / NT-3): the
/// wiring between CoreBluetooth delegate events and Bluey's server
/// behavior, previously untestable because the impl was welded to
/// concrete CB types.
final class PeripheralManagerImplCoreTests: XCTestCase {
    private let presenceUuid = "b1e70005-0000-1000-8000-00805f9b34fb"
    private let dataUuid = "00002a37-0000-1000-8000-00805f9b34fb"

    private var manager: FakePeripheralManager!
    private var api: CapturingFlutterApi!
    private var core: PeripheralManagerImplCore<FakePeripheralManager>!

    override func setUp() {
        super.setUp()
        manager = FakePeripheralManager()
        api = CapturingFlutterApi()
        core = PeripheralManagerImplCore(flutterApi: api, manager: manager)
    }

    private func makeChar(_ uuid: String, properties: CBCharacteristicProperties = [.notify]) -> CBMutableCharacteristic {
        CBMutableCharacteristic(
            type: CBUUID(string: uuid),
            properties: properties,
            value: nil,
            permissions: []
        )
    }

    /// Registers a notifiable characteristic through the real addService
    /// flow (mint handle → manager.add → didAddService completion) and
    /// returns its minted handle plus the CBMutableCharacteristic the
    /// core actually stored.
    private func addNotifiableService(charUuid: String) -> (handle: Int64, characteristic: CBMutableCharacteristic) {
        let dto = LocalServiceDto(
            uuid: "0000180d-0000-1000-8000-00805f9b34fb",
            isPrimary: true,
            characteristics: [
                LocalCharacteristicDto(
                    uuid: charUuid,
                    properties: CharacteristicPropertiesDto(
                        canRead: false, canWrite: false,
                        canWriteWithoutResponse: false,
                        canNotify: true, canIndicate: false
                    ),
                    permissions: [],
                    descriptors: [],
                    handle: 0
                ),
            ],
            includedServices: []
        )
        var populated: LocalServiceDto?
        core.addService(service: dto) { result in
            populated = try? result.get()
        }
        let added = manager.addedServices.last!
        core.didAddService(service: added, error: nil)
        let handle = populated!.characteristics[0].handle
        let characteristic = added.characteristics!.first as! CBMutableCharacteristic
        return (handle, characteristic)
    }

    // MARK: Pattern B — presence characteristic as the disconnect signal

    func test_presenceUnsubscribe_firesCentralDisconnected() {
        let central = FakeCentral(mtu: 185)
        let presence = makeChar(presenceUuid)

        core.didSubscribe(central: central, characteristic: presence)
        XCTAssertEqual(api.connectedCentrals.count, 1)
        XCTAssertEqual(api.connectedCentrals[0].mtu, 185)

        core.didUnsubscribe(central: central, characteristic: presence)
        XCTAssertEqual(
            api.disconnectedCentralIds,
            [central.identifier.uuidString.lowercased()],
            "presence unsubscribe IS the iOS client-disconnect signal (I338 Pattern B)"
        )
    }

    func test_dataCharacteristicUnsubscribe_isNotADisconnect() {
        let central = FakeCentral()
        let dataChar = makeChar(dataUuid)

        core.didSubscribe(central: central, characteristic: dataChar)
        core.didUnsubscribe(central: central, characteristic: dataChar)

        XCTAssertEqual(api.unsubscribed.count, 1)
        XCTAssertTrue(
            api.disconnectedCentralIds.isEmpty,
            "a client may toggle data notifications while staying connected"
        )
    }

    // MARK: I040 — TX gate shut / reopen wiring

    func test_notifyDefersWhenGateShut_andIsReadyDrainsThroughManager() {
        let (handle, _) = addNotifiableService(charUuid: dataUuid)

        manager.updateValueResults = [false] // gate shut on first attempt
        var notifyResult: Result<Void, Error>?
        core.notifyCharacteristic(
            characteristicHandle: handle,
            value: FlutterStandardTypedData(bytes: Data([0x07]))
        ) { notifyResult = $0 }

        XCTAssertEqual(manager.updates.count, 1, "first attempt hit the manager")
        XCTAssertNil(notifyResult, "deferred — no completion while queued")

        // The OS signals readiness; the drain must go through the
        // manager again and complete the original caller.
        core.isReadyToUpdateSubscribers()
        XCTAssertEqual(manager.updates.count, 2, "drain re-attempted via manager")
        guard case .some(.success) = notifyResult else {
            return XCTFail("drained notify must complete successfully")
        }
    }

    func test_isReadyDrainHaltsWhenGateShutsAgain() {
        let (handle, _) = addNotifiableService(charUuid: dataUuid)

        manager.updateValueResults = [false, false] // both notifies deferred
        var completions = 0
        for byte: UInt8 in [1, 2] {
            core.notifyCharacteristic(
                characteristicHandle: handle,
                value: FlutterStandardTypedData(bytes: Data([byte]))
            ) { _ in completions += 1 }
        }
        XCTAssertEqual(completions, 0)

        // Gate reopens for exactly one send, then shuts again.
        manager.updateValueResults = [true, false]
        core.isReadyToUpdateSubscribers()
        XCTAssertEqual(completions, 1, "only the head drained; tail waits for the next ready signal")

        manager.updateValueResults = [true]
        core.isReadyToUpdateSubscribers()
        XCTAssertEqual(completions, 2)
    }

    // MARK: Batched writes (I047 shape)

    func test_didReceiveWriteBatch_emitsOneDtoPerRequest_underOneRequestId() {
        let central = FakeCentral()
        let charA = makeChar(dataUuid, properties: [.write])
        let charB = makeChar(presenceUuid, properties: [.write])

        core.didReceiveWrite(requests: [
            FakeATTRequest(central: central, characteristic: charA, value: Data([0x01])),
            FakeATTRequest(central: central, characteristic: charB, value: Data([0x02])),
        ])

        XCTAssertEqual(api.writeRequests.count, 2)
        XCTAssertEqual(
            api.writeRequests[0].requestId,
            api.writeRequests[1].requestId,
            "a batched ATT write shares one requestId (the I047 shape)"
        )
    }

    // MARK: Read requests answered through the manager

    func test_readRequest_respondsThroughManager_withValue() {
        let central = FakeCentral()
        let char = makeChar(dataUuid, properties: [.read])
        let request = FakeATTRequest(central: central, characteristic: char)

        core.didReceiveRead(request: request)
        XCTAssertEqual(api.readRequests.count, 1)

        var respondResult: Result<Void, Error>?
        core.respondToReadRequest(
            requestId: Int(api.readRequests[0].requestId),
            status: .success,
            value: FlutterStandardTypedData(bytes: Data([0x42]))
        ) { respondResult = $0 }

        XCTAssertEqual(manager.responses.count, 1)
        XCTAssertEqual(manager.responses[0].result, CBATTError.success)
        XCTAssertEqual(request.value, Data([0x42]), "the response value is stamped onto the ATT request")
        guard case .some(.success) = respondResult else {
            return XCTFail("respond must succeed")
        }
    }

    // MARK: Adapter state

    func test_poweredOff_isForwarded_andOpsAreRejected() {
        manager.state = .poweredOff
        core.didUpdateState()
        XCTAssertEqual(api.states.last, .off)

        var result: Result<Void, Error>?
        core.notifyCharacteristic(
            characteristicHandle: 1,
            value: FlutterStandardTypedData(bytes: Data())
        ) { result = $0 }
        guard case .some(.failure) = result else {
            return XCTFail("ops against a powered-off manager must be rejected")
        }
        XCTAssertTrue(manager.updates.isEmpty)
    }
}
