import Foundation
import CoreBluetooth
import Flutter

/// Implementation of the Peripheral (server) role BLE operations.
class PeripheralManagerImpl: NSObject {
    private let flutterApi: BlueyFlutterApi
    private let peripheralManager: CBPeripheralManager

    private lazy var peripheralManagerDelegate: PeripheralManagerDelegate = {
        let delegate = PeripheralManagerDelegate()
        delegate.manager = self
        return delegate
    }()

    // Added services
    private var services: [String: CBMutableService] = [:] // [serviceUuid: service]
    private var characteristics: [String: CBMutableCharacteristic] = [:] // [charUuid: char]

    // Subscribed centrals per characteristic
    private var subscribedCentrals: [String: Set<String>] = [:] // [charUuid: Set<centralId>]

    // Connected centrals
    private var centrals: [String: CBCentral] = [:] // [centralId: central]

    // Pending ATT requests
    private var pendingReadRequests: [Int: CBATTRequest] = [:]
    private var pendingWriteRequests: [Int: [CBATTRequest]] = [:]
    private var nextRequestId: Int = 0

    // Completion handlers
    private var addServiceCompletions: [String: (Result<Void, Error>) -> Void] = [:]
    private var startAdvertisingCompletion: ((Result<Void, Error>) -> Void)?

