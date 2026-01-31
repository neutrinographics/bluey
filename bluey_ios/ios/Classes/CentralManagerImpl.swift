import Foundation
import CoreBluetooth
import Flutter

/// Implementation of the Central (client) role BLE operations.
class CentralManagerImpl: NSObject {
    private let flutterApi: BlueyFlutterApi
    private let centralManager: CBCentralManager

    private lazy var centralManagerDelegate: CentralManagerDelegate = {
        let delegate = CentralManagerDelegate()
        delegate.manager = self
        return delegate
    }()

    private lazy var peripheralDelegate: PeripheralDelegate = {
        let delegate = PeripheralDelegate()
        delegate.manager = self
        return delegate
    }()

    // Cached peripherals by UUID
    private var peripherals: [String: CBPeripheral] = [:]

    // GATT caches
    private var services: [String: [String: CBService]] = [:] // [deviceId: [serviceUuid: service]]
    private var characteristics: [String: [String: CBCharacteristic]] = [:] // [deviceId: [charUuid: char]]
    private var descriptors: [String: [String: CBDescriptor]] = [:] // [deviceId: [descUuid: desc]]

    // Completion handlers
    private var connectCompletions: [String: (Result<Void, Error>) -> Void] = [:]
    private var disconnectCompletions: [String: (Result<Void, Error>) -> Void] = [:]
    private var discoverServicesCompletions: [String: (Result<[ServiceDto], Error>) -> Void] = [:]
    private var readCharacteristicCompletions: [String: [String: (Result<FlutterStandardTypedData, Error>) -> Void]] = [:]
    private var writeCharacteristicCompletions: [String: [String: (Result<Void, Error>) -> Void]] = [:]
    private var notifyCompletions: [String: [String: (Result<Void, Error>) -> Void]] = [:]
    private var readDescriptorCompletions: [String: [String: (Result<FlutterStandardTypedData, Error>) -> Void]] = [:]
    private var writeDescriptorCompletions: [String: [String: (Result<Void, Error>) -> Void]] = [:]
    private var readRssiCompletions: [String: (Result<Int64, Error>) -> Void] = [:]

    // Service discovery tracking
    private var pendingServiceDiscovery: [String: Set<String>] = [:] // [deviceId: Set<serviceUuid>] - services waiting for characteristics
    private var pendingCharacteristicDiscovery: [String: Set<String>] = [:] // [deviceId: Set<charUuid>] - characteristics waiting for descriptors

    init(messenger: FlutterBinaryMessenger) {
        flutterApi = BlueyFlutterApi(binaryMessenger: messenger)
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        centralManager.delegate = centralManagerDelegate
    }

    // MARK: - State

    func getState() -> BluetoothStateDto {
        return centralManager.state.toDto()
    }

    func authorize(completion: @escaping (Result<Bool, Error>) -> Void) {
        // On iOS 13+, accessing the central manager automatically triggers authorization
        // The state will reflect if authorization was granted
        let state = centralManager.state
        switch state {
        case .unauthorized:
            completion(.success(false))
        case .poweredOn:
            completion(.success(true))
        case .poweredOff:
            // Bluetooth is off but we may still have authorization
            completion(.success(true))
        default:
            // Unknown state, assume we need to wait
            completion(.success(true))
        }
    }

