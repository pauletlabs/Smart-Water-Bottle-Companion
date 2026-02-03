import XCTest
@testable import SmartWaterBottleCompanion

final class DrinkEventTests: XCTestCase {

    func testParseDrinkEventFromValidData() {
        // Sample packet: record type 0x1A, Feb 2, 22:21:15, 16ml
        let data = Data([0x1A, 0x02, 0x02, 0x16, 0x15, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x61, 0x00])

        let event = DrinkEvent(data: data)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.month, 2)
        XCTAssertEqual(event?.day, 2)
        XCTAssertEqual(event?.hour, 22)
        XCTAssertEqual(event?.minute, 21)
        XCTAssertEqual(event?.second, 15)
        XCTAssertEqual(event?.amountMl, 16)
    }

    func testRejectInvalidRecordType() {
        // Wrong record type (not 0x1A)
        let data = Data([0x1B, 0x02, 0x02, 0x16, 0x15, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x61, 0x00])

        let event = DrinkEvent(data: data)

        XCTAssertNil(event)
    }

    func testRejectTooShortData() {
        let data = Data([0x1A, 0x02, 0x02])

        let event = DrinkEvent(data: data)

        XCTAssertNil(event)
    }

    func testTimestampGeneration() {
        let data = Data([0x1A, 0x02, 0x02, 0x16, 0x15, 0x0F, 0x00, 0x10, 0x00, 0x00, 0x01, 0x61, 0x00])

        let event = DrinkEvent(data: data)
        let timestamp = event?.timestamp

        XCTAssertNotNil(timestamp)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.month, from: timestamp!), 2)
        XCTAssertEqual(calendar.component(.day, from: timestamp!), 2)
        XCTAssertEqual(calendar.component(.hour, from: timestamp!), 22)
    }
}
