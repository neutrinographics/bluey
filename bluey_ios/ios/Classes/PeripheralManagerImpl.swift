import Foundation
import CoreBluetooth
import Flutter

// Pattern B — the dedicated Bluey lifecycle presence characteristic.
// A central unsubscribing from THIS characteristic is treated as a
// real client disconnect (see `didUnsubscribe`). Must match the Dart
// constant exactly. (File-scope because generic types cannot hold
// static stored properties.)
private let presenceCharUuid = "b1e70005-0000-1000-8000-00805f9b34fb"

/// Implementation of the Peripheral (server) role BLE operations.
///
/// Generic over [PeripheralManaging] (audit R5): production binds
/// `CBPeripheralManager` via the `PeripheralManagerImpl` subclass below;
/// tests bind an instantiable fake and drive full delegate sequences.
class PeripheralManagerImplCore<Manager: PeripheralManaging>: NSObject {

    private let flutterApi: BlueyFlutterApiProtocol
    let peripheralManager: Manager

    // Added services
    private var services: [String: CBMutableService] = [:] // [serviceUuid: service]

    // I088 D.13 — handle-keyed store for the server role. Module-wide
    // counter (only one local server). Replaces the legacy UUID-keyed
    // `characteristics` map: every notify / indicate / request DTO
    // is addressed by handle.
    //
    // Stored as `CBCharacteristic` (parent type of
    // `CBMutableCharacteristic`) so reverse-lookup at
    // `didReceiveRead` / `didReceiveWrite` — where CB hands us a
    // `CBCharacteristic` — can compare by reference identity without
    // a downcast. CB returns the same reference for a given
    // attribute across callbacks, so identity matching is reliable.
    private let handleStore = PeripheralHandleStore<CBCharacteristic>()

    // I040 — FIFO queue for notifications deferred by iOS's
    // `updateValue` returning `false` (TX queue full). Drained by
    // `peripheralManagerIsReady(toUpdateSubscribers:)`.
    private let pendingNotifications =
        PendingNotificationQueue<CBMutableCharacteristic, Manager.Central>()

    // Subscribed centrals per characteristic
    private var subscribedCentrals: [String: Set<String>] = [:] // [charUuid: Set<centralId>]

    // Connected centrals
    private var centrals: [String: Manager.Central] = [:] // [centralId: central]

    // Pending ATT requests
    private var pendingReadRequests: [Int: Manager.Request] = [:]
    private var pendingWriteRequests: [Int: [Manager.Request]] = [:]
    private var nextRequestId: Int = 0

    // Completion handlers
    private var addServiceCompletions: [String: (Result<LocalServiceDto, Error>) -> Void] = [:]
    /// Populated LocalServiceDto (handles stamped) per pending serviceUuid.
    private var addServicePopulated: [String: LocalServiceDto] = [:]
    private var startAdvertisingCompletion: ((Result<Void, Error>) -> Void)?

    init(flutterApi: BlueyFlutterApiProtocol, manager: Manager) {
        self.flutterApi = flutterApi
        self.peripheralManager = manager
        super.init()
    }

    // MARK: - Readiness gate (I333)

    // I333 — symmetric backstop to Android's `DeadObjectException`
    // translation. CoreBluetooth calls against a `CBPeripheralManager`
    // whose `state != .poweredOn` silently no-op (worst-case: the
    // consumer's `Future` hangs forever). Every public server op
    // short-circuits with `BlueyError.notReady.toServerPigeonError()`
    // (Pigeon code `bluetooth-unavailable`, surfaces Dart-side as
    // `BluetoothUnavailableException`) when the manager is not
    // powered on. All current server ops use completion handlers, so
    // the gate is inlined at op entry rather than via a `throws`
    // helper; see `CentralManagerImpl.requireReady()` for the
    // throwing variant used by `getMaximumWriteLength`.

    // MARK: - Service Management

