import Foundation
import CoreBluetooth

/// Delegate for CBPeripheral events (GATT operations).
class PeripheralDelegate: NSObject, CBPeripheralDelegate {
    weak var manager: CentralManagerImpl?

    // MARK: - Service Discovery

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        manager?.didDiscoverServices(peripheral: peripheral, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        manager?.didDiscoverIncludedServices(peripheral: peripheral, service: service, error: error)
    }

    // MARK: - Characteristic Discovery

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        manager?.didDiscoverCharacteristics(peripheral: peripheral, service: service, error: error)
    }

    // MARK: - Descriptor Discovery

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        manager?.didDiscoverDescriptors(peripheral: peripheral, characteristic: characteristic, error: error)
    }

    // MARK: - Reading Characteristic Values

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        manager?.didUpdateCharacteristicValue(peripheral: peripheral, characteristic: characteristic, error: error)
    }

    // MARK: - Writing Characteristic Values

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        manager?.didWriteCharacteristicValue(peripheral: peripheral, characteristic: characteristic, error: error)
    }

    // MARK: - Notifications

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        manager?.didUpdateNotificationState(peripheral: peripheral, characteristic: characteristic, error: error)
    }

    // MARK: - Reading Descriptor Values

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        manager?.didUpdateDescriptorValue(peripheral: peripheral, descriptor: descriptor, error: error)
    }

    // MARK: - Writing Descriptor Values

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        manager?.didWriteDescriptorValue(peripheral: peripheral, descriptor: descriptor, error: error)
    }

    // MARK: - RSSI

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        manager?.didReadRSSI(peripheral: peripheral, rssi: RSSI, error: error)
    }

    // MARK: - Service Changes

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        manager?.didModifyServices(peripheral: peripheral, invalidatedServices: invalidatedServices)
    }
}
