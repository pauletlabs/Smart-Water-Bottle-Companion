import XCTest
@testable import SmartWaterBottleCompanion

@MainActor
final class HydrationTrackerTests: XCTestCase {

    // MARK: - Initial State Tests

    func testInitialState() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        XCTAssertEqual(tracker.state.dailyGoalMl, 1600)
        XCTAssertEqual(tracker.state.todayTotalMl, 0)
        XCTAssertFalse(tracker.isPolling)
        XCTAssertNil(tracker.connectionError)
    }

    // MARK: - Process New Drinks Tests

    func testProcessNewDrinksFiltersTodayOnly() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        let calendar = Calendar.current
        let today = Date()

        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        // Create drink from today
        let todayDrink = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 10,
            minute: 30,
            second: 0,
            amountMl: 200
        )

        // Create drink from yesterday (different day)
        let yesterdayDay = todayComponents.day! == 1 ? 28 : todayComponents.day! - 1
        let yesterdayDrink = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(yesterdayDay),
            hour: 10,
            minute: 30,
            second: 0,
            amountMl: 150
        )

        tracker.processNewDrinks([todayDrink, yesterdayDrink])

        // Only today's drink should be counted
        XCTAssertEqual(tracker.state.todayTotalMl, 200)
        XCTAssertEqual(tracker.state.drinkHistory.count, 1)
    }

    func testProcessNewDrinksUpdatesTodayTotal() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        let drink1 = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 9,
            minute: 0,
            second: 0,
            amountMl: 200
        )

        let drink2 = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 10,
            minute: 0,
            second: 0,
            amountMl: 150
        )

        tracker.processNewDrinks([drink1, drink2])

        XCTAssertEqual(tracker.state.todayTotalMl, 350)
    }

    func testProcessNewDrinksAvoidsDuplicates() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        // Create a drink with a specific ID
        let drinkId = UUID()
        let drink = DrinkEvent(
            id: drinkId,
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 10,
            minute: 0,
            second: 0,
            amountMl: 200
        )

        // Process the same drink twice
        tracker.processNewDrinks([drink])
        tracker.processNewDrinks([drink])

        // Should only count once
        XCTAssertEqual(tracker.state.drinkHistory.count, 1)
        XCTAssertEqual(tracker.state.todayTotalMl, 200)
    }

    func testProcessNewDrinksUpdatesLastDrinkTime() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        let drink = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 14,
            minute: 30,
            second: 0,
            amountMl: 200
        )

        XCTAssertNil(tracker.state.lastDrinkTime)

        tracker.processNewDrinks([drink])

        XCTAssertNotNil(tracker.state.lastDrinkTime)
    }

    func testProcessNewDrinksUpdatesLastDrinkTimeToLatest() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        let earlierDrink = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 9,
            minute: 0,
            second: 0,
            amountMl: 200
        )

        let laterDrink = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 14,
            minute: 30,
            second: 0,
            amountMl: 150
        )

        tracker.processNewDrinks([earlierDrink, laterDrink])

        XCTAssertNotNil(tracker.state.lastDrinkTime)
        let lastHour = calendar.component(.hour, from: tracker.state.lastDrinkTime!)
        XCTAssertEqual(lastHour, 14)
    }

    // MARK: - Adaptive Poll Interval Tests

    func testPollIntervalMoreThan10Minutes() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        // More than 10 minutes -> 10 minute interval
        let interval = tracker.calculatePollInterval(timeUntilReminder: 15 * 60)

        XCTAssertEqual(interval, 10 * 60)
    }

    func testPollInterval5To10Minutes() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        // 5-10 minutes -> 5 minute interval
        let interval = tracker.calculatePollInterval(timeUntilReminder: 7 * 60)

        XCTAssertEqual(interval, 5 * 60)
    }

    func testPollIntervalLessThan5Minutes() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        // Less than 5 minutes -> 2 minute interval
        let interval = tracker.calculatePollInterval(timeUntilReminder: 3 * 60)

        XCTAssertEqual(interval, 2 * 60)
    }

    func testPollIntervalZeroOrNegative() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        // At or past reminder time -> 1 minute interval
        let zeroInterval = tracker.calculatePollInterval(timeUntilReminder: 0)
        let negativeInterval = tracker.calculatePollInterval(timeUntilReminder: -60)

        XCTAssertEqual(zeroInterval, 60)
        XCTAssertEqual(negativeInterval, 60)
    }

    func testPollIntervalAt10MinuteBoundary() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        // Exactly 10 minutes should use 5 minute interval (5-10 range)
        let interval = tracker.calculatePollInterval(timeUntilReminder: 10 * 60)

        XCTAssertEqual(interval, 5 * 60)
    }

    func testPollIntervalAt5MinuteBoundary() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        // Exactly 5 minutes should use 2 minute interval (<5 min range)
        let interval = tracker.calculatePollInterval(timeUntilReminder: 5 * 60)

        XCTAssertEqual(interval, 2 * 60)
    }

    // MARK: - Polling State Tests

    func testStartPollingChangesState() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)

        XCTAssertFalse(tracker.isPolling)

        tracker.startPolling()

        XCTAssertTrue(tracker.isPolling)
    }

    func testStopPollingChangesState() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        tracker.startPolling()

        XCTAssertTrue(tracker.isPolling)

        tracker.stopPolling()

        XCTAssertFalse(tracker.isPolling)
    }

    // MARK: - Reset Tests

    func testResetForNewDay() async {
        let tracker = HydrationTracker(dailyGoalMl: 1600)
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        // Add some drinks
        let drink = DrinkEvent(
            month: UInt8(todayComponents.month!),
            day: UInt8(todayComponents.day!),
            hour: 10,
            minute: 0,
            second: 0,
            amountMl: 200
        )
        tracker.processNewDrinks([drink])

        XCTAssertEqual(tracker.state.todayTotalMl, 200)

        // Reset for new day
        tracker.resetForNewDay()

        XCTAssertEqual(tracker.state.todayTotalMl, 0)
        XCTAssertTrue(tracker.state.drinkHistory.isEmpty)
        XCTAssertNil(tracker.state.lastDrinkTime)
    }

    // MARK: - Helper for creating test dates

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