    func addService(service: LocalServiceDto, completion: @escaping (Result<LocalServiceDto, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        let mutableService = service.toMutableService()
        let serviceUuid = service.uuid.lowercased()
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "addService",
                            data: ["serviceUuid": serviceUuid,
                                   "characteristicCount": service.characteristics.count])

        // I088 D.13 — mint handles in lock-step with the DTO order so
        // we can return a populated LocalServiceDto with handles
        // stamped for every characteristic / descriptor. The DTO order
        // matches `toMutableService`'s build order, so a positional
        // walk is exact.
        let mutableChars = mutableService.characteristics ?? []
        var populatedChars: [LocalCharacteristicDto] = []
        for (idx, charDto) in service.characteristics.enumerated() {
            let mutableChar = mutableChars[idx] as! CBMutableCharacteristic
            let handle = handleStore.recordCharacteristic(mutableChar)
            // Descriptor handles are minted per characteristic from a
            // local counter starting at 1, mirroring the central side.
            var nextDesc: Int64 = 1
            let populatedDescs = charDto.descriptors.map { d -> LocalDescriptorDto in
                let h = nextDesc
                nextDesc += 1
                return LocalDescriptorDto(
                    uuid: d.uuid,
                    permissions: d.permissions,
                    value: d.value,
                    handle: h
                )
            }
            populatedChars.append(LocalCharacteristicDto(
                uuid: charDto.uuid,
                properties: charDto.properties,
                permissions: charDto.permissions,
                descriptors: populatedDescs,
                handle: Int64(handle)
            ))
        }
        let populated = LocalServiceDto(
            uuid: service.uuid,
            isPrimary: service.isPrimary,
            characteristics: populatedChars,
            includedServices: service.includedServices
        )

        services[serviceUuid] = mutableService
        addServiceCompletions[serviceUuid] = completion
        addServicePopulated[serviceUuid] = populated
        peripheralManager.add(mutableService)
    }

