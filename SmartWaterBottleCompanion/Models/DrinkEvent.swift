import Foundation

struct DrinkEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let month: UInt8
    let day: UInt8
    let hour: UInt8
    let minute: UInt8
    let second: UInt8
    let amountMl: UInt8

    init?(data: Data) {
        guard data.count >= 13, data[0] == 0x1A else { return nil }

        self.id = UUID()
        self.month = data[1]
        self.day = data[2]
        self.hour = data[3]
        self.minute = data[4]
        self.second = data[5]
        // data[6] is separator
        self.amountMl = data[7]
    }

    /// Creates a DrinkEvent with explicit values (for testing and manual creation)
    init(id: UUID = UUID(), month: UInt8, day: UInt8, hour: UInt8, minute: UInt8, second: UInt8, amountMl: UInt8) {
        self.id = id
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.amountMl = amountMl
    }

    var timestamp: Date? {
        var components = DateComponents()
        components.month = Int(month)
        components.day = Int(day)
        components.hour = Int(hour)
        components.minute = Int(minute)
        components.second = Int(second)
        components.year = Calendar.current.component(.year, from: Date())
        return Calendar.current.date(from: components)
    }
}
