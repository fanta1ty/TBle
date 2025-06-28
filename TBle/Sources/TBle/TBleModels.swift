import CoreBluetooth
import Foundation

// MARK: - TBle Device Model
public struct TBleDevice: Identifiable, Hashable {
    public let id: UUID = UUID()
    public let peripheral: CBPeripheral
    public let advertisementData: [String: Any]
    public let rssi: NSNumber
    public let discoveredAt: Date
    
    public init(
        peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi: NSNumber
    ) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
        self.rssi = rssi
        self.discoveredAt = Date()
    }
    
    public var name: String {
        peripheral.name ?? "Unknown Device"
    }
    
    public var localName: String? {
        advertisementData[CBAdvertisementDataLocalNameKey] as? String
    }
    
    public var serviceUUIDs: [CBUUID]? {
        advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
    }
    
    public var txPowerLevel: NSNumber? {
        advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber
    }
    
    public var isConnectable: Bool {
        advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false
    }
    
    public static func == (
        lhs: TBleDevice,
        rhs: TBleDevice
    ) -> Bool {
        lhs.peripheral.identifier == rhs.peripheral.identifier
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(peripheral.identifier)
    }
}

// MARK: - TBle Service Model
public struct TBleService: Identifiable {
    public let id: UUID = UUID()
    public let service: CBService
    public var characteristics: [TBleCharacteristic] = []
    
    public init(service: CBService) {
        self.service = service
    }
    
    public var uuid: CBUUID {
        service.uuid
    }
    
    public var isPrimary: Bool {
        service.isPrimary
    }
}

// MARK: - TBle Characteristic Model
public struct TBleCharacteristic: Identifiable {
    public let id: UUID = UUID()
    public let characteristic: CBCharacteristic
    public var value: Data?
    public var isNotifying: Bool = false
    
    public init(characteristic: CBCharacteristic) {
        self.characteristic = characteristic
        self.value = characteristic.value
        self.isNotifying = characteristic.isNotifying
    }
    
    public var uuid: CBUUID {
        characteristic.uuid
    }
    
    public var properties: CBCharacteristicProperties {
        characteristic.properties
    }
    
    public var canRead: Bool {
        properties.contains(.read)
    }
    
    public var canWrite: Bool {
        properties.contains(.write) || properties.contains(.writeWithoutResponse)
    }
    
    public var canNotify: Bool {
        properties.contains(.notify) || properties.contains(.indicate)
    }
    
    public var stringValue: String? {
        guard let data = value else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    public var hexValue: String? {
        guard let data = value else { return nil }
        return data.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - TBle Error Types
public enum TBleError: Error, LocalizedError {
    case bluetoothPoweredOff
    case bluetoothUnavailable
    case scanningFailed
    case connectionFailed(peripheral: CBPeripheral)
    case serviceDiscoveryFailed(peripheral: CBPeripheral)
    case characteristicDiscoveryFailed(service: CBService)
    case readFailed(characteristic: CBCharacteristic)
    case writeFailed(characteristic: CBCharacteristic)
    case peripheralNotConnected(peripheral: CBPeripheral)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off"
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable"
        case .scanningFailed:
            return "Failed to start scanning"
        case .connectionFailed(let peripheral):
            return "Failed to connect to \(peripheral.name ?? "device")"
        case .serviceDiscoveryFailed(let peripheral):
            return "Failed to discover services for \(peripheral.name ?? "device")"
        case .characteristicDiscoveryFailed(let service):
            return "Failed to discover characteristics for service \(service.uuid)"
        case .readFailed(let characteristic):
            return "Failed to read characteristic \(characteristic.uuid)"
        case .writeFailed(let characteristic):
            return "Failed to write to characteristic \(characteristic.uuid)"
        case .peripheralNotConnected(let peripheral):
            return "Peripheral \(peripheral.name ?? "device") is not connected"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

// MARK: - CBManagerState Extension
public extension CBManagerState {
    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .resetting:
            return "Resetting"
        case .unsupported:
            return "Unsupported"
        case .unauthorized:
            return "Unauthorized"
        case .poweredOff:
            return "Powered Off"
        case .poweredOn:
            return "Powered On"
        @unknown default:
            return "Unknown State"
        }
    }
    
    var isReady: Bool {
        return self == .poweredOn
    }
}

// MARK: - CBPeripheral Extension
public extension CBPeripheral {
    var connectionStatusDescription: String {
        switch state {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .disconnecting:
            return "Disconnecting"
        @unknown default:
            return "Unknown"
        }
    }
    
    var isConnected: Bool {
        return state == .connected
    }
}

// MARK: - Data Extension
public extension Data {
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    init?(hexString: String) {
        let cleanedHex = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanedHex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = cleanedHex.startIndex
        
        while index < cleanedHex.endIndex {
            let nextIndex = cleanedHex.index(index, offsetBy: 2)
            let byteString = cleanedHex[index..<nextIndex]
            
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            
            index = nextIndex
        }
        
        self = data
    }
}
