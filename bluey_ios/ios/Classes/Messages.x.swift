import Foundation
import CoreBluetooth
import Flutter

// MARK: - CoreBluetooth to DTO conversions

extension CBManagerState {
    func toDto() -> BluetoothStateDto {
        switch self {
        case .poweredOn:
            return .on
        case .poweredOff:
            return .off
        case .unauthorized:
            return .unauthorized
        case .unsupported:
            return .unsupported
        case .resetting, .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

extension CBPeripheral {
    func toDeviceDto(rssi: Int, advertisementData: [String: Any]) -> DeviceDto {
        let id = identifier.uuidString.lowercased()
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? self.name

        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceUuidStrings = serviceUUIDs.map { $0.uuidString.lowercased() }

        // Parse manufacturer data
        var manufacturerDataCompanyId: Int64? = nil
        var manufacturerData: [Int64]? = nil
        if let mfrData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfrData.count >= 2 {
            // First 2 bytes are company ID (little endian)
            manufacturerDataCompanyId = Int64(mfrData[0]) | (Int64(mfrData[1]) << 8)
            // Rest is the actual data
            if mfrData.count > 2 {
                manufacturerData = Array(mfrData[2...]).map { Int64($0) }
            } else {
                manufacturerData = []
            }
        }

        return DeviceDto(
            id: id,
            name: name,
            rssi: Int64(rssi),
            serviceUuids: serviceUuidStrings,
            manufacturerDataCompanyId: manufacturerDataCompanyId,
            manufacturerData: manufacturerData
        )
    }
}

extension CBService {
    func toDto() -> ServiceDto {
        let uuid = self.uuid.uuidString.lowercased()
        let characteristics = self.characteristics?.map { $0.toDto() } ?? []
        let includedServices = self.includedServices?.map { $0.toDto() } ?? []

        return ServiceDto(
            uuid: uuid,
            isPrimary: isPrimary,
            characteristics: characteristics,
            includedServices: includedServices
        )
    }
}

extension CBCharacteristic {
    func toDto() -> CharacteristicDto {
        let uuid = self.uuid.uuidString.lowercased()
        let props = properties

        let propertiesDto = CharacteristicPropertiesDto(
            canRead: props.contains(.read),
            canWrite: props.contains(.write),
            canWriteWithoutResponse: props.contains(.writeWithoutResponse),
            canNotify: props.contains(.notify),
            canIndicate: props.contains(.indicate)
        )

        let descriptors = self.descriptors?.map { $0.toDto() } ?? []

        return CharacteristicDto(
            uuid: uuid,
            properties: propertiesDto,
            descriptors: descriptors
        )
    }
}

extension CBDescriptor {
    func toDto() -> DescriptorDto {
        let uuid = self.uuid.uuidString.lowercased()
        return DescriptorDto(uuid: uuid)
    }
}

extension CBCentral {
    func toCentralDto(mtu: Int) -> CentralDto {
        let id = identifier.uuidString.lowercased()
        return CentralDto(id: id, mtu: Int64(mtu))
    }
}

// MARK: - DTO to CoreBluetooth conversions

extension String {
    func toCBUUID() -> CBUUID {
        return CBUUID(string: self)
    }
}

extension CharacteristicPropertiesDto {
    func toCBProperties() -> CBCharacteristicProperties {
        var props: CBCharacteristicProperties = []
        if canRead { props.insert(.read) }
        if canWrite { props.insert(.write) }
        if canWriteWithoutResponse { props.insert(.writeWithoutResponse) }
        if canNotify { props.insert(.notify) }
        if canIndicate { props.insert(.indicate) }
        return props
    }
}

extension GattPermissionDto {
    func toCBPermission() -> CBAttributePermissions {
        switch self {
        case .read:
            return .readable
        case .readEncrypted:
            return .readEncryptionRequired
        case .write:
            return .writeable
        case .writeEncrypted:
            return .writeEncryptionRequired
        }
    }
}

extension [GattPermissionDto] {
    func toCBPermissions() -> CBAttributePermissions {
        var permissions: CBAttributePermissions = []
        for perm in self {
            permissions.insert(perm.toCBPermission())
        }
        return permissions
    }
}

extension GattStatusDto {
    func toCBATTError() -> CBATTError.Code {
        switch self {
        case .success:
            return .success
        case .readNotPermitted:
            return .readNotPermitted
        case .writeNotPermitted:
            return .writeNotPermitted
        case .invalidOffset:
            return .invalidOffset
        case .invalidAttributeLength:
            return .invalidAttributeValueLength
        case .insufficientAuthentication:
            return .insufficientAuthentication
        case .insufficientEncryption:
            return .insufficientEncryption
        case .requestNotSupported:
            return .requestNotSupported
        }
    }
}

extension LocalServiceDto {
    func toMutableService() -> CBMutableService {
        let service = CBMutableService(type: uuid.toCBUUID(), primary: isPrimary)

        // Convert characteristics
        var mutableCharacteristics: [CBMutableCharacteristic] = []
        for charDto in characteristics {
            let characteristic = charDto.toMutableCharacteristic()
            mutableCharacteristics.append(characteristic)
        }
        service.characteristics = mutableCharacteristics

        // Note: includedServices would need to be handled separately
        // as they reference other services by UUID

        return service
    }
}

extension LocalCharacteristicDto {
    func toMutableCharacteristic() -> CBMutableCharacteristic {
        let props = properties.toCBProperties()
        let perms = permissions.toCBPermissions()

        let characteristic = CBMutableCharacteristic(
            type: uuid.toCBUUID(),
            properties: props,
            value: nil, // Value is set dynamically
            permissions: perms
        )

        // Convert descriptors
        var mutableDescriptors: [CBMutableDescriptor] = []
        for descDto in descriptors {
            let descriptor = descDto.toMutableDescriptor()
            mutableDescriptors.append(descriptor)
        }
        characteristic.descriptors = mutableDescriptors

        return characteristic
    }
}

extension LocalDescriptorDto {
    func toMutableDescriptor() -> CBMutableDescriptor {
        // CoreBluetooth requires type-specific value objects for certain
        // well-known descriptors. Passing NSData where NSString is expected
        // raises NSInternalInconsistencyException at runtime.
        let cbValue: Any? = descriptorValue(uuid: uuid, data: value?.data)
        return CBMutableDescriptor(type: uuid.toCBUUID(), value: cbValue)
    }

    /// Returns the correct Objective-C value type for a given descriptor UUID.
    ///
    /// CoreBluetooth enforces type requirements for standard descriptors:
    /// - 0x2901 (User Description): NSString (UTF-8)
    /// - 0x2902 (CCCD): NSNumber (UInt16 bit field) — normally managed by the stack
    /// - 0x2904 (Presentation Format): NSData (7-byte struct)
    /// - All others: NSData
    private func descriptorValue(uuid: String, data: Data?) -> Any? {
        guard let data = data else { return nil }
        let cbUuid = CBUUID(string: uuid)
        if cbUuid == CBUUID(string: CBUUIDCharacteristicUserDescriptionString) {
            // 0x2901 requires NSString, not NSData
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        return data
    }
}

// MARK: - Data helpers

extension Data {
    func toFlutterData() -> FlutterStandardTypedData {
        return FlutterStandardTypedData(bytes: self)
    }
}
