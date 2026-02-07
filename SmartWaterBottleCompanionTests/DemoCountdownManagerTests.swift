import XCTest
@testable import SmartWaterBottleCompanion

/// Tests for DemoCountdownManager - the ObservableObject that handles demo countdown
@MainActor
final class DemoCountdownManagerTests: XCTestCase {

    func testInitialState() {
        let manager = DemoCountdownManager()

        XCTAssertEqual(manager.demoSecondsLeft, 0)
        XCTAssertEqual(manager.demoAlertSecondsLeft, 0)
        XCTAssertFalse(manager.isDemoActive)
        XCTAssertFalse(manager.isDemoAlerting)
        XCTAssertNil(manager.displayCountdown)
    }

    func testStartDemo() {
        let manager = DemoCountdownManager()
        manager.startDemo()

        XCTAssertEqual(manager.demoSecondsLeft, 10)
        XCTAssertEqual(manager.demoAlertSecondsLeft, 0)
        XCTAssertTrue(manager.isDemoActive)
        XCTAssertFalse(manager.isDemoAlerting)
        XCTAssertEqual(manager.displayCountdown, "00:10")
    }

    func testStopDemo() {
        let manager = DemoCountdownManager()
        manager.startDemo()
        manager.stopDemo()

        XCTAssertEqual(manager.demoSecondsLeft, 0)
        XCTAssertEqual(manager.demoAlertSecondsLeft, 0)
        XCTAssertFalse(manager.isDemoActive)
        XCTAssertFalse(manager.isDemoAlerting)
    }

    func testStopDuringCountdown() async {
        let manager = DemoCountdownManager()
        manager.startDemo()

        // Wait for a few ticks
        try? await Task.sleep(nanoseconds: 2_500_000_000)  // 2.5 seconds

        // Should have ticked down
        XCTAssertLessThan(manager.demoSecondsLeft, 10)
        XCTAssertGreaterThan(manager.demoSecondsLeft, 0)

        // Stop it
        manager.stopDemo()
        XCTAssertEqual(manager.demoSecondsLeft, 0)
        XCTAssertEqual(manager.demoAlertSecondsLeft, 0)

        // Wait a bit more - should stay at 0
        try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
        XCTAssertEqual(manager.demoSecondsLeft, 0)
        XCTAssertEqual(manager.demoAlertSecondsLeft, 0)
    }

    func testRestartAfterStop() async {
        let manager = DemoCountdownManager()

        // Start demo
        manager.startDemo()
        XCTAssertEqual(manager.demoSecondsLeft, 10)

        // Wait a bit
        try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        // Stop
        manager.stopDemo()
        XCTAssertEqual(manager.demoSecondsLeft, 0)

        // Restart
        manager.startDemo()
        XCTAssertEqual(manager.demoSecondsLeft, 10, "Should restart at 10 seconds")

        // Wait and verify it's ticking
        try? await Task.sleep(nanoseconds: 2_500_000_000)  // 2.5 seconds
        XCTAssertLessThan(manager.demoSecondsLeft, 10, "Should be ticking down")
        XCTAssertGreaterThan(manager.demoSecondsLeft, 0, "Should still be counting")
    }

    func testRapidStopStartCycles() async {
        let manager = DemoCountdownManager()

        for _ in 0..<3 {
            manager.startDemo()
            XCTAssertEqual(manager.demoSecondsLeft, 10)

            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            manager.stopDemo()
            XCTAssertEqual(manager.demoSecondsLeft, 0)
        }

        // Final start should work
        manager.startDemo()
        XCTAssertEqual(manager.demoSecondsLeft, 10)

        try? await Task.sleep(nanoseconds: 2_500_000_000)  // 2.5 seconds
        XCTAssertLessThan(manager.demoSecondsLeft, 10, "Timer should still be ticking")
        XCTAssertGreaterThan(manager.demoSecondsLeft, 5, "Should have ticked about 2 times")
    }

    func testCountdownTransitionsToAlert() async {
        let manager = DemoCountdownManager()
        manager.startDemo()

        // Wait for countdown to finish (10 seconds + small buffer)
        // Using 10.5s to ensure exactly 10 ticks (countdown reaches 0, alert starts at 60)
        try? await Task.sleep(nanoseconds: 10_500_000_000)  // 10.5 seconds

        XCTAssertEqual(manager.demoSecondsLeft, 0, "Countdown should be at 0")
        // Alert should be 60 (just started) or 59 (one tick into alert) depending on exact timing
        XCTAssertGreaterThanOrEqual(manager.demoAlertSecondsLeft, 59, "Should be in alert phase")
        XCTAssertLessThanOrEqual(manager.demoAlertSecondsLeft, 60, "Should have just started alert")
        XCTAssertTrue(manager.isDemoActive)
        XCTAssertTrue(manager.isDemoAlerting)
        XCTAssertEqual(manager.displayCountdown, "00:00")

        // Stop to clean up
        manager.stopDemo()
    }
}
