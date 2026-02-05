import CoreBluetooth

enum BLEConstants {
    // WaterH bottle uses custom 128-bit UUIDs
    // These need to be discovered from actual bottle - placeholder format
    static let bottleServiceUUID = CBUUID(string: "0000FF00-0000-1000-8000-00805F9B34FB")

    // Characteristic #1 - Write commands
    static let commandCharacteristicUUID = CBUUID(string: "0000FF01-0000-1000-8000-00805F9B34FB")

    // Characteristic #2 - Read responses
    static let responseCharacteristicUUID = CBUUID(string: "0000FF02-0000-1000-8000-00805F9B34FB")

    // Command to request drink history
    static let requestHistoryCommand = Data([0x01])

    // Drink packet header "PT" = 0x50 0x54
    static let drinkPacketHeader = Data([0x50, 0x54])

    // Connection timeout
    static let scanTimeout: TimeInterval = 10.0
    static let connectionTimeout: TimeInterval = 5.0
}
