import CoreBluetooth

enum BLEConstants {
    // WaterH-Boost-24oz UUIDs (discovered 2026-02-06)

    // Service containing the command characteristic (write)
    static let commandServiceUUID = CBUUID(string: "0000FFE5-0000-1000-8000-00805F9B34FB")

    // Service containing the response characteristic (read/notify)
    static let responseServiceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")

    // For scanning - look for either service
    static let bottleServiceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")

    // Characteristic for writing commands (in FFE5 service)
    static let commandCharacteristicUUID = CBUUID(string: "0000FFE9-0000-1000-8000-00805F9B34FB")

    // Characteristic for reading responses (in FFE0 service)
    static let responseCharacteristicUUID = CBUUID(string: "0000FFE4-0000-1000-8000-00805F9B34FB")

    // Command to request drink history
    static let requestHistoryCommand = Data([0x01])

    // Drink packet header "PT" = 0x50 0x54
    static let drinkPacketHeader = Data([0x50, 0x54])

    // Connection timeout
    static let scanTimeout: TimeInterval = 10.0
    static let connectionTimeout: TimeInterval = 5.0
}
