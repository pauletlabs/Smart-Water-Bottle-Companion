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

    /// Published when real-time data is received from the bottle
    @Published var lastReceivedData: Data?

    /// Published when drink events are parsed from bottle data
    @Published var receivedDrinks: [DrinkEvent] = []

    /// Enable to scan for ALL devices (discovery mode)
    var discoveryMode: Bool = true

    /// Should we auto-reconnect when disconnected?
    var autoReconnect: Bool = true

    /// Saved bottle identifier for reconnection
    @Published var savedBottleIdentifier: UUID? {
        didSet {
            if let uuid = savedBottleIdentifier {
                UserDefaults.standard.set(uuid.uuidString, forKey: "savedBottleIdentifier")
                bleLog.info("💾 Saved bottle identifier: \(uuid.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "savedBottleIdentifier")
            }
        }
    }

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?

    private var scanTimer: Timer?
    private var reconnectTimer: Timer?
    private var onDrinksReceived: (([DrinkEvent]) -> Void)?
    private var isUserInitiatedDisconnect = false

    override init() {
        super.init()
        // Load saved bottle identifier
        if let uuidString = UserDefaults.standard.string(forKey: "savedBottleIdentifier"),
           let uuid = UUID(uuidString: uuidString) {
            savedBottleIdentifier = uuid
            bleLog.info("📂 Loaded saved bottle identifier: \(uuidString)")
        }
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
        reconnectTimer?.invalidate()
        centralManager?.stopScan()

        // Save the bottle identifier for future reconnection
        savedBottleIdentifier = device.id
        isUserInitiatedDisconnect = false

        self.peripheral = device.peripheral
        device.peripheral.delegate = self
        connectionState = .connecting
        centralManager?.connect(device.peripheral, options: nil)
    }

    /// Try to reconnect to the saved bottle
    func reconnectToSavedBottle() {
        guard let bottleId = savedBottleIdentifier else {
            bleLog.warning("No saved bottle to reconnect to")
            return
        }

        guard let central = centralManager, central.state == .poweredOn else {
            bleLog.warning("Central manager not ready for reconnection")
            // Start the central manager if needed
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: nil)
            }
            return
        }

        // Try to retrieve the peripheral by identifier
        let peripherals = central.retrievePeripherals(withIdentifiers: [bottleId])
        if let savedPeripheral = peripherals.first {
            bleLog.notice("🔄 Attempting to reconnect to saved bottle...")
            isUserInitiatedDisconnect = false
            self.peripheral = savedPeripheral
            savedPeripheral.delegate = self
            connectionState = .connecting
            central.connect(savedPeripheral, options: nil)
        } else {
            // Peripheral not found - scan for it
            bleLog.notice("🔍 Saved bottle not in cache, scanning...")
            startScanning()
        }
    }

    func poll(completion: @escaping ([DrinkEvent]) -> Void) {
        self.onDrinksReceived = completion
        startScanning()

        // Timeout for scan
        scanTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.scanTimeout, repeats: false) { [weak self] _ in
            self?.handleScanTimeout()
        }
    }

    /// Stop scanning but keep any existing connection alive
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager?.stopScan()
        // Don't change connectionState if we're connected
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    func disconnect() {
        isUserInitiatedDisconnect = true
        scanTimer?.invalidate()
        scanTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        // Stop scanning
        centralManager?.stopScan()

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

        // Check for "PT" header (original format)
        if data.count >= 6, data.prefix(2) == BLEConstants.drinkPacketHeader {
            // Skip header (2) + length (2) + metadata (2) = 6 bytes
            var offset = 6
            while offset + 13 <= data.count {
                let recordData = data.subdata(in: offset..<offset+13)
                if let event = DrinkEvent(data: recordData) {
                    drinks.append(event)
                }
                offset += 13
            }
            return drinks
        }

        // Alternative format: packets starting with length byte + metadata
        // Look for drink records (0x1A marker) anywhere in the data
        drinks = parseDrinkRecords(from: data)
        return drinks
    }

    /// Parse drink records from raw data by looking for 0x1A markers
    private func parseDrinkRecords(from data: Data) -> [DrinkEvent] {
        var drinks: [DrinkEvent] = []
        var offset = 0

        // Skip first 2 bytes (header/metadata)
        if data.count > 2 {
            offset = 2
        }

        // Look for 0x1A markers (drink record type)
        while offset + 13 <= data.count {
            if data[offset] == 0x1A {
                // Found a drink record
                let recordData = data.subdata(in: offset..<offset+13)
                if let event = DrinkEvent(data: recordData) {
                    drinks.append(event)
                    bleLog.info("🥤 Parsed drink: \(event.amountMl)ml at \(event.hour):\(event.minute)")
                }
                offset += 13
            } else {
                // Not a drink record, skip one byte
                offset += 1
            }
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
                // If we have a saved bottle and should auto-reconnect, do so
                if autoReconnect && savedBottleIdentifier != nil && peripheral == nil {
                    bleLog.info("🔄 Bluetooth powered on, attempting reconnect to saved bottle...")
                    reconnectToSavedBottle()
                } else if discoveryMode {
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

            // Check if this is our saved bottle - auto-connect!
            if let savedId = savedBottleIdentifier, deviceId == savedId {
                bleLog.notice("🎯 Found saved bottle! Auto-connecting...")
                scanTimer?.invalidate()
                central.stopScan()

                isUserInitiatedDisconnect = false
                self.peripheral = peripheral
                peripheral.delegate = self
                connectionState = .connecting
                central.connect(peripheral, options: nil)
                return
            }

            // In discovery mode, DON'T auto-connect - let user tap to choose
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

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            bleLog.notice("📴 Disconnected from: \(peripheral.name ?? "Unknown")")

            self.peripheral = nil
            commandCharacteristic = nil
            responseCharacteristic = nil
            connectionState = .disconnected

            if let error = error {
                bleLog.warning("   Disconnect reason: \(error.localizedDescription)")
            }

            // Auto-reconnect if not user-initiated and we have a saved bottle
            if !isUserInitiatedDisconnect && autoReconnect && savedBottleIdentifier != nil {
                bleLog.info("🔄 Scheduling auto-reconnect in 2 seconds...")
                reconnectTimer?.invalidate()
                reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.reconnectToSavedBottle()
                    }
                }
            }
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

            // In discovery mode, just subscribe and listen - don't write commands
            // The bottle sends RT (Real-Time) status packets automatically via notifications
            // Writing to unknown characteristics can cause the bottle to disconnect
            if discoveryMode {
                bleLog.info("📡 Discovery mode: listening for notifications (not writing commands)")
                // Notifications are already subscribed above - just wait for data to arrive
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

            // Publish the data for observers
            lastReceivedData = data

            // Check for packet type by header
            if data.count >= 2 {
                let header = String(data: data.prefix(2), encoding: .ascii) ?? ""
                bleLog.info("   Header: \"\(header)\"")

                switch header {
                case "PT":
                    // Drink history packet (original format)
                    bleLog.notice("🎉 DRINK DATA PACKET DETECTED (PT)!")
                    let drinks = parseResponse(data: data)
                    if !drinks.isEmpty {
                        bleLog.notice("🥤 Parsed \(drinks.count) drink events!")
                        receivedDrinks = drinks
                        onDrinksReceived?(drinks)
                    }
                case "RT":
                    // Real-time status packet - bottle sends these automatically
                    bleLog.info("   📊 Real-time status packet")
                case "RP":
                    // Response/acknowledgment packet
                    bleLog.info("   📊 Response packet")
                default:
                    // Try to parse as drink data (alternative format)
                    let drinks = parseDrinkRecords(from: data)
                    if !drinks.isEmpty {
                        bleLog.notice("🎉 DRINK DATA DETECTED! Found \(drinks.count) drinks")
                        receivedDrinks = drinks
                        onDrinksReceived?(drinks)
                    } else {
                        bleLog.info("   Unknown packet type")
                    }
                }
            }

            // Legacy polling flow - finish if we were in polling mode
            if !discoveryMode && characteristic.uuid == BLEConstants.responseCharacteristicUUID {
                let drinks = parseResponse(data: data)
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