    func removeService(serviceUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        let uuid = serviceUuid.lowercased()
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "removeService",
                            data: ["serviceUuid": uuid])
        guard let service = services.removeValue(forKey: uuid) else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "removeService: not found",
                                data: ["serviceUuid": uuid], errorCode: "not-found")
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        // I088 D.13 — drop handle entries for this service's
        // characteristics. The handle-store counter does NOT reset
        // — once a handle has been issued it is never reused.
        var mutableCharsToRemove: [CBMutableCharacteristic] = []
        if let chars = service.characteristics {
            for char in chars {
                let charUuid = char.uuid.uuidString.lowercased()
                subscribedCentrals.removeValue(forKey: charUuid)
                if let mutableChar = char as? CBMutableCharacteristic {
                    mutableCharsToRemove.append(mutableChar)
                }
            }
            handleStore.removeCharacteristics(mutableCharsToRemove)
        }

        // I040 — fail-out any queued notifications targeting these
        // characteristics. Without this, the entries would sit in the
        // queue and head-of-line block subsequent drains (or get
        // silently consumed by iOS for handles that no longer exist).
        if !mutableCharsToRemove.isEmpty {
            pendingNotifications.failEntries(
                matching: { entry in
                    mutableCharsToRemove.contains { $0 === entry.characteristic }
                },
                error: BlueyError.handleInvalidated.toServerPigeonError()
            )
        }

        peripheralManager.remove(service)
        completion(.success(()))
    }

    // MARK: - Advertising

    func startAdvertising(config: AdvertiseConfigDto, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "startAdvertising",
                            data: ["serviceUuidCount": config.serviceUuids.count,
                                   "scanResponseServiceUuidCount": config.scanResponseServiceUuids.count,
                                   "hasName": config.name != nil])
        var advertisement: [String: Any] = [:]

        if let name = config.name {
            advertisement[CBAdvertisementDataLocalNameKey] = name
        }

        // I313: CoreBluetooth doesn't expose a separate scan-response slot.
        // We fold scanResponseServiceUuids into the unified advertisement
        // UUID list, prepending so the peer-discovery UUID retains
        // primary-slot priority via CoreBluetooth's overflow ordering. The
        // wire-level intent matches Android (where the same UUIDs go to
        // scan response): cross-platform scanners filtering on the
        // peer-discovery UUID see this peripheral.
        let combinedUuids = config.scanResponseServiceUuids + config.serviceUuids
        if !combinedUuids.isEmpty {
            advertisement[CBAdvertisementDataServiceUUIDsKey] = combinedUuids.map { $0.toCBUUID() }
        }

        // Note: iOS does not support manufacturer data in advertising
        // config.manufacturerDataCompanyId and config.manufacturerData are ignored

        startAdvertisingCompletion = completion
        peripheralManager.startAdvertising(advertisement)
    }

    func stopAdvertising(completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "stopAdvertising")
        peripheralManager.stopAdvertising()
        completion(.success(()))
    }

    // MARK: - Notifications

    func notifyCharacteristic(characteristicHandle: Int64, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "notifyCharacteristic (broadcast)",
                            data: ["characteristicHandle": characteristicHandle,
                                   "length": value.data.count])
        guard let characteristic = handleStore.characteristicByHandle[Int(characteristicHandle)] as? CBMutableCharacteristic else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "notifyCharacteristic: handle invalidated",
                                data: ["characteristicHandle": characteristicHandle],
                                errorCode: "handle-invalidated")
            completion(.failure(BlueyError.handleInvalidated.toServerPigeonError()))
            return
        }

        let success = peripheralManager.updateValue(value.data, for: characteristic, onSubscribedCentrals: nil)
        if success {
            completion(.success(()))
            return
        }

        // I040 — queue is full. Defer until isReadyToUpdateSubscribers fires.
        let entry = PendingNotificationQueue<CBMutableCharacteristic, Manager.Central>.Entry(
            characteristic: characteristic,
            data: value.data,
            central: nil,
            completion: completion
        )
        if pendingNotifications.enqueue(entry) {
            BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "notifyCharacteristic: deferred (queue full, will retry)",
                                data: ["characteristicHandle": characteristicHandle,
                                       "queueDepth": pendingNotifications.count])
        } else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "notifyCharacteristic: queue cap reached",
                                data: ["characteristicHandle": characteristicHandle,
                                       "queueDepth": pendingNotifications.count],
                                errorCode: "notify-queue-full")
            completion(.failure(BlueyError.unknown.toServerPigeonError()))
        }
    }

    func notifyCharacteristicTo(centralId: String, characteristicHandle: Int64, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "notifyCharacteristicTo (targeted)",
                            data: ["centralId": centralId,
                                   "characteristicHandle": characteristicHandle,
                                   "length": value.data.count])
        guard let characteristic = handleStore.characteristicByHandle[Int(characteristicHandle)] as? CBMutableCharacteristic else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "notifyCharacteristicTo: handle invalidated",
                                data: ["characteristicHandle": characteristicHandle],
                                errorCode: "handle-invalidated")
            completion(.failure(BlueyError.handleInvalidated.toServerPigeonError()))
            return
        }

        guard let central = centrals[centralId] else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "notifyCharacteristicTo: central not found",
                                data: ["centralId": centralId],
                                errorCode: "not-found")
            completion(.failure(BlueyError.notFound.toServerPigeonError()))
            return
        }

        let success = peripheralManager.updateValue(value.data, for: characteristic, onSubscribedCentrals: [central])
        if success {
            completion(.success(()))
            return
        }

        // I040 — queue is full. Defer until isReadyToUpdateSubscribers fires.
        let entry = PendingNotificationQueue<CBMutableCharacteristic, Manager.Central>.Entry(
            characteristic: characteristic,
            data: value.data,
            central: central,
            completion: completion
        )
        if pendingNotifications.enqueue(entry) {
            BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "notifyCharacteristicTo: deferred (queue full, will retry)",
                                data: ["centralId": centralId,
                                       "characteristicHandle": characteristicHandle,
                                       "queueDepth": pendingNotifications.count])
        } else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "notifyCharacteristicTo: queue cap reached",
                                data: ["centralId": centralId,
                                       "characteristicHandle": characteristicHandle,
                                       "queueDepth": pendingNotifications.count],
                                errorCode: "notify-queue-full")
            completion(.failure(BlueyError.unknown.toServerPigeonError()))
        }
    }

    // MARK: - Request Responses

    func respondToReadRequest(requestId: Int, status: GattStatusDto, value: FlutterStandardTypedData?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "respondToReadRequest",
                            data: ["requestId": requestId,
                                   "status": String(describing: status),
                                   "valueLength": value?.data.count ?? 0])
        guard let request = pendingReadRequests.removeValue(forKey: requestId) else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "respondToReadRequest: requestId not found",
                                data: ["requestId": requestId],
                                errorCode: "not-found")
            completion(.failure(BlueyError.pendingRequestNotFound.toServerPigeonError()))
            return
        }

        if let value = value {
            request.value = value.data
        }

        peripheralManager.respond(to: request, withResult: status.toCBATTError())
        completion(.success(()))
    }

    func respondToWriteRequest(requestId: Int, status: GattStatusDto, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheralManager.state == .poweredOn else {
            completion(.failure(BlueyError.notReady.toServerPigeonError()))
            return
        }
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "respondToWriteRequest",
                            data: ["requestId": requestId,
                                   "status": String(describing: status)])
        guard let requests = pendingWriteRequests.removeValue(forKey: requestId), let firstRequest = requests.first else {
            BlueyLog.shared.log(.warn, "bluey.ios.peripheral", "respondToWriteRequest: requestId not found",
                                data: ["requestId": requestId],
                                errorCode: "not-found")
            completion(.failure(BlueyError.pendingRequestNotFound.toServerPigeonError()))
            return
        }

        peripheralManager.respond(to: firstRequest, withResult: status.toCBATTError())
        completion(.success(()))
    }

    func closeServer(completion: @escaping (Result<Void, Error>) -> Void) {
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "closeServer",
                            data: ["serviceCount": services.count,
                                   "centralCount": centrals.count])
        // Stop advertising
        peripheralManager.stopAdvertising()

        // Remove all services
        peripheralManager.removeAllServices()

        // Clear caches. The handle-store's per-characteristic
        // entries are dropped via removeCharacteristics across all
        // remaining services so closeServer is symmetric with
        // removeService — counter still does NOT reset.
        // TODO(I083): Full handle-store reset on
        // peripheralManagerDidUpdateState(.poweredOff) is a separate
        // backlog item; not addressed here.
        var allChars: [CBMutableCharacteristic] = []
        for (_, service) in services {
            for char in service.characteristics ?? [] {
                if let mutableChar = char as? CBMutableCharacteristic {
                    allChars.append(mutableChar)
                }
            }
        }
        handleStore.removeCharacteristics(allChars)

        services.removeAll()
        subscribedCentrals.removeAll()
        centrals.removeAll()
        pendingReadRequests.removeAll()
        pendingWriteRequests.removeAll()

        // I040 — release any pending notification callers waiting on a
        // server that's now closed. Surfaces as
        // AttributeHandleInvalidatedException on the Dart side, matching
        // the post-removeService shape.
        pendingNotifications.failAll(
            error: BlueyError.handleInvalidated.toServerPigeonError()
        )

        completion(.success(()))
    }

    // MARK: - Central Tracking

    /// Tracks a central and notifies Flutter if this is the first time we see it.
    /// iOS does not provide a connection state callback, so we infer connections
    /// from subscribe, read, and write events.
    private func trackCentralIfNeeded(_ central: Manager.Central) {
        let centralId = central.identifier.uuidString.lowercased()
        let isNew = centrals[centralId] == nil
        centrals[centralId] = central

        if isNew {
            BlueyLog.shared.log(.info, "bluey.ios.peripheral", "central connected (inferred)",
                                data: ["centralId": centralId,
                                       "mtu": central.maximumUpdateValueLength])
            let centralDto = CentralDto(
                id: centralId, mtu: Int64(central.maximumUpdateValueLength))
            flutterApi.onCentralConnected(central: centralDto) { _ in }
        }
    }

    /// Re-announces every currently-tracked central to Dart by re-firing
    /// onCentralConnected with each central's known MTU. Lets a freshly-created
    /// BlueyServer re-establish sessions for centrals that survived a prior
    /// server instance (the native manager is reused across recreations)
    /// instead of evicting their next request (I338). Re-announce (not clear)
    /// preserves the negotiated MTU — `maximumUpdateValueLength` is read live
    /// from the retained `CBCentral`, the same source the connect-time announce
    /// in `trackCentralIfNeeded` uses.
    func reannounceTrackedCentrals() {
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "resetServerSessions",
                            data: ["centralCount": centrals.count])
        for (centralId, central) in centrals {
            let centralDto = CentralDto(
                id: centralId, mtu: Int64(central.maximumUpdateValueLength))
            flutterApi.onCentralConnected(central: centralDto) { _ in }
        }
    }

    // MARK: - CBPeripheralManagerDelegate callbacks

    func didUpdateState() {
        let stateDto = peripheralManager.state.toDto()
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "peripheralManagerDidUpdateState",
                            data: ["state": String(describing: stateDto)])
        flutterApi.onStateChanged(state: stateDto) { _ in }
    }

    func didAddService(service: CBService, error: Error?) {
        let serviceUuid = service.uuid.uuidString.lowercased()
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "didAddService",
                            data: ["serviceUuid": serviceUuid,
                                   "hasError": error != nil])

        guard let completion = addServiceCompletions.removeValue(forKey: serviceUuid) else {
            return
        }
        let populated = addServicePopulated.removeValue(forKey: serviceUuid)

        if let error = error {
            BlueyLog.shared.log(.error, "bluey.ios.peripheral", "didAddService failed",
                                data: ["serviceUuid": serviceUuid,
                                       "error": String(describing: error)],
                                errorCode: "add-service-failed")
            services.removeValue(forKey: serviceUuid)
            if let nsError = error as? NSError {
                completion(.failure(nsError.toPigeonError()))
            } else {
                completion(.failure(BlueyError.unknown.toServerPigeonError()))
            }
        } else if let populated = populated {
            completion(.success(populated))
        } else {
            completion(.failure(BlueyError.unknown.toServerPigeonError()))
        }
    }

    func didStartAdvertising(error: Error?) {
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "peripheralManagerDidStartAdvertising",
                            data: ["hasError": error != nil])
        guard let completion = startAdvertisingCompletion else {
            return
        }
        startAdvertisingCompletion = nil

        if let error = error {
            BlueyLog.shared.log(.error, "bluey.ios.peripheral", "didStartAdvertising failed",
                                data: ["error": String(describing: error)],
                                errorCode: "advertise-failed")
            if let nsError = error as? NSError {
                completion(.failure(nsError.toPigeonError()))
            } else {
                completion(.failure(BlueyError.unknown.toServerPigeonError()))
            }
        } else {
            completion(.success(()))
        }
    }

    func didSubscribe(central: Manager.Central, characteristic: CBCharacteristic) {
        let centralId = central.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "didSubscribeTo",
                            data: ["centralId": centralId,
                                   "characteristicUuid": charUuid])

        // Track the central and notify Flutter if this is the first time we see it
        trackCentralIfNeeded(central)

        // Track subscription
        subscribedCentrals[charUuid, default: []].insert(centralId)
        flutterApi.onCharacteristicSubscribed(centralId: centralId, characteristicUuid: charUuid) { _ in }
    }

    func didUnsubscribe(central: Manager.Central, characteristic: CBCharacteristic) {
        let centralId = central.identifier.uuidString.lowercased()
        let charUuid = characteristic.uuid.uuidString.lowercased()
        BlueyLog.shared.log(.info, "bluey.ios.peripheral", "didUnsubscribeFrom",
                            data: ["centralId": centralId,
                                   "characteristicUuid": charUuid])

        // Remove subscription
        subscribedCentrals[charUuid]?.remove(centralId)

        // Notify Flutter
        flutterApi.onCharacteristicUnsubscribed(centralId: centralId, characteristicUuid: charUuid) { _ in }

        // Pattern B: a central unsubscribing from the dedicated presence
        // characteristic means it disconnected (graceful, or a supervision-timeout
        // link loss) — the iOS server's real client-disconnect signal (I201 has no
        // native peripheral-side disconnect callback). Only the presence char
        // triggers this; a data-characteristic unsubscribe stays a no-op (a client
        // may toggle data notifications while staying connected).
        if charUuid == presenceCharUuid {
            centrals.removeValue(forKey: centralId)
            flutterApi.onCentralDisconnected(centralId: centralId) { _ in }
        }
    }

    func didReceiveRead(request: Manager.Request) {
        let centralId = request.central.identifier.uuidString.lowercased()
        let charUuid = request.characteristic.uuid.uuidString.lowercased()
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "didReceiveRead",
                            data: ["centralId": centralId,
                                   "characteristicUuid": charUuid,
                                   "offset": request.offset])

        // Track the central and notify Flutter if this is the first time we see it
        trackCentralIfNeeded(request.central)

        // Store request for later response
        let requestId = nextRequestId
        nextRequestId += 1
        pendingReadRequests[requestId] = request

        // I088 D.13 — handle is now non-nullable on the wire. Default
        // to 0 ("invalid handle") if reverse-lookup fails; the Dart
        // side will treat that as gatt-handle-invalidated.
        let handle = handleStore.handleForCharacteristic(request.characteristic)
        let requestDto = ReadRequestDto(
            requestId: Int64(requestId),
            centralId: centralId,
            characteristicUuid: charUuid,
            offset: Int64(request.offset),
            characteristicHandle: handle.map { Int64($0) } ?? 0
        )
        flutterApi.onReadRequest(request: requestDto) { _ in }
    }

    func didReceiveWrite(requests: [Manager.Request]) {
        guard let firstRequest = requests.first else { return }

        let centralId = firstRequest.central.identifier.uuidString.lowercased()
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "didReceiveWrite",
                            data: ["centralId": centralId,
                                   "requestCount": requests.count])

        // Track the central and notify Flutter if this is the first time we see it
        trackCentralIfNeeded(firstRequest.central)

        // Store requests for later response
        let requestId = nextRequestId
        nextRequestId += 1
        pendingWriteRequests[requestId] = requests

        // Notify Flutter for each request. I088 D.13 — handle is now
        // non-nullable on the wire; see matching note in didReceiveRead.
        for request in requests {
            let charUuid = request.characteristic.uuid.uuidString.lowercased()
            let value = request.value ?? Data()
            let handle = handleStore.handleForCharacteristic(request.characteristic)

            let requestDto = WriteRequestDto(
                requestId: Int64(requestId),
                centralId: centralId,
                characteristicUuid: charUuid,
                value: FlutterStandardTypedData(bytes: value),
                offset: Int64(request.offset),
                responseNeeded: true, // iOS always requires response for write requests received this way
                characteristicHandle: handle.map { Int64($0) } ?? 0
            )
            flutterApi.onWriteRequest(request: requestDto) { _ in }
        }
    }

    func isReadyToUpdateSubscribers() {
        let depthBefore = pendingNotifications.count
        BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "peripheralManagerIsReady toUpdateSubscribers",
                            data: ["queueDepthBefore": depthBefore])

        // I040 — drain deferred notifications in arrival order. Each
        // entry is re-attempted via `updateValue`; the first re-attempt
        // that returns `false` halts draining and waits for the next
        // ready callback.
        pendingNotifications.drain { entry in
            if let central = entry.central {
                return peripheralManager.updateValue(
                    entry.data,
                    for: entry.characteristic,
                    onSubscribedCentrals: [central]
                )
            } else {
                return peripheralManager.updateValue(
                    entry.data,
                    for: entry.characteristic,
                    onSubscribedCentrals: nil
                )
            }
        }

        if depthBefore > 0 {
            BlueyLog.shared.log(.debug, "bluey.ios.peripheral", "drained pending notifications",
                                data: ["queueDepthBefore": depthBefore,
                                       "queueDepthAfter": pendingNotifications.count])
        }
    }
}

/// Production binding: `PeripheralManagerImplCore` over the real
/// `CBPeripheralManager`, wired to the Pigeon Flutter API and the
/// CoreBluetooth delegate wrapper.
final class PeripheralManagerImpl: PeripheralManagerImplCore<CBPeripheralManager> {
    private let peripheralManagerDelegate = PeripheralManagerDelegate()

    init(messenger: FlutterBinaryMessenger) {
        let manager = CBPeripheralManager(delegate: nil, queue: nil)
        super.init(
            flutterApi: BlueyFlutterApi(binaryMessenger: messenger),
            manager: manager
        )
        peripheralManagerDelegate.manager = self
        manager.delegate = peripheralManagerDelegate
    }
}