    init(messenger: FlutterBinaryMessenger) {
        flutterApi = BlueyFlutterApi(binaryMessenger: messenger)
        peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)
        super.init()
        peripheralManager.delegate = peripheralManagerDelegate
    }

    // MARK: - Service Management

    func addService(service: LocalServiceDto, completion: @escaping (Result<Void, Error>) -> Void) {
        let mutableService = service.toMutableService()
        let serviceUuid = service.uuid.lowercased()

        // Store characteristics for later lookup
        if let chars = mutableService.characteristics {
            for char in chars {
                if let mutableChar = char as? CBMutableCharacteristic {
                    let charUuid = char.uuid.uuidString.lowercased()
                    characteristics[charUuid] = mutableChar
                }
            }
        }

        services[serviceUuid] = mutableService
        addServiceCompletions[serviceUuid] = completion
        peripheralManager.add(mutableService)
    }

    func removeService(serviceUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let uuid = serviceUuid.lowercased()
        guard let service = services.removeValue(forKey: uuid) else {
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        // Remove characteristics
        if let chars = service.characteristics {
            for char in chars {
                let charUuid = char.uuid.uuidString.lowercased()
                characteristics.removeValue(forKey: charUuid)
                subscribedCentrals.removeValue(forKey: charUuid)
            }
        }

        peripheralManager.remove(service)
        completion(.success(()))
    }

    // MARK: - Advertising

    func startAdvertising(config: AdvertiseConfigDto, completion: @escaping (Result<Void, Error>) -> Void) {
        var advertisement: [String: Any] = [:]

        if let name = config.name {
            advertisement[CBAdvertisementDataLocalNameKey] = name
        }

        if !config.serviceUuids.isEmpty {
            let uuids = config.serviceUuids.map { $0.toCBUUID() }
            advertisement[CBAdvertisementDataServiceUUIDsKey] = uuids
        }

        // Note: iOS does not support manufacturer data in advertising
        // config.manufacturerDataCompanyId and config.manufacturerData are ignored

        startAdvertisingCompletion = completion
        peripheralManager.startAdvertising(advertisement)
    }

    func stopAdvertising(completion: @escaping (Result<Void, Error>) -> Void) {
        peripheralManager.stopAdvertising()
        completion(.success(()))
    }

    // MARK: - Notifications

    func notifyCharacteristic(characteristicUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        let uuid = characteristicUuid.lowercased()
        guard let characteristic = characteristics[uuid] else {
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        let success = peripheralManager.updateValue(value.data, for: characteristic, onSubscribedCentrals: nil)
        if success {
            completion(.success(()))
        } else {
            // Queue is full, will retry when isReadyToUpdateSubscribers is called
            // For simplicity, we report failure here
            completion(.failure(BlueyError.unknown.toServerPigeonError()))
        }
    }

    func notifyCharacteristicTo(centralId: String, characteristicUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        let uuid = characteristicUuid.lowercased()
        guard let characteristic = characteristics[uuid] else {
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        guard let central = centrals[centralId] else {
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        let success = peripheralManager.updateValue(value.data, for: characteristic, onSubscribedCentrals: [central])
        if success {
            completion(.success(()))
        } else {
            completion(.failure(BlueyError.unknown.toServerPigeonError()))
        }
    }

    // MARK: - Request Responses

    func respondToReadRequest(requestId: Int, status: GattStatusDto, value: FlutterStandardTypedData?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let request = pendingReadRequests.removeValue(forKey: requestId) else {
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        if let value = value {
            request.value = value.data
        }

        peripheralManager.respond(to: request, withResult: status.toCBATTError())
        completion(.success(()))
    }

    func respondToWriteRequest(requestId: Int, status: GattStatusDto, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let requests = pendingWriteRequests.removeValue(forKey: requestId), let firstRequest = requests.first else {
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        peripheralManager.respond(to: firstRequest, withResult: status.toCBATTError())
        completion(.success(()))
    }

    // MARK: - Central Management

    func disconnectCentral(centralId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // iOS doesn't provide a direct way to disconnect a central
        // The central must disconnect itself
        // We can only remove them from our tracking
        centrals.removeValue(forKey: centralId)

        // Remove from all subscription lists
        for (charUuid, var centralSet) in subscribedCentrals {
            centralSet.remove(centralId)
            subscribedCentrals[charUuid] = centralSet
        }

        completion(.success(()))
    }

    func closeServer(completion: @escaping (Result<Void, Error>) -> Void) {
        // Stop advertising
        peripheralManager.stopAdvertising()

        // Remove all services
        peripheralManager.removeAllServices()

        // Clear caches
        services.removeAll()
        characteristics.removeAll()
        subscribedCentrals.removeAll()
        centrals.removeAll()
        pendingReadRequests.removeAll()
        pendingWriteRequests.removeAll()

        completion(.success(()))
    }

    // MARK: - Central Tracking

    /// Tracks a central and notifies Flutter if this is the first time we see it.
    /// iOS does not provide a connection state callback, so we infer connections
    /// from subscribe, read, and write events.
    private func trackCentralIfNeeded(_ central: CBCentral) {
        let centralId = central.identifier.uuidString.lowercased()
        let isNew = centrals[centralId] == nil
        centrals[centralId] = central

        if isNew {
            let centralDto = central.toCentralDto(mtu: central.maximumUpdateValueLength)
            flutterApi.onCentralConnected(central: centralDto) { _ in }
        }
    }

    // MARK: - CBPeripheralManagerDelegate callbacks

    func didUpdateState(peripheral: CBPeripheralManager) {
        let stateDto = peripheral.state.toDto()
        flutterApi.onStateChanged(state: stateDto) { _ in }
    }

    func didAddService(peripheral: CBPeripheralManager, service: CBService, error: Error?) {
        let serviceUuid = service.uuid.uuidString.lowercased()

        guard let completion = addServiceCompletions.removeValue(forKey: serviceUuid) else {
            return
        }

        if let error = error {
            services.removeValue(forKey: serviceUuid)
            completion(.failure((error as NSError).toPigeonError()))
        } else {
            completion(.success(()))
        }
    }

    func didStartAdvertising(peripheral: CBPeripheralManager, error: Error?) {
        guard let completion = startAdvertisingCompletion else {
            return
        }
        startAdvertisingCompletion = nil

        if let error = error {
            completion(.failure((error as NSError).toPigeonError()))
        } else {
            completion(.success(()))
        }
    }

    func didSubscribe(peripheral: CBPeripheralManager, central: CBCentral, characteristic: CBCharacteristic) {
        let centralId = central.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        // Track the central and notify Flutter if this is the first time we see it
        trackCentralIfNeeded(central)

        // Track subscription
        subscribedCentrals[charUuid, default: []].insert(centralId)
        flutterApi.onCharacteristicSubscribed(centralId: centralId, characteristicUuid: charUuid) { _ in }
    }

    func didUnsubscribe(peripheral: CBPeripheralManager, central: CBCentral, characteristic: CBCharacteristic) {
        let centralId = central.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        // Remove subscription
        subscribedCentrals[charUuid]?.remove(centralId)

        // Notify Flutter
        flutterApi.onCharacteristicUnsubscribed(centralId: centralId, characteristicUuid: charUuid) { _ in }

        // Note: We do NOT infer disconnection from unsubscribe events.
        // Disconnect detection is handled by the Bluey lifecycle control
        // service at the Dart layer via heartbeat timeouts and explicit
        // disconnect commands. This avoids false disconnections when a
        // client unsubscribes from notifications but stays connected.
    }

    func didReceiveRead(peripheral: CBPeripheralManager, request: CBATTRequest) {
        let centralId = request.central.identifier.uuidString.lowercased()
        let charUuid = request.characteristic.uuid.uuidString.lowercased()

        // Track the central and notify Flutter if this is the first time we see it
        trackCentralIfNeeded(request.central)

        // Store request for later response
        let requestId = nextRequestId
        nextRequestId += 1
        pendingReadRequests[requestId] = request

        // Notify Flutter
        let requestDto = ReadRequestDto(
            requestId: Int64(requestId),
            centralId: centralId,
            characteristicUuid: charUuid,
            offset: Int64(request.offset)
        )
        flutterApi.onReadRequest(request: requestDto) { _ in }
    }

    func didReceiveWrite(peripheral: CBPeripheralManager, requests: [CBATTRequest]) {
        guard let firstRequest = requests.first else { return }

        let centralId = firstRequest.central.identifier.uuidString.lowercased()

        // Track the central and notify Flutter if this is the first time we see it
        trackCentralIfNeeded(firstRequest.central)

        // Store requests for later response
        let requestId = nextRequestId
        nextRequestId += 1
        pendingWriteRequests[requestId] = requests

        // Notify Flutter for each request
        for request in requests {
            let charUuid = request.characteristic.uuid.uuidString.lowercased()
            let value = request.value ?? Data()

            let requestDto = WriteRequestDto(
                requestId: Int64(requestId),
                centralId: centralId,
                characteristicUuid: charUuid,
                value: FlutterStandardTypedData(bytes: value),
                offset: Int64(request.offset),
                responseNeeded: true // iOS always requires response for write requests received this way
            )
            flutterApi.onWriteRequest(request: requestDto) { _ in }
        }
    }

    func isReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
        // The queue has space again for notifications
        // We could retry any failed notifications here
    }
}
