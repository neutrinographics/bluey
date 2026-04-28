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

    // I088 — handle-identity tables. Populated alongside the
    // UUID-keyed caches above when CB fires the discovery callbacks;
    // the UUID-keyed maps remain in service for legacy code paths
    // (D.8/D.13 retire them). See `CentralHandleStore` for the mint
    // contract (per-device monotonic counter, shared between chars
    // and descs in encounter order).
    internal let handleStore = CentralHandleStore<CBCharacteristic, CBDescriptor>()

    // Pending completion slots — one FIFO per (device, key). Each OpSlot
    // owns its head-of-queue timer. See OpSlot.swift for semantics.
    private var connectSlots: [String: OpSlot<Void>] = [:]
    private var disconnectSlots: [String: OpSlot<Void>] = [:]
    private var discoverServicesSlots: [String: OpSlot<[ServiceDto]>] = [:]
    private var readCharacteristicSlots: [String: [String: OpSlot<FlutterStandardTypedData>]] = [:]
    private var writeCharacteristicSlots: [String: [String: OpSlot<Void>]] = [:]
    private var notifySlots: [String: [String: OpSlot<Void>]] = [:]
    private var readDescriptorSlots: [String: [String: OpSlot<FlutterStandardTypedData>]] = [:]
    private var writeDescriptorSlots: [String: [String: OpSlot<Void>]] = [:]
    private var readRssiSlots: [String: OpSlot<Int64>] = [:]

    // Configurable timeout values — set via configure(), defaults match previous hardcoded values
    private var connectTimeout: TimeInterval = 30.0
    private var discoverServicesTimeout: TimeInterval = 15.0
    private var readCharacteristicTimeout: TimeInterval = 10.0
    private var writeCharacteristicTimeout: TimeInterval = 10.0
    private var readDescriptorTimeout: TimeInterval = 10.0
    private var writeDescriptorTimeout: TimeInterval = 10.0
    private var readRssiTimeout: TimeInterval = 5.0

    // Service discovery tracking
    private var pendingServiceDiscovery: [String: Set<String>] = [:] // [deviceId: Set<serviceUuid>] - services waiting for characteristics
    private var pendingCharacteristicDiscovery: [String: Set<String>] = [:] // [deviceId: Set<charUuid>] - characteristics waiting for descriptors

    init(messenger: FlutterBinaryMessenger) {
        flutterApi = BlueyFlutterApi(binaryMessenger: messenger)
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        centralManager.delegate = centralManagerDelegate
    }

    // MARK: - Configuration

    func configure(config: BlueyConfigDto) {
        if let ms = config.discoverServicesTimeoutMs {
            discoverServicesTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.readCharacteristicTimeoutMs {
            readCharacteristicTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.writeCharacteristicTimeoutMs {
            writeCharacteristicTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.readDescriptorTimeoutMs {
            readDescriptorTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.writeDescriptorTimeoutMs {
            writeDescriptorTimeout = TimeInterval(ms) / 1000.0
        }
        if let ms = config.readRssiTimeoutMs {
            readRssiTimeout = TimeInterval(ms) / 1000.0
        }
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
            completion(.failure(BlueyError.unknown.toClientPigeonError()))
            return
        }
        UIApplication.shared.open(url) { success in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(BlueyError.unknown.toClientPigeonError()))
            }
        }
        #else
        completion(.failure(BlueyError.unsupported.toClientPigeonError()))
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
            completion(.failure(BlueyError.notFound.toClientPigeonError()))
            return
        }

        let timeoutSeconds = config.timeoutMs != nil
            ? TimeInterval(config.timeoutMs!) / 1000.0
            : connectTimeout

        let slot = connectSlots[deviceId] ?? OpSlot<Void>()
        connectSlots[deviceId] = slot
        slot.enqueue(
            completion: { [weak self] result in
                switch result {
                case .success:
                    completion(.success(deviceId))
                case .failure(let err):
                    // Cancel the underlying CoreBluetooth attempt only if
                    // the peripheral isn't already connected. Stacked
                    // connects could queue behind a successful head; if
                    // such a queued entry later times out, we must not
                    // tear down the live connection belonging to the
                    // caller that already got its success.
                    if let manager = self?.centralManager,
                       peripheral.state != .connected {
                        manager.cancelPeripheralConnection(peripheral)
                    }
                    completion(.failure(err))
                }
            },
            timeoutSeconds: timeoutSeconds,
            makeTimeoutError: BlueyError.timeout.toClientPigeonError()
        )
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(deviceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let peripheral = peripherals[deviceId] else {
            completion(.failure(BlueyError.notFound.toClientPigeonError()))
            return
        }

        let slot = disconnectSlots[deviceId] ?? OpSlot<Void>()
        disconnectSlots[deviceId] = slot
        slot.enqueue(
            completion: completion,
            timeoutSeconds: 30.0,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Disconnect timed out", details: nil)
        )
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Service Discovery

    func discoverServices(deviceId: String, completion: @escaping (Result<[ServiceDto], Error>) -> Void) {
        guard let peripheral = peripherals[deviceId] else {
            completion(.failure(BlueyError.notFound.toClientPigeonError()))
            return
        }

        guard peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let slot = discoverServicesSlots[deviceId] ?? OpSlot<[ServiceDto]>()
        discoverServicesSlots[deviceId] = slot
        slot.enqueue(
            completion: { [weak self] result in
                // Clear per-discovery tracking regardless of outcome so a
                // subsequent call starts fresh.
                self?.pendingServiceDiscovery.removeValue(forKey: deviceId)
                self?.pendingCharacteristicDiscovery.removeValue(forKey: deviceId)
                completion(result)
            },
            timeoutSeconds: discoverServicesTimeout,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Service discovery timed out", details: nil)
        )
        peripheral.discoverServices(nil)
    }

    // MARK: - Characteristic Operations

    func readCharacteristic(deviceId: String, characteristicHandle: Int64, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        guard let characteristic = handleStore.characteristicByHandle[deviceId]?[Int(characteristicHandle)] else {
            completion(.failure(BlueyError.handleInvalidated.toClientPigeonError()))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let cacheKey = characteristic.uuid.uuidString.lowercased()
        let slot = readCharacteristicSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<FlutterStandardTypedData>()
        readCharacteristicSlots[deviceId, default: [:]][cacheKey] = slot
        slot.enqueue(
            completion: completion,
            timeoutSeconds: readCharacteristicTimeout,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Read characteristic timed out", details: nil)
        )
        peripheral.readValue(for: characteristic)
    }

    func writeCharacteristic(deviceId: String, characteristicHandle: Int64, value: FlutterStandardTypedData, withResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let characteristic = handleStore.characteristicByHandle[deviceId]?[Int(characteristicHandle)] else {
            completion(.failure(BlueyError.handleInvalidated.toClientPigeonError()))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse

        if withResponse {
            let cacheKey = characteristic.uuid.uuidString.lowercased()
            let slot = writeCharacteristicSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<Void>()
            writeCharacteristicSlots[deviceId, default: [:]][cacheKey] = slot
            slot.enqueue(
                completion: completion,
                timeoutSeconds: writeCharacteristicTimeout,
                makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Write characteristic timed out", details: nil)
            )
        }

        peripheral.writeValue(value.data, for: characteristic, type: type)

        if !withResponse {
            completion(.success(()))
        }
    }

    func setNotification(deviceId: String, characteristicHandle: Int64, enable: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let characteristic = handleStore.characteristicByHandle[deviceId]?[Int(characteristicHandle)] else {
            completion(.failure(BlueyError.handleInvalidated.toClientPigeonError()))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let cacheKey = characteristic.uuid.uuidString.lowercased()
        let slot = notifySlots[deviceId, default: [:]][cacheKey] ?? OpSlot<Void>()
        notifySlots[deviceId, default: [:]][cacheKey] = slot
        slot.enqueue(
            completion: completion,
            timeoutSeconds: 10.0,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Set notification timed out", details: nil)
        )
        peripheral.setNotifyValue(enable, for: characteristic)
    }

    // MARK: - Descriptor Operations

    func readDescriptor(deviceId: String, characteristicHandle: Int64, descriptorHandle: Int64, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        guard let descriptor = handleStore.descriptorByHandle[deviceId]?[Int(descriptorHandle)] else {
            completion(.failure(BlueyError.handleInvalidated.toClientPigeonError()))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let cacheKey = descriptor.uuid.uuidString.lowercased()
        let slot = readDescriptorSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<FlutterStandardTypedData>()
        readDescriptorSlots[deviceId, default: [:]][cacheKey] = slot
        slot.enqueue(
            completion: completion,
            timeoutSeconds: readDescriptorTimeout,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Read descriptor timed out", details: nil)
        )
        peripheral.readValue(for: descriptor)
    }

    func writeDescriptor(deviceId: String, characteristicHandle: Int64, descriptorHandle: Int64, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let descriptor = handleStore.descriptorByHandle[deviceId]?[Int(descriptorHandle)] else {
            completion(.failure(BlueyError.handleInvalidated.toClientPigeonError()))
            return
        }

        guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let cacheKey = descriptor.uuid.uuidString.lowercased()
        let slot = writeDescriptorSlots[deviceId, default: [:]][cacheKey] ?? OpSlot<Void>()
        writeDescriptorSlots[deviceId, default: [:]][cacheKey] = slot
        slot.enqueue(
            completion: completion,
            timeoutSeconds: writeDescriptorTimeout,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "Write descriptor timed out", details: nil)
        )
        peripheral.writeValue(value.data, for: descriptor)
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
            completion(.failure(BlueyError.notConnected.toClientPigeonError()))
            return
        }

        let slot = readRssiSlots[deviceId] ?? OpSlot<Int64>()
        readRssiSlots[deviceId] = slot
        slot.enqueue(
            completion: completion,
            timeoutSeconds: readRssiTimeout,
            makeTimeoutError: PigeonError(code: "gatt-timeout", message: "RSSI read timed out", details: nil)
        )
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
        connectSlots[deviceId]?.completeHead(.success(()))
    }

    func didFailToConnect(central: CBCentralManager, peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        let err: Error = (error as? NSError)?.toPigeonError()
            ?? BlueyError.unknown.toClientPigeonError()
        connectSlots[deviceId]?.completeHead(.failure(err))
    }

    func didDisconnectPeripheral(central: CBCentralManager, peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Clear caches
        services.removeValue(forKey: deviceId)
        characteristics.removeValue(forKey: deviceId)
        descriptors.removeValue(forKey: deviceId)

        // I088 — drop the per-device handle table. CB does not
        // guarantee object identity preservation across reconnect,
        // so handles minted from the previous session must not
        // outlive the link.
        handleStore.clear(for: deviceId)

        // Clear pending discovery state
        pendingServiceDiscovery.removeValue(forKey: deviceId)
        pendingCharacteristicDiscovery.removeValue(forKey: deviceId)

        // Pop the head of any user-initiated disconnect BEFORE draining
        // other slots, so the caller that invoked `disconnect()` gets
        // success (not the `gatt-disconnected` drain error). We do NOT
        // remove the slot from the map here; any additional queued
        // disconnect entries are drained by `clearPendingCompletions`
        // below so no completion is orphaned.
        if let disconnectSlot = disconnectSlots[deviceId], !disconnectSlot.isEmpty {
            if let nsError = error as? NSError {
                disconnectSlot.completeHead(.failure(nsError.toPigeonError()))
            } else {
                disconnectSlot.completeHead(.success(()))
            }
        }

        // Drain all remaining pending completions with the disconnect error.
        // iOS reports nil error for graceful disconnects: peer-initiated
        // clean shutdown, or our own cancelPeripheralConnection (e.g.
        // LifecycleClient declared the peer unreachable). The link is gone
        // either way; map to gatt-disconnected so callers (LifecycleClient,
        // example-app reconnect cubit) recognise the dead-peer signal.
        // Falling through to BlueyError.unknown was wrong — see I096.
        let pigeonError: Error
        if let nsError = error as? NSError {
            pigeonError = nsError.toPigeonError()
        } else {
            pigeonError = PigeonError(code: "gatt-disconnected",
                                      message: "Peripheral disconnected",
                                      details: nil)
        }
        clearPendingCompletions(for: deviceId, error: pigeonError)

        // Notify connection state change
        let event = ConnectionStateEventDto(deviceId: deviceId, state: .disconnected)
        flutterApi.onConnectionStateChanged(event: event) { _ in }
    }

    // MARK: - CBPeripheralDelegate callbacks

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Check if we have a pending completion - if not, this might be a re-discovery
        guard let slot = discoverServicesSlots[deviceId], !slot.isEmpty else {
            return
        }

        if let nsError = error as? NSError {
            slot.completeHead(.failure(nsError.toPigeonError()))
            return
        }

        let cbServices = peripheral.services ?? []

        // If no services, complete immediately
        if cbServices.isEmpty {
            slot.completeHead(.success([]))
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

            // I088 — mint a per-device handle for this characteristic
            // and store it. Subsequent DTO mapping looks up this
            // handle by reference identity. Idempotency: only mint
            // if we haven't already seen this exact characteristic
            // object (CB returns the same reference across callbacks
            // for the same attribute). This guards against multiple
            // didDiscoverCharacteristicsFor for the same service —
            // they're rare but possible after re-discovery races.
            if handleStore.handleForCharacteristic(characteristic, deviceId: deviceId) == nil {
                handleStore.recordCharacteristic(characteristic, for: deviceId)
            }

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

                // I088 — mint a handle for this descriptor from the
                // same per-device counter as characteristics, so
                // descriptor handles continue from where chars left
                // off in encounter order. Idempotency same as for
                // characteristics: skip if we've seen this exact
                // descriptor object before.
                if handleStore.handleForDescriptor(descriptor, deviceId: deviceId) == nil {
                    handleStore.recordDescriptor(descriptor, for: deviceId)
                }
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

        // Build the final service DTOs with all discovered characteristics and descriptors.
        // I088 — DTO mapping reverse-looks-up minted handles from
        // `handleStore` so each CharacteristicDto / DescriptorDto
        // carries the handle Dart will address it by.
        let cbServices = peripheral.services ?? []
        var serviceDtos: [ServiceDto] = []

        for service in cbServices {
            serviceDtos.append(mapServiceWithHandles(service: service, deviceId: deviceId))
        }

        discoverServicesSlots[deviceId]?.completeHead(.success(serviceDtos))
    }

    /// I088 — DTO mapping that emits minted handles. Mirrors
    /// `CBService.toDto()` but uses `handleStore` for handle
    /// reverse-lookup. We keep `toDto()` (handle-less) intact for
    /// any callers that don't need handles; D.8/D.13 retire that
    /// fallback path.
    private func mapServiceWithHandles(service: CBService, deviceId: String) -> ServiceDto {
        let uuid = service.uuid.uuidString.lowercased()
        let chars = (service.characteristics ?? []).map { mapCharacteristicWithHandle(characteristic: $0, deviceId: deviceId) }
        let included = (service.includedServices ?? []).map { mapServiceWithHandles(service: $0, deviceId: deviceId) }
        return ServiceDto(
            uuid: uuid,
            isPrimary: service.isPrimary,
            characteristics: chars,
            includedServices: included
        )
    }

    private func mapCharacteristicWithHandle(characteristic: CBCharacteristic, deviceId: String) -> CharacteristicDto {
        let uuid = characteristic.uuid.uuidString.lowercased()
        let props = characteristic.properties
        let propertiesDto = CharacteristicPropertiesDto(
            canRead: props.contains(.read),
            canWrite: props.contains(.write),
            canWriteWithoutResponse: props.contains(.writeWithoutResponse),
            canNotify: props.contains(.notify),
            canIndicate: props.contains(.indicate)
        )
        let descs = (characteristic.descriptors ?? []).map { mapDescriptorWithHandle(descriptor: $0, deviceId: deviceId) }
        // I088 D.13 — handle is non-nullable on the wire. We mint at
        // discovery time so the lookup always succeeds; defensive 0
        // for the impossible case.
        let handle = Int64(handleStore.handleForCharacteristic(characteristic, deviceId: deviceId) ?? 0)
        return CharacteristicDto(
            uuid: uuid,
            properties: propertiesDto,
            descriptors: descs,
            handle: handle
        )
    }

    private func mapDescriptorWithHandle(descriptor: CBDescriptor, deviceId: String) -> DescriptorDto {
        let uuid = descriptor.uuid.uuidString.lowercased()
        let handle = Int64(handleStore.handleForDescriptor(descriptor, deviceId: deviceId) ?? 0)
        return DescriptorDto(uuid: uuid, handle: handle)
    }

    func didUpdateCharacteristicValue(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        // Check if this was a read request (slot has pending entries)
        if let slot = readCharacteristicSlots[deviceId]?[charUuid], !slot.isEmpty {
            if let nsError = error as? NSError {
                slot.completeHead(.failure(nsError.toPigeonError()))
            } else {
                let value = characteristic.value ?? Data()
                slot.completeHead(.success(FlutterStandardTypedData(bytes: value)))
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

        guard let slot = writeCharacteristicSlots[deviceId]?[charUuid] else {
            return
        }

        if let nsError = error as? NSError {
            slot.completeHead(.failure(nsError.toPigeonError()))
        } else {
            slot.completeHead(.success(()))
        }
    }

    func didUpdateNotificationState(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()

        guard let slot = notifySlots[deviceId]?[charUuid] else {
            return
        }

        if let nsError = error as? NSError {
            slot.completeHead(.failure(nsError.toPigeonError()))
        } else {
            slot.completeHead(.success(()))
        }
    }

    func didUpdateDescriptorValue(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let descUuid = descriptor.uuid.uuidString.lowercased()

        guard let slot = readDescriptorSlots[deviceId]?[descUuid] else {
            return
        }

        if let nsError = error as? NSError {
            slot.completeHead(.failure(nsError.toPigeonError()))
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
            slot.completeHead(.success(FlutterStandardTypedData(bytes: value)))
        }
    }

    func didWriteDescriptorValue(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()
        let descUuid = descriptor.uuid.uuidString.lowercased()

        guard let slot = writeDescriptorSlots[deviceId]?[descUuid] else {
            return
        }

        if let nsError = error as? NSError {
            slot.completeHead(.failure(nsError.toPigeonError()))
        } else {
            slot.completeHead(.success(()))
        }
    }

    func didModifyServices(peripheral: CBPeripheral, invalidatedServices: [CBService]) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        // Clear cached services for this device so the next discovery is fresh
        services.removeValue(forKey: deviceId)
        characteristics.removeValue(forKey: deviceId)
        descriptors.removeValue(forKey: deviceId)

        // I088 — Service Changed invalidates the attribute layout;
        // drop minted handles before notifying Dart so any lookup
        // that races the change can't resolve to a stale entry.
        handleStore.clear(for: deviceId)

        flutterApi.onServicesChanged(deviceId: deviceId) { _ in }
    }

    func didReadRSSI(peripheral: CBPeripheral, rssi: NSNumber, error: Error?) {
        let deviceId = peripheral.identifier.uuidString.lowercased()

        guard let slot = readRssiSlots[deviceId] else {
            return
        }

        if let nsError = error as? NSError {
            slot.completeHead(.failure(nsError.toPigeonError()))
        } else {
            slot.completeHead(.success(rssi.int64Value))
        }
    }

    // MARK: - Helpers

    private func clearPendingCompletions(for deviceId: String, error: Error) {
        // Drain all per-(device, key) slot maps — each OpSlot cancels its
        // own timers and fires all pending completions with the error.
        connectSlots.removeValue(forKey: deviceId)?.drainAll(error)
        disconnectSlots.removeValue(forKey: deviceId)?.drainAll(error)
        discoverServicesSlots.removeValue(forKey: deviceId)?.drainAll(error)
        readRssiSlots.removeValue(forKey: deviceId)?.drainAll(error)

        if let slots = readCharacteristicSlots.removeValue(forKey: deviceId) {
            for (_, slot) in slots {
                slot.drainAll(error)
            }
        }
        if let slots = writeCharacteristicSlots.removeValue(forKey: deviceId) {
            for (_, slot) in slots {
                slot.drainAll(error)
            }
        }
        if let slots = notifySlots.removeValue(forKey: deviceId) {
            for (_, slot) in slots {
                slot.drainAll(error)
            }
        }
        if let slots = readDescriptorSlots.removeValue(forKey: deviceId) {
            for (_, slot) in slots {
                slot.drainAll(error)
            }
        }
        if let slots = writeDescriptorSlots.removeValue(forKey: deviceId) {
            for (_, slot) in slots {
                slot.drainAll(error)
            }
        }
    }
}
