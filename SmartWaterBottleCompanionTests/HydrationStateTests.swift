import XCTest
@testable import SmartWaterBottleCompanion

final class HydrationStateTests: XCTestCase {

    func testProgressCalculation() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.todayTotalMl = 800

        XCTAssertEqual(state.progress, 0.5, accuracy: 0.01)
    }

    func testProgressCapsAt100Percent() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.todayTotalMl = 2000

        XCTAssertEqual(state.progress, 1.0, accuracy: 0.01)
    }

    func testGlassCount() {
        var state = HydrationState(dailyGoalMl: 1600, mlPerGlass: 200)
        state.todayTotalMl = 600

        XCTAssertEqual(state.glassesConsumed, 3)
        XCTAssertEqual(state.glassesGoal, 8)
    }

    func testTimeUntilNextDrink() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.wakeTime = DateComponents(hour: 8, minute: 0)
        state.sleepTime = DateComponents(hour: 20, minute: 0)
        state.todayTotalMl = 400  // 2 glasses of 8

        let interval = state.timeUntilNextDrink(from: makeDate(hour: 10, minute: 0))

        XCTAssertNotNil(interval)
        XCTAssertGreaterThan(interval!, 0)
    }

    func testNoReminderDuringSleep() {
        var state = HydrationState(dailyGoalMl: 1600)
        state.wakeTime = DateComponents(hour: 8, minute: 0)
        state.sleepTime = DateComponents(hour: 20, minute: 0)

        let interval = state.timeUntilNextDrink(from: makeDate(hour: 22, minute: 0))

        XCTAssertNil(interval)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
