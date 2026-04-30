import Flutter
import UIKit

public class BlueyIosPlugin: NSObject, FlutterPlugin {
    private var centralManager: CentralManagerImpl?
    private var peripheralManager: PeripheralManagerImpl?
    private var logFlutterApi: BlueyFlutterApi?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let instance = BlueyIosPlugin()

        // Initialize managers
        instance.centralManager = CentralManagerImpl(messenger: messenger)
        instance.peripheralManager = PeripheralManagerImpl(messenger: messenger)

        // Bind structured logger to the Pigeon FlutterApi so native log
        // events are forwarded to Dart's logEvents stream (I307).
        instance.logFlutterApi = BlueyFlutterApi(binaryMessenger: messenger)
        BlueyLog.shared.bind(instance.logFlutterApi!)
        BlueyLog.shared.log(.info, "bluey.ios.plugin", "plugin attached")

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

    func readCharacteristic(deviceId: String, characteristicHandle: Int64, completion: @escaping (Result<FlutterStandardTypedData, any Error>) -> Void) {
        centralManager.readCharacteristic(deviceId: deviceId, characteristicHandle: characteristicHandle, completion: completion)
    }

    func writeCharacteristic(deviceId: String, characteristicHandle: Int64, value: FlutterStandardTypedData, withResponse: Bool, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.writeCharacteristic(deviceId: deviceId, characteristicHandle: characteristicHandle, value: value, withResponse: withResponse, completion: completion)
    }

    func setNotification(deviceId: String, characteristicHandle: Int64, enable: Bool, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.setNotification(deviceId: deviceId, characteristicHandle: characteristicHandle, enable: enable, completion: completion)
    }

    func readDescriptor(deviceId: String, characteristicHandle: Int64, descriptorHandle: Int64, completion: @escaping (Result<FlutterStandardTypedData, any Error>) -> Void) {
        centralManager.readDescriptor(deviceId: deviceId, characteristicHandle: characteristicHandle, descriptorHandle: descriptorHandle, completion: completion)
    }

    func writeDescriptor(deviceId: String, characteristicHandle: Int64, descriptorHandle: Int64, value: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        centralManager.writeDescriptor(deviceId: deviceId, characteristicHandle: characteristicHandle, descriptorHandle: descriptorHandle, value: value, completion: completion)
    }

    func getMaximumWriteLength(deviceId: String, withResponse: Bool) throws -> Int64 {
        return centralManager.getMaximumWriteLength(deviceId: deviceId, withResponse: withResponse)
    }

    func readRssi(deviceId: String, completion: @escaping (Result<Int64, any Error>) -> Void) {
        centralManager.readRssi(deviceId: deviceId, completion: completion)
    }

    // MARK: - Server (Peripheral) Operations

    func addService(service: LocalServiceDto, completion: @escaping (Result<LocalServiceDto, any Error>) -> Void) {
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

    func notifyCharacteristic(characteristicHandle: Int64, value: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.notifyCharacteristic(characteristicHandle: characteristicHandle, value: value, completion: completion)
    }

    func notifyCharacteristicTo(centralId: String, characteristicHandle: Int64, value: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.notifyCharacteristicTo(centralId: centralId, characteristicHandle: characteristicHandle, value: value, completion: completion)
    }

    func respondToReadRequest(requestId: Int64, status: GattStatusDto, value: FlutterStandardTypedData?, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.respondToReadRequest(requestId: Int(requestId), status: status, value: value, completion: completion)
    }

    func respondToWriteRequest(requestId: Int64, status: GattStatusDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.respondToWriteRequest(requestId: Int(requestId), status: status, completion: completion)
    }

    func closeServer(completion: @escaping (Result<Void, any Error>) -> Void) {
        peripheralManager.closeServer(completion: completion)
    }

    // MARK: - Logging (I307)

    func setLogLevel(level: LogLevelDto, completion: @escaping (Result<Void, any Error>) -> Void) {
        BlueyLog.shared.setLevel(level)
        completion(.success(()))
    }
}
