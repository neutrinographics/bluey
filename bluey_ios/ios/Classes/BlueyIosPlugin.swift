import Flutter
import UIKit

public class BlueyIosPlugin: NSObject, FlutterPlugin {
    private var centralManager: CentralManagerImpl?
    private var peripheralManager: PeripheralManagerImpl?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let instance = BlueyIosPlugin()

        // Initialize managers
        instance.centralManager = CentralManagerImpl(messenger: messenger)
        instance.peripheralManager = PeripheralManagerImpl(messenger: messenger)

        // Set up the Host API
        let hostApi = BlueyHostApiImpl(
            centralManager: instance.centralManager!,
            peripheralManager: instance.peripheralManager!
        )
        BlueyHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
    }
}

/// Implementation of the Host API that bridges Dart calls to Swift.
class BlueyHostApiImpl: BlueyHostApi {
    private let centralManager: CentralManagerImpl
    private let peripheralManager: PeripheralManagerImpl

    init(centralManager: CentralManagerImpl, peripheralManager: PeripheralManagerImpl) {
        self.centralManager = centralManager
        self.peripheralManager = peripheralManager
    }

    // MARK: - Configuration

    func configure(config: BlueyConfigDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.configure(config: config)
        completion(.success(()))
    }

    // MARK: - State

    func getState(completion: @escaping (Result<BluetoothStateDto, any Error>) -> Void) {
        let state = centralManager.getState()
        completion(.success(state))
    }

    func authorize(completion: @escaping (Result<Bool, any Error>) -> Void) {
        centralManager.authorize(completion: completion)
    }

    func openSettings(completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.openSettings(completion: completion)
    }

    // MARK: - Scanning

    func startScan(config: ScanConfigDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.startScan(config: config, completion: completion)
    }

    func stopScan(completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.stopScan(completion: completion)
    }

    // MARK: - Connection

    func connect(deviceId: String, config: ConnectConfigDto, completion: @escaping (Result<String, any Error>) -> Void) {
        centralManager.connect(deviceId: deviceId, config: config, completion: completion)
    }

    func disconnect(deviceId: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.disconnect(deviceId: deviceId, completion: completion)
    }

    // MARK: - GATT Operations

    func discoverServices(deviceId: String, completion: @escaping (Result<[ServiceDto], any Error>) -> Void) {
        centralManager.discoverServices(deviceId: deviceId, completion: completion)
    }

    func readCharacteristic(deviceId: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, any Error>) -> Void) {
        centralManager.readCharacteristic(deviceId: deviceId, characteristicUuid: characteristicUuid, completion: completion)
    }

    func writeCharacteristic(deviceId: String, characteristicUuid: String, value: FlutterStandardTypedData, withResponse: Bool, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.writeCharacteristic(deviceId: deviceId, characteristicUuid: characteristicUuid, value: value, withResponse: withResponse, completion: completion)
    }

    func setNotification(deviceId: String, characteristicUuid: String, enable: Bool, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.setNotification(deviceId: deviceId, characteristicUuid: characteristicUuid, enable: enable, completion: completion)
    }

    func readDescriptor(deviceId: String, descriptorUuid: String, completion: @escaping (Result<FlutterStandardTypedData, any Error>) -> Void) {
        centralManager.readDescriptor(deviceId: deviceId, descriptorUuid: descriptorUuid, completion: completion)
    }

    func writeDescriptor(deviceId: String, descriptorUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.writeDescriptor(deviceId: deviceId, descriptorUuid: descriptorUuid, value: value, completion: completion)
    }

    func getMaximumWriteLength(deviceId: String, withResponse: Bool) throws -> Int64 {
        return centralManager.getMaximumWriteLength(deviceId: deviceId, withResponse: withResponse)
    }

    func readRssi(deviceId: String, completion: @escaping (Result<Int64, any Error>) -> Void) {
        centralManager.readRssi(deviceId: deviceId, completion: completion)
    }

    // MARK: - Server (Peripheral) Operations

    func addService(service: LocalServiceDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.addService(service: service, completion: completion)
    }

    func removeService(serviceUuid: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.removeService(serviceUuid: serviceUuid, completion: completion)
    }

    func startAdvertising(config: AdvertiseConfigDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.startAdvertising(config: config, completion: completion)
    }

    func stopAdvertising(completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.stopAdvertising(completion: completion)
    }

    func notifyCharacteristic(characteristicUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.notifyCharacteristic(characteristicUuid: characteristicUuid, value: value, completion: completion)
    }

    func notifyCharacteristicTo(centralId: String, characteristicUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.notifyCharacteristicTo(centralId: centralId, characteristicUuid: characteristicUuid, value: value, completion: completion)
    }

    func respondToReadRequest(requestId: Int64, status: GattStatusDto, value: FlutterStandardTypedData?, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.respondToReadRequest(requestId: Int(requestId), status: status, value: value, completion: completion)
    }

    func respondToWriteRequest(requestId: Int64, status: GattStatusDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.respondToWriteRequest(requestId: Int(requestId), status: status, completion: completion)
    }

    func disconnectCentral(centralId: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.disconnectCentral(centralId: centralId, completion: completion)
    }

    func closeServer(completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.closeServer(completion: completion)
    }
}
