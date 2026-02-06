import CoreBluetooth
import Combine
import os.log

private let bleLog = Logger(subsystem: "com.smartwaterbottle", category: "BLE")

enum BLEConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    case polling
    case error(String)
}

/// Discovered device info for UI
struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

@MainActor
class BLEManager: NSObject, ObservableObject {
    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var lastError: String?
    @Published var discoveredDevices: [String] = []  // For debug UI (legacy)
    @Published var devices: [DiscoveredDevice] = []  // Full device info

    /// Enable to scan for ALL devices (discovery mode)
    var discoveryMode: Bool = true

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?

    private var scanTimer: Timer?
    private var onDrinksReceived: (([DrinkEvent]) -> Void)?

    override init() {
        super.init()
        bleLog.info("BLEManager initialized")
    }

    func startScanning() {
        connectionState = .scanning
        discoveredDevices = []
        devices = []
        bleLog.info("Starting BLE scan (discoveryMode: \(self.discoveryMode))")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Connect to a specific discovered device
    func connectToDevice(_ device: DiscoveredDevice) {
        bleLog.notice("🔗 Manual connect to: \(device.name)")
        scanTimer?.invalidate()
        centralManager?.stopScan()

        self.peripheral = device.peripheral
        device.peripheral.delegate = self
        connectionState = .connecting
        centralManager?.connect(device.peripheral, options: nil)
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
            bleLog.info("Central manager state: \(String(describing: central.state.rawValue))")
            switch central.state {
            case .poweredOn:
                if discoveryMode {
                    // Open scan - find ALL BLE devices nearby
                    bleLog.info("🔍 Starting OPEN scan (all devices)")
                    central.scanForPeripherals(withServices: nil, options: [
                        CBCentralManagerScanOptionAllowDuplicatesKey: false
                    ])
                } else {
                    bleLog.info("Scanning for service: \(BLEConstants.bottleServiceUUID)")
                    central.scanForPeripherals(withServices: [BLEConstants.bottleServiceUUID], options: nil)
                }
            case .poweredOff:
                bleLog.error("Bluetooth is off")
                connectionState = .error("Bluetooth is off")
            case .unauthorized:
                bleLog.error("Bluetooth permission denied")
                connectionState = .error("Bluetooth permission denied")
            default:
                bleLog.info("Central state: \(central.state.rawValue)")
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? "Unknown"
            let deviceId = peripheral.identifier

            // Skip devices we've already seen (by identifier)
            let alreadySeen = devices.contains { $0.id == deviceId }
            if alreadySeen {
                return  // Skip duplicate
            }

            // Cap at 50 devices max
            if devices.count >= 50 {
                bleLog.warning("Device limit reached (50), stopping scan")
                central.stopScan()
                return
            }

            // Store full device info for tap-to-connect
            let device = DiscoveredDevice(
                id: deviceId,
                name: name,
                rssi: RSSI.intValue,
                peripheral: peripheral
            )
            devices.append(device)

            // Legacy string list for compatibility
            let deviceInfo = "\(name) (\(RSSI)dB)"
            discoveredDevices.append(deviceInfo)

            // Only log devices with names (reduces noise)
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let serviceStr = serviceUUIDs.map { $0.uuidString }.joined(separator: ", ")

            if name != "Unknown" {
                bleLog.info("📱 Found: \(name) | RSSI: \(RSSI) | Services: [\(serviceStr)]")
            }

            // In discovery mode, DON'T auto-connect - let user tap to choose
            // (Previously auto-connected to anything with "water" in name)
            if !discoveryMode {
                // Original behavior - connect to first match
                scanTimer?.invalidate()
                central.stopScan()

                self.peripheral = peripheral
                peripheral.delegate = self
                connectionState = .connecting
                central.connect(peripheral, options: nil)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = .connected
            bleLog.notice("✅ CONNECTED to: \(peripheral.name ?? "Unknown")")

            if discoveryMode {
                // Discover ALL services to see what the bottle exposes
                bleLog.info("🔎 Discovering ALL services...")
                peripheral.discoverServices(nil)
            } else {
                // Discover both command (FFE5) and response (FFE0) services
                peripheral.discoverServices([BLEConstants.commandServiceUUID, BLEConstants.responseServiceUUID])
            }
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
            if let error = error {
                bleLog.error("Service discovery error: \(error.localizedDescription)")
                finishPolling(drinks: [])
                return
            }

            guard let services = peripheral.services else {
                bleLog.warning("No services found")
                finishPolling(drinks: [])
                return
            }

            bleLog.notice("📋 Found \(services.count) services:")
            for (index, service) in services.enumerated() {
                bleLog.notice("  Service \(index + 1): \(service.uuid.uuidString)")
                // Discover ALL characteristics for each service
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error = error {
                bleLog.error("Characteristic discovery error: \(error.localizedDescription)")
                return
            }

            guard let characteristics = service.characteristics else {
                bleLog.warning("No characteristics for service \(service.uuid)")
                return
            }

            bleLog.notice("📝 Service \(service.uuid.uuidString) has \(characteristics.count) characteristics:")
            for (index, char) in characteristics.enumerated() {
                let props = describeProperties(char.properties)
                bleLog.notice("  Char \(index + 1): \(char.uuid.uuidString)")
                bleLog.notice("         Properties: \(props)")

                // Subscribe to notifications FIRST (before any reads/writes)
                if char.properties.contains(.notify) {
                    bleLog.info("    → Subscribing to notifications...")
                    peripheral.setNotifyValue(true, for: char)
                }
            }

            // Track characteristics for actual use
            for characteristic in characteristics {
                if characteristic.uuid == BLEConstants.commandCharacteristicUUID {
                    commandCharacteristic = characteristic
                    bleLog.info("✓ Found command characteristic")
                } else if characteristic.uuid == BLEConstants.responseCharacteristicUUID {
                    responseCharacteristic = characteristic
                    bleLog.info("✓ Found response characteristic")
                }
            }

            // In discovery mode, write the history command to writable characteristics
            // Response will come via notification (already subscribed above)
            if discoveryMode {
                // Small delay to let notification subscription complete first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Task { @MainActor in
                        // Check we're still connected
                        guard peripheral.state == .connected else {
                            bleLog.warning("⚠️ Peripheral disconnected before write")
                            return
                        }

                        for char in characteristics where char.properties.contains(.writeWithoutResponse) {
                            bleLog.notice("🧪 Writing history command (0x01) to \(char.uuid.uuidString)")
                            peripheral.writeValue(BLEConstants.requestHistoryCommand, for: char, type: .withoutResponse)
                        }
                        bleLog.info("⏳ Waiting for notification response...")
                    }
                }
            } else if commandCharacteristic != nil && responseCharacteristic != nil {
                requestDrinkHistory()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                bleLog.error("Read error for \(characteristic.uuid): \(error.localizedDescription)")
                return
            }

            guard let data = characteristic.value else {
                bleLog.warning("No data from \(characteristic.uuid)")
                return
            }

            // Log the raw data as hex
            let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            bleLog.notice("📥 DATA from \(characteristic.uuid.uuidString):")
            bleLog.notice("   Raw (\(data.count) bytes): \(hexStr)")

            // Check for "PT" header (drink data)
            if data.count >= 2 {
                let header = String(data: data.prefix(2), encoding: .ascii) ?? ""
                bleLog.info("   Header: \"\(header)\"")

                if header == "PT" {
                    bleLog.notice("🎉 DRINK DATA PACKET DETECTED!")
                }
            }

            // Original response handling
            if characteristic.uuid == BLEConstants.responseCharacteristicUUID {
                let drinks = parseResponse(data: data)
                if !drinks.isEmpty {
                    bleLog.notice("🥤 Parsed \(drinks.count) drink events!")
                    for drink in drinks {
                        bleLog.info("   - \(drink.amountMl)ml at \(drink.timestamp?.description ?? "?")")
                    }
                }
                finishPolling(drinks: drinks)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error = error {
                bleLog.error("Notify subscription error: \(error.localizedDescription)")
            } else {
                bleLog.info("📡 Subscribed to notifications from \(characteristic.uuid)")
            }
        }
    }

    // Helper to describe characteristic properties
    private func describeProperties(_ props: CBCharacteristicProperties) -> String {
        var result: [String] = []
        if props.contains(.read) { result.append("Read") }
        if props.contains(.write) { result.append("Write") }
        if props.contains(.writeWithoutResponse) { result.append("WriteNoResp") }
        if props.contains(.notify) { result.append("Notify") }
        if props.contains(.indicate) { result.append("Indicate") }
        if props.contains(.broadcast) { result.append("Broadcast") }
        return result.joined(separator: ", ")
    }
}
