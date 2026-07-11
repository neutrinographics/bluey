import Foundation
import CoreBluetooth

/// Delegate for CBPeripheralManager events (GATT server).
class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate {
    weak var manager: PeripheralManagerImpl?

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        manager?.didUpdateState()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        manager?.didAddService(service: service, error: error)
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        manager?.didStartAdvertising(error: error)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        manager?.didSubscribe(central: central, characteristic: characteristic)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        manager?.didUnsubscribe(central: central, characteristic: characteristic)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        manager?.didReceiveRead(request: request)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        manager?.didReceiveWrite(requests: requests)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        manager?.isReadyToUpdateSubscribers()
    }
}
