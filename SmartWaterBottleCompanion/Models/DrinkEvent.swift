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
