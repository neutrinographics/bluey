import Foundation
import CoreBluetooth

// Seams over the CoreBluetooth server-role types (audit R5 / NT-3).
//
// CBCentral and CBATTRequest cannot be instantiated by client code, so
// the server logic in `PeripheralManagerImplCore` is generic over these
// protocols — the same pattern as `PendingNotificationQueue`'s type
// parameters and `OpSlot`'s `TimerFactory`. Production binds the
// CoreBluetooth types via the conformances below; tests bind
// instantiable fakes and drive full delegate sequences.

/// The subset of `CBCentral` the server role reads.
protocol CentralLike: AnyObject {
    var identifier: UUID { get }
    var maximumUpdateValueLength: Int { get }
}

extension CBCentral: CentralLike {}

/// The subset of `CBATTRequest` the server role reads and writes.
protocol ATTRequestLike: AnyObject {
    associatedtype CentralT: CentralLike
    var central: CentralT { get }
    var characteristic: CBCharacteristic { get }
    var offset: Int { get }
    var value: Data? { get set }
}

extension CBATTRequest: ATTRequestLike {
    typealias CentralT = CBCentral
}

/// The operations the server role performs against its
/// `CBPeripheralManager`.
protocol PeripheralManaging: AnyObject {
    associatedtype Central: CentralLike
    associatedtype Request: ATTRequestLike where Request.CentralT == Central

    var state: CBManagerState { get }
    func add(_ service: CBMutableService)
    func remove(_ service: CBMutableService)
    func removeAllServices()
    func startAdvertising(_ advertisementData: [String: Any]?)
    func stopAdvertising()
    func updateValue(
        _ value: Data,
        for characteristic: CBMutableCharacteristic,
        onSubscribedCentrals centrals: [Central]?
    ) -> Bool
    func respond(to request: Request, withResult result: CBATTError.Code)
}

extension CBPeripheralManager: PeripheralManaging {
    typealias Central = CBCentral
    typealias Request = CBATTRequest
}
