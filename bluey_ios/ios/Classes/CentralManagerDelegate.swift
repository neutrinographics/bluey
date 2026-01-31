import Foundation
import CoreBluetooth

/// Delegate for CBCentralManager events.
class CentralManagerDelegate: NSObject, CBCentralManagerDelegate {
    weak var manager: CentralManagerImpl?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        manager?.didUpdateState(central: central)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        manager?.didDiscover(central: central, peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        manager?.didConnect(central: central, peripheral: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        manager?.didFailToConnect(central: central, peripheral: peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        manager?.didDisconnectPeripheral(central: central, peripheral: peripheral, error: error)
    }
}