    func openSettings(completion: @escaping (Result<Void, Error>) -> Void) {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            completion(.failure(BlueyError.unknown))
            return
        }
        UIApplication.shared.open(url) { success in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(BlueyError.unknown))
            }
        }
        #else
        completion(.failure(BlueyError.unsupported))
        #endif
    }

    // MARK: - Scanning

    func startScan(config: ScanConfigDto, completion: @escaping (Result<Void, Error>) -> Void) {
        let serviceUUIDs: [CBUUID]? = config.serviceUuids.isEmpty ? nil : config.serviceUuids.map { $0.toCBUUID() }
        let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
        completion(.success(()))
    }

    func stopScan(completion: @escaping (Result<Void, Error>) -> Void) {
        centralManager.stopScan()
        flutterApi.onScanComplete { _ in }
        completion(.success(()))
    }

    // MARK: - Connection

    func connect(deviceId: String, config: ConnectConfigDto, completion: @escaping (Result<String, Error>) -> Void) {
        guard let peripheral = peripherals[deviceId] else {
            completion(.failure(BlueyError.notFound))
            return
        }

        connectCompletions[deviceId] = { result in
            switch result {
            case .success:
                completion(.success(deviceId))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(deviceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let peripheral = peripherals[deviceId] else {
            completion(.failure(BlueyError.notFound))
            return
        }

        disconnectCompletions[deviceId] = completion
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Service Discovery

    func discoverServices(deviceId: String, completion: @escaping (Result<[ServiceDto], Error>) -> Void) {
        guard let peripheral = peripherals[deviceId] else {
            completion(.failure(BlueyError.notFound))
            return
        }

        guard peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        discoverServicesCompletions[deviceId] = completion
        peripheral.discoverServices(nil)
    }

    // MARK: - Characteristic Operations

    func readCharacteristic(deviceId: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        let charUuid = normalizeUuid(characteristicUuid)
        guard let characteristic = findCharacteristic(deviceId: deviceId, uuid: charUuid) else {
            completion(.failure(BlueyError.notFound))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        let cacheKey = characteristic.uuid.uuidString.lowercased()
        readCharacteristicCompletions[deviceId, default: [:]][cacheKey] = completion
        peripheral.readValue(for: characteristic)
    }

    func writeCharacteristic(deviceId: String, characteristicUuid: String, value: FlutterStandardTypedData, withResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let charUuid = normalizeUuid(characteristicUuid)
        guard let characteristic = findCharacteristic(deviceId: deviceId, uuid: charUuid) else {
            completion(.failure(BlueyError.notFound))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse

        if withResponse {
            let cacheKey = characteristic.uuid.uuidString.lowercased()
            writeCharacteristicCompletions[deviceId, default: [:]][cacheKey] = completion
        }

        peripheral.writeValue(value.data, for: characteristic, type: type)

        if !withResponse {
            completion(.success(()))
        }
    }

    func setNotification(deviceId: String, characteristicUuid: String, enable: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let charUuid = normalizeUuid(characteristicUuid)
        guard let characteristic = findCharacteristic(deviceId: deviceId, uuid: charUuid) else {
            completion(.failure(BlueyError.notFound))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        let cacheKey = characteristic.uuid.uuidString.lowercased()
        notifyCompletions[deviceId, default: [:]][cacheKey] = completion
        peripheral.setNotifyValue(enable, for: characteristic)
    }

    /// Finds a characteristic by UUID, handling both short and full UUID formats.
    private func findCharacteristic(deviceId: String, uuid: String) -> CBCharacteristic? {
        guard let deviceChars = characteristics[deviceId] else { return nil }

        // Try exact match first
        if let char = deviceChars[uuid] {
            return char
        }

        // Try matching by CBUUID (handles short UUID matching)
        let targetCBUUID = uuid.toCBUUID()
        for (_, char) in deviceChars {
            if char.uuid == targetCBUUID {
                return char
            }
        }

        return nil
    }

    /// Normalizes a UUID string to lowercase without hyphens for consistent comparison.
    private func normalizeUuid(_ uuid: String) -> String {
        return uuid.lowercased()
    }

    // MARK: - Descriptor Operations

    func readDescriptor(deviceId: String, descriptorUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        let descUuid = normalizeUuid(descriptorUuid)
        guard let descriptor = findDescriptor(deviceId: deviceId, uuid: descUuid) else {
            completion(.failure(BlueyError.notFound))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        let cacheKey = descriptor.uuid.uuidString.lowercased()
        readDescriptorCompletions[deviceId, default: [:]][cacheKey] = completion
        peripheral.readValue(for: descriptor)
    }

    func writeDescriptor(deviceId: String, descriptorUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        let descUuid = normalizeUuid(descriptorUuid)
        guard let descriptor = findDescriptor(deviceId: deviceId, uuid: descUuid) else {
            completion(.failure(BlueyError.notFound))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        let cacheKey = descriptor.uuid.uuidString.lowercased()
        writeDescriptorCompletions[deviceId, default: [:]][cacheKey] = completion
        peripheral.writeValue(value.data, for: descriptor)
    }

    /// Finds a descriptor by UUID, handling both short and full UUID formats.
    private func findDescriptor(deviceId: String, uuid: String) -> CBDescriptor? {
        guard let deviceDescs = descriptors[deviceId] else { return nil }

        // Try exact match first
        if let desc = deviceDescs[uuid] {
            return desc
        }

        // Try matching by CBUUID (handles short UUID matching)
        let targetCBUUID = uuid.toCBUUID()
        for (_, desc) in deviceDescs {
            if desc.uuid == targetCBUUID {
                return desc
            }
        }

        return nil
    }

    // MARK: - MTU

    func getMaximumWriteLength(deviceId: String, withResponse: Bool) -> Int64 {
        guard let peripheral = peripherals[deviceId] else {
            return 20 // Default BLE MTU - 3
        }

        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        return Int64(peripheral.maximumWriteValueLength(for: type))
    }

    // MARK: - RSSI

    func readRssi(deviceId: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected))
            return
        }

        readRssiCompletions[deviceId] = completion
        peripheral.readRSSI()
    }

    // MARK: - CBCentralManagerDelegate callbacks

    func didUpdateState(central: CBCentralManager) {
        let stateDto = central.state.toDto()
        flutterApi.onStateChanged(state: stateDto) { _ in }
    }

    func didDiscover(central: CBCentralManager, peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Cache the peripheral
        if peripherals[deviceId] == nil {
            peripheral.delegate = peripheralDelegate
            peripherals[deviceId] = peripheral
        }

        let deviceDto = peripheral.toDeviceDto(rssi: rssi.intValue, advertisementData: advertisementData)
        flutterApi.onDeviceDiscovered(device: deviceDto) { _ in }
    }

    func didConnect(central: CBCentralManager, peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Notify connection state change
        let event = ConnectionStateEventDto(deviceId: deviceId, state: .connected)
        flutterApi.onConnectionStateChanged(event: event) { _ in }

        // Complete the connection
        if let completion = connectCompletions.removeValue(forKey: deviceId) {
            completion(.success(()))
        }
    }

    func didFailToConnect(central: CBCentralManager, peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        if let completion = connectCompletions.removeValue(forKey: deviceId) {
            completion(.failure(error ?? BlueyError.unknown))
        }
    }

    func didDisconnectPeripheral(central: CBCentralManager, peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Clear caches
        services.removeValue(forKey: deviceId)
        characteristics.removeValue(forKey: deviceId)
        descriptors.removeValue(forKey: deviceId)

        // Clear pending discovery state
        pendingServiceDiscovery.removeValue(forKey: deviceId)
        pendingCharacteristicDiscovery.removeValue(forKey: deviceId)

        // Clear pending completions with error
        clearPendingCompletions(for: deviceId, error: error ?? BlueyError.unknown)

        // Notify connection state change
        let event = ConnectionStateEventDto(deviceId: deviceId, state: .disconnected)
        flutterApi.onConnectionStateChanged(event: event) { _ in }

        // Complete the disconnect
        if let completion = disconnectCompletions.removeValue(forKey: deviceId) {
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    // MARK: - CBPeripheralDelegate callbacks

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Check if we have a pending completion - if not, this might be a re-discovery
        guard discoverServicesCompletions[deviceId] != nil else {
            return
        }

        if let error = error {
            let completion = discoverServicesCompletions.removeValue(forKey: deviceId)
            completion?(.failure(error))
            return
        }

        let cbServices = peripheral.services ?? []

        // If no services, complete immediately
        if cbServices.isEmpty {
            let completion = discoverServicesCompletions.removeValue(forKey: deviceId)
            completion?(.success([]))
            return
        }

        // Track which services need characteristic discovery
        var pendingServices = Set<String>()
        for service in cbServices {
            let serviceUuid = service.uuid.uuidString.lowercased()
            services[deviceId, default: [:]][serviceUuid] = service
            pendingServices.insert(serviceUuid)

            // Start discovering characteristics for each service
            peripheral.discoverCharacteristics(nil, for: service)
        }

        pendingServiceDiscovery[deviceId] = pendingServices
    }

    func didDiscoverIncludedServices(peripheral: CBPeripheral, service: CBService, error: Error?) {
        // Store included services in cache
        let deviceId = peripheral.identifier.uuidString.lowercased()
        if let includedServices = service.includedServices {
            for included in includedServices {
                let uuid = included.uuid.uuidString.lowercased()
                services[deviceId, default: [:]][uuid] = included
            }
        }
    }

    func didDiscoverCharacteristics(peripheral: CBPeripheral, service: CBService, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let serviceUuid = service.uuid.uuidString.lowercased()

        // Remove this service from pending list
        pendingServiceDiscovery[deviceId]?.remove(serviceUuid)

        guard error == nil else {
            // Even on error, check if discovery is complete
            checkDiscoveryComplete(deviceId: deviceId, peripheral: peripheral)
            return
        }

        let cbCharacteristics = service.characteristics ?? []

        // If no characteristics, check if discovery is complete
        if cbCharacteristics.isEmpty {
            checkDiscoveryComplete(deviceId: deviceId, peripheral: peripheral)
            return
        }

        // Track which characteristics need descriptor discovery
        for characteristic in cbCharacteristics {
            let charUuid = characteristic.uuid.uuidString.lowercased()
            characteristics[deviceId, default: [:]][charUuid] = characteristic
            pendingCharacteristicDiscovery[deviceId, default: []].insert(charUuid)

            // Discover descriptors for each characteristic
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func didDiscoverDescriptors(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        // Remove this characteristic from pending list
        pendingCharacteristicDiscovery[deviceId]?.remove(charUuid)

        // Cache descriptors (even if error, they may be partially discovered)
        if error == nil {
            let cbDescriptors = characteristic.descriptors ?? []
            for descriptor in cbDescriptors {
                let descUuid = descriptor.uuid.uuidString.lowercased()
                descriptors[deviceId, default: [:]][descUuid] = descriptor
            }
        }

        // Check if all discovery is complete
        checkDiscoveryComplete(deviceId: deviceId, peripheral: peripheral)
    }

    private func checkDiscoveryComplete(deviceId: String, peripheral: CBPeripheral) {
        // Check if all services have had their characteristics discovered
        let pendingServices = pendingServiceDiscovery[deviceId] ?? []
        let pendingChars = pendingCharacteristicDiscovery[deviceId] ?? []

        // Discovery is complete when no services or characteristics are pending
        guard pendingServices.isEmpty && pendingChars.isEmpty else {
            return
        }

        // Clear tracking state
        pendingServiceDiscovery.removeValue(forKey: deviceId)
        pendingCharacteristicDiscovery.removeValue(forKey: deviceId)

        // Get the completion handler
        guard let completion = discoverServicesCompletions.removeValue(forKey: deviceId) else {
            return
        }

        // Build the final service DTOs with all discovered characteristics and descriptors
        let cbServices = peripheral.services ?? []
        var serviceDtos: [ServiceDto] = []

        for service in cbServices {
            serviceDtos.append(service.toDto())
        }

        completion(.success(serviceDtos))
    }

    func didUpdateCharacteristicValue(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        // Check if this was a read request
        if let completion = readCharacteristicCompletions[deviceId]?.removeValue(forKey: charUuid) {
            if let error = error {
                completion(.failure(error))
            } else {
                let value = characteristic.value ?? Data()
                completion(.success(FlutterStandardTypedData(bytes: value)))
            }
            return
        }

        // Otherwise it's a notification
        if error == nil {
            let value = characteristic.value ?? Data()
            let notification = NotificationEventDto(
                deviceId: deviceId,
                characteristicUuid: charUuid,
                value: FlutterStandardTypedData(bytes: value)
            )
            flutterApi.onNotification(event: notification) { _ in }
        }
    }

    func didWriteCharacteristicValue(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        guard let completion = writeCharacteristicCompletions[deviceId]?.removeValue(forKey: charUuid) else {
            return
        }

        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    func didUpdateNotificationState(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        guard let completion = notifyCompletions[deviceId]?.removeValue(forKey: charUuid) else {
            return
        }

        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    func didUpdateDescriptorValue(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let descUuid = descriptor.uuid.uuidString.lowercased()

        guard let completion = readDescriptorCompletions[deviceId]?.removeValue(forKey: descUuid) else {
            return
        }

        if let error = error {
            completion(.failure(error))
        } else {
            let value: Data
            switch descriptor.value {
            case let data as Data:
                value = data
            case let string as String:
                value = string.data(using: .utf8) ?? Data()
            case let number as NSNumber:
                var num = number.uint16Value
                value = Data(bytes: &num, count: MemoryLayout<UInt16>.size)
            default:
                value = Data()
            }
            completion(.success(FlutterStandardTypedData(bytes: value)))
        }
    }

    func didWriteDescriptorValue(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let descUuid = descriptor.uuid.uuidString.lowercased()

        guard let completion = writeDescriptorCompletions[deviceId]?.removeValue(forKey: descUuid) else {
            return
        }

        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    func didReadRSSI(peripheral: CBPeripheral, rssi: NSNumber, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        guard let completion = readRssiCompletions.removeValue(forKey: deviceId) else {
            return
        }

        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(rssi.int64Value))
        }
    }

    // MARK: - Helpers

    private func clearPendingCompletions(for deviceId: String, error: Error) {
        // Clear all pending completions for this device with error
        if let completions = readCharacteristicCompletions.removeValue(forKey: deviceId) {
            for (_, completion) in completions {
                completion(.failure(error))
            }
        }
        if let completions = writeCharacteristicCompletions.removeValue(forKey: deviceId) {
            for (_, completion) in completions {
                completion(.failure(error))
            }
        }
        if let completions = notifyCompletions.removeValue(forKey: deviceId) {
            for (_, completion) in completions {
                completion(.failure(error))
            }
        }
        if let completions = readDescriptorCompletions.removeValue(forKey: deviceId) {
            for (_, completion) in completions {
                completion(.failure(error))
            }
        }
        if let completions = writeDescriptorCompletions.removeValue(forKey: deviceId) {
            for (_, completion) in completions {
                completion(.failure(error))
            }
        }
        if let completion = readRssiCompletions.removeValue(forKey: deviceId) {
            completion(.failure(error))
        }
    }
}
