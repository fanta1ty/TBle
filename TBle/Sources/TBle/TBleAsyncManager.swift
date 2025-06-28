import CoreBluetooth
import Foundation

private class TBleAsyncConnectionDelegate: NSObject, TBleManagerDelegate {
    private let completion: (Result<Void, Error>) -> Void
    
    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }
    
    func tbleManager(
        _ manager: TBleManager,
        didConnect peripheral: CBPeripheral
    ) {
        completion(.success(()))
    }
    
    func tbleManager(
        _ manager: TBleManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        completion(.failure(error ?? TBleError.connectionFailed(peripheral: peripheral)))
    }
}

private class TBleAsyncServiceDelegate: NSObject, CBPeripheralDelegate {
    private let peripheral: CBPeripheral
    private let completion: (Result<[CBService], Error>) -> Void
    
    init(
        peripheral: CBPeripheral,
        completion: @escaping (Result<[CBService], Error>) -> Void
    ) {
        self.peripheral = peripheral
        self.completion = completion
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(peripheral.services ?? [] ))
        }
    }
}

private class TBleAsyncCharacteristicDelegate: NSObject, CBPeripheralDelegate {
    private let service: CBService
    private let completion: (Result<[CBCharacteristic], Error>) -> Void
    
    init(
        service: CBService,
        completion: @escaping (Result<[CBCharacteristic], Error>) -> Void
    ) {
        self.service = service
        self.completion = completion
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard service.uuid == self.service.uuid else { return }
        
        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(service.characteristics ?? []))
        }
    }
}

private class TBleAsyncReadDelegate: NSObject, CBPeripheralDelegate {
    private let characteristic: CBCharacteristic
    private let completion: (Result<Data, Error>) -> Void
    
    init(
        characteristic: CBCharacteristic,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        self.characteristic = characteristic
        self.completion = completion
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == self.characteristic.uuid else { return }
        
        if let error = error {
            completion(.failure(error))
        } else if let data = characteristic.value {
            completion(.success(data))
        } else {
            completion(.failure(TBleError.invalidData))
        }
    }
}

private class TBleAsyncWriteDelegate: NSObject, CBPeripheralDelegate {
    private let characteristic: CBCharacteristic
    private let completion: (Result<Void, Error>) -> Void
    
    init(
        characteristic: CBCharacteristic,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.characteristic = characteristic
        self.completion = completion
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == self.characteristic.uuid else { return }
        
        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }
}

public extension TBleManager {
    // MARK: - Async Scanning
    func scanForPeripherals(
        withServices services: [CBUUID]? = nil,
        timeout: TimeInterval = 10.0
    ) async throws -> [CBPeripheral] {
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed: Bool = false
            
            startScanning(withServices: services, timeout: timeout)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: { [weak self] in
                if !hasResumed {
                    hasResumed = true
                    self?.stopScanning()
                    
                    continuation.resume(returning: self?.discoveredPeripherals ?? [])
                }
            })
        }
    }
    
    // MARK: - Async Connection
    func connect(
        to peripheral: CBPeripheral,
        timeout: TimeInterval = 10.0
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed: Bool = false
            let originalDelegate = self.delegate
            
            let tempDelegate = TBleAsyncConnectionDelegate { result in
                if !hasResumed {
                    hasResumed = true
                    self.delegate = originalDelegate
                    continuation.resume(with: result)
                }
            }
            
            self.delegate = tempDelegate
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if !hasResumed {
                    hasResumed = true
                    self.delegate = originalDelegate
                    self.disconnect(from: peripheral)
                    continuation.resume(throwing: TBleError.connectionFailed(peripheral: peripheral))
                }
            }
            
            connect(to: peripheral)
        }
    }
    
    // MARK: - Async Service Discovery
    func discoverServices(
        for peripheral: CBPeripheral,
        serviceUUIDs: [CBUUID]? = nil
    ) async throws -> [CBService] {
        guard peripheral.isConnected else {
            throw TBleError.peripheralNotConnected(peripheral: peripheral)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let originalDelegate = peripheral.delegate
            
            // Create temporary delegate
            let tempDelegate = TBleAsyncServiceDelegate(peripheral: peripheral) { result in
                if !hasResumed {
                    hasResumed = true
                    peripheral.delegate = originalDelegate
                    continuation.resume(with: result)
                }
            }
            
            peripheral.delegate = tempDelegate
            peripheral.discoverServices(serviceUUIDs)
        }
    }
    
    // MARK: - Async Characteristic Discovery
    func discoverCharacteristics(
        for service: CBService,
        characteristicUUIDs: [CBUUID]? = nil
    ) async throws -> [CBCharacteristic] {
        guard let peripheral = service.peripheral, peripheral.isConnected else {
            throw TBleError.peripheralNotConnected(peripheral: service.peripheral)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let originalDelegate = peripheral.delegate
            
            // Create temporary delegate
            let tempDelegate = TBleAsyncCharacteristicDelegate(service: service) { result in
                if !hasResumed {
                    hasResumed = true
                    peripheral.delegate = originalDelegate
                    continuation.resume(with: result)
                }
            }
            
            peripheral.delegate = tempDelegate
            peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
        }
    }
       
    // MARK: - Async Read
    func readValue(for characteristic: CBCharacteristic) async throws -> Data {
        guard let peripheral = characteristic.service?.peripheral, peripheral.isConnected else {
            throw TBleError.peripheralNotConnected(peripheral: characteristic.service?.peripheral)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let originalDelegate = peripheral.delegate
            
            // Create temporary delegate
            let tempDelegate = TBleAsyncReadDelegate(characteristic: characteristic) { result in
                if !hasResumed {
                    hasResumed = true
                    peripheral.delegate = originalDelegate
                    continuation.resume(with: result)
                }
            }
            
            peripheral.delegate = tempDelegate
            peripheral.readValue(for: characteristic)
        }
    }
    
    // MARK: - Async Write
    func writeValue(
        _ data: Data,
        for characteristic: CBCharacteristic
    ) async throws {
        guard let peripheral = characteristic.service?.peripheral, peripheral.isConnected else {
            throw TBleError.peripheralNotConnected(peripheral: characteristic.service?.peripheral)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let originalDelegate = peripheral.delegate
            
            // Create temporary delegate
            let tempDelegate = TBleAsyncWriteDelegate(characteristic: characteristic) { result in
                if !hasResumed {
                    hasResumed = true
                    peripheral.delegate = originalDelegate
                    continuation.resume(with: result)
                }
            }
            
            peripheral.delegate = tempDelegate
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
}
