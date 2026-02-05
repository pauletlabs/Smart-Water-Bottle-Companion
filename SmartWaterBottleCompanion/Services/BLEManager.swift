import CoreBluetooth
import Combine

enum BLEConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    case polling
    case error(String)
}

@MainActor
class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var lastError: String?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?

    private var scanTimer: Timer?
    private var onDrinksReceived: (([DrinkEvent]) -> Void)?

    override init() {
        super.init()
    }

    func startScanning() {
        connectionState = .scanning
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func poll(completion: @escaping ([DrinkEvent]) -> Void) {
        self.onDrinksReceived = completion
        startScanning()

        // Timeout for scan
        scanTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.scanTimeout, repeats: false) { [weak self] _ in
            self?.handleScanTimeout()
        }
    }

    func disconnect() {
        scanTimer?.invalidate()
        scanTimer = nil

        if let peripheral = peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }

        peripheral = nil
        commandCharacteristic = nil
        responseCharacteristic = nil
        connectionState = .disconnected
    }

    private func handleScanTimeout() {
        if case .scanning = connectionState {
            disconnect()
            connectionState = .error("Bottle not found")
            lastError = "Could not find bottle. Make sure it's nearby."
            onDrinksReceived?([])
        }
    }

    private func requestDrinkHistory() {
        guard let characteristic = commandCharacteristic else { return }
        connectionState = .polling
        peripheral?.writeValue(BLEConstants.requestHistoryCommand, for: characteristic, type: .withoutResponse)

        // Read response after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.readResponse()
        }
    }

    private func readResponse() {
        guard let characteristic = responseCharacteristic else {
            finishPolling(drinks: [])
            return
        }
        peripheral?.readValue(for: characteristic)
    }

    private func parseResponse(data: Data) -> [DrinkEvent] {
        var drinks: [DrinkEvent] = []

        // Check for "PT" header
        guard data.count >= 6,
              data.prefix(2) == BLEConstants.drinkPacketHeader else {
            return drinks
        }

        // Skip header (2) + length (2) + metadata (2) = 6 bytes
        var offset = 6

        // Parse drink records (13 bytes each)
        while offset + 13 <= data.count {
            let recordData = data.subdata(in: offset..<offset+13)
            if let event = DrinkEvent(data: recordData) {
                drinks.append(event)
            }
            offset += 13
        }

        return drinks
    }

    private func finishPolling(drinks: [DrinkEvent]) {
        onDrinksReceived?(drinks)
        onDrinksReceived = nil
        disconnect()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                central.scanForPeripherals(withServices: [BLEConstants.bottleServiceUUID], options: nil)
            case .poweredOff:
                connectionState = .error("Bluetooth is off")
            case .unauthorized:
                connectionState = .error("Bluetooth permission denied")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            scanTimer?.invalidate()
            central.stopScan()

            self.peripheral = peripheral
            peripheral.delegate = self
            connectionState = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = .connected
            peripheral.discoverServices([BLEConstants.bottleServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .error("Failed to connect")
            lastError = error?.localizedDescription
            finishPolling(drinks: [])
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first else {
                finishPolling(drinks: [])
                return
            }
            peripheral.discoverCharacteristics([
                BLEConstants.commandCharacteristicUUID,
                BLEConstants.responseCharacteristicUUID
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == BLEConstants.commandCharacteristicUUID {
                    commandCharacteristic = characteristic
                } else if characteristic.uuid == BLEConstants.responseCharacteristicUUID {
                    responseCharacteristic = characteristic
                }
            }

            if commandCharacteristic != nil && responseCharacteristic != nil {
                requestDrinkHistory()
            } else {
                finishPolling(drinks: [])
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == BLEConstants.responseCharacteristicUUID,
                  let data = characteristic.value else {
                finishPolling(drinks: [])
                return
            }

            let drinks = parseResponse(data: data)
            finishPolling(drinks: drinks)
        }
    }
}
