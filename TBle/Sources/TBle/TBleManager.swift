import CoreBluetooth
import Foundation
import Combine

public protocol TBleManagerDelegate: AnyObject {
    func tbleManager(
        _ manager: TBleManager,
        didUpdateState state: CBManagerState
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didConnect peripheral: CBPeripheral
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didDiscoverServices services: [CBService]?,
        for peripheral: CBPeripheral
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didDiscoverCharacteristics characteristics: [CBCharacteristic]?,
        for service: CBService
    )
    
    func tbleManager(
        _ manager: TBleManager,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    )
}

public extension TBleManagerDelegate {
    func tbleManager(
        _ manager: TBleManager,
        didUpdateState state: CBManagerState
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didConnect peripheral: CBPeripheral
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didDiscoverServices services: [CBService]?,
        for peripheral: CBPeripheral
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didDiscoverCharacteristics characteristics: [CBCharacteristic]?,
        for service: CBService
    ) {}
    
    func tbleManager(
        _ manager: TBleManager,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {}
}

public class TBleManager: NSObject, ObservableObject {
    // MARK: - Properties
    @Published public var isScanning = false
    @Published public var connectedPeripherals: [CBPeripheral] = []
    @Published public var discoveredPeripherals: [CBPeripheral] = []
    @Published public var bluetoothState: CBManagerState = .unknown
    
    public weak var delegate: TBleManagerDelegate?
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheralMap: [UUID: CBPeripheral] = [:]
    private var serviceUUIDs: [CBUUID]?
    private var scanTimeout: Timer?
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil
        )
    }
    
    public init(serviceUUIDs: [CBUUID]? = nil) {
        self.serviceUUIDs = serviceUUIDs
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil
        )
    }
    
    public func startScanning(
        withServices services: [CBUUID]? = nil,
        timeout: TimeInterval? = nil
    ) {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on")
            return
        }
        let servicesToScan = services ?? serviceUUIDs
        centralManager.scanForPeripherals(
            withServices: servicesToScan,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
        discoveredPeripherals.removeAll()
        if let timeout {
            scanTimeout = Timer.scheduledTimer(
                withTimeInterval: timeout,
                repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                self.stopScanning()
            }
        }
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        scanTimeout?.invalidate()
        scanTimeout = nil
    }
    
    public func connect(to peripheral: CBPeripheral) {
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    public func disconnect(from peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    public func disconnectAll() {
        for peripheral in connectedPeripherals {
            disconnect(from: peripheral)
        }
    }
    
    public func discoverServices(
        for peripheral: CBPeripheral,
        serviceUUIDs: [CBUUID]? = nil
    ) {
        peripheral.discoverServices(serviceUUIDs)
    }
    
    public func discoverCharacteristics(
        for service: CBService,
        characteristicUUIDs: [CBUUID]? = nil
    ) {
        service.peripheral?.discoverCharacteristics(
            characteristicUUIDs,
            for: service
        )
    }
    
    public func readValue(
        for characteristic: CBCharacteristic
    ) {
        characteristic.service?.peripheral?.readValue(for: characteristic)
    }
    
    public func writeValue(
        _ data: Data,
        for characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType = .withResponse
    ) {
        characteristic.service?.peripheral?.writeValue(
            data,
            for: characteristic,
            type: type
        )
    }
    
    public func setNotify(
        _ enabled: Bool,
        for characteristic: CBCharacteristic
    ) {
        characteristic.service?.peripheral?.setNotifyValue(
            enabled,
            for: characteristic
        )
    }
    
    public func isConnected(
        to peripheral: CBPeripheral
    ) -> Bool {
        connectedPeripherals.contains(peripheral)
    }
    
    private func addConnectedPeripheral(_ peripheral: CBPeripheral) {
        if !connectedPeripherals.contains(peripheral) {
            connectedPeripherals.append(peripheral)
            connectedPeripheralMap[peripheral.identifier] = peripheral
        }
    }
    
    private func removeConnectedPeripheral(_ peripheral: CBPeripheral) {
        connectedPeripherals.removeAll {
            $0.identifier == peripheral.identifier
        }
        connectedPeripheralMap.removeValue(forKey: peripheral.identifier)
    }
}

// MARK: - CBCentralManagerDelegate
extension TBleManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        delegate?.tbleManager(
            self,
            didUpdateState: central.state
        )
        if central.state != .poweredOn && isScanning {
            stopScanning()
        }
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        if !discoveredPeripherals
            .contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
        delegate?.tbleManager(
            self,
            didDiscover: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI
        )
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        addConnectedPeripheral(peripheral)
        delegate?.tbleManager(
            self,
            didConnect: peripheral
        )
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        removeConnectedPeripheral(peripheral)
        delegate?.tbleManager(
            self,
            didDisconnectPeripheral: peripheral,
            error: error
        )
    }
    
    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        delegate?.tbleManager(
            self, didFailToConnect: peripheral,
            error: error
        )
    }
}

// MARK: - CBPeripheralDelegate
extension TBleManager: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil,
              let services = peripheral.services else {
            print("Error discovering services: \(error?.localizedDescription ?? "Unknown error")")
            return
        }
        delegate?.tbleManager(
            self,
            didDiscoverServices: services,
            for: peripheral
        )
    }
    
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristics = service.characteristics else {
            print("Error discovering characteristics: \(error?.localizedDescription ?? "Unknown error")")
            return
        }
        delegate?.tbleManager(
            self,
            didDiscoverCharacteristics: characteristics,
            for: service
        )
    }
    
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        delegate?.tbleManager(
            self,
            didUpdateValueFor: characteristic,
            error: error
        )
    }
    
    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            print("Error writing value: \(error.localizedDescription)")
        }
    }
    
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            print("Error updating notification state: \(error.localizedDescription)")
        }
    }
}
