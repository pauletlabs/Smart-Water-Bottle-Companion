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
        // Set last drink time to 20 minutes ago
        state.lastDrinkTime = makeDate(hour: 9, minute: 40)

        let interval = state.timeUntilNextDrink(from: makeDate(hour: 10, minute: 0))

        // Should return time remaining (capped interval minus elapsed since last drink)
        XCTAssertNotNil(interval)
        // With 45 min cap and 20 min elapsed, should have ~25 min remaining
    }

    func testNoReminderBeforeStartTime() {
        var state = HydrationState(dailyGoalMl: 1000)
        state.wakeTime = DateComponents(hour: 6, minute: 45)
        state.sleepTime = DateComponents(hour: 17, minute: 0)

        // Before start time should return nil
        let interval = state.timeUntilNextDrink(from: makeDate(hour: 5, minute: 0))

        XCTAssertNil(interval)
    }

    func testContinuesAfterTargetTime() {
        var state = HydrationState(dailyGoalMl: 1000)
        state.wakeTime = DateComponents(hour: 6, minute: 45)
        state.sleepTime = DateComponents(hour: 17, minute: 0)
        state.lastDrinkTime = makeDate(hour: 18, minute: 0)

        // After target time should still return a value (continues tracking)
        let interval = state.timeUntilNextDrink(from: makeDate(hour: 18, minute: 30))

        XCTAssertNotNil(interval)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
