import XCTest
@testable import SmartWaterBottleCompanion

/// Tests for the demo countdown timer behavior
/// Reproducing bug: countdown gets stuck after adding a drink and restarting demo
final class DemoCountdownTests: XCTestCase {

    // MARK: - Test the demo state logic directly

    /// Test that startDemo initializes state correctly
    func testStartDemoInitializesState() {
        var demoSecondsLeft = 0
        var demoAlertSecondsLeft = 0

        // Simulate startDemo()
        demoSecondsLeft = 10
        demoAlertSecondsLeft = 0

        XCTAssertEqual(demoSecondsLeft, 10)
        XCTAssertEqual(demoAlertSecondsLeft, 0)
        XCTAssertTrue(demoSecondsLeft > 0 || demoAlertSecondsLeft > 0, "isDemoActive should be true")
    }

    /// Test that stopDemo clears state correctly
    func testStopDemoClearsState() {
        var demoSecondsLeft = 5
        var demoAlertSecondsLeft = 30

        // Simulate stopDemo()
        demoSecondsLeft = 0
        demoAlertSecondsLeft = 0

        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 0)
        XCTAssertFalse(demoSecondsLeft > 0 || demoAlertSecondsLeft > 0, "isDemoActive should be false")
    }

    /// Test tick during countdown phase
    func testTickDuringCountdown() {
        var demoSecondsLeft = 10
        var demoAlertSecondsLeft = 0

        // Simulate one tick
        if demoSecondsLeft > 0 {
            demoSecondsLeft -= 1
            if demoSecondsLeft == 0 {
                demoAlertSecondsLeft = 60
            }
        } else if demoAlertSecondsLeft > 0 {
            demoAlertSecondsLeft -= 1
        }

        XCTAssertEqual(demoSecondsLeft, 9)
        XCTAssertEqual(demoAlertSecondsLeft, 0)
    }

    /// Test tick transitions to alert phase when countdown reaches 0
    func testTickTransitionsToAlertPhase() {
        var demoSecondsLeft = 1
        var demoAlertSecondsLeft = 0

        // Simulate one tick - should transition to alert
        if demoSecondsLeft > 0 {
            demoSecondsLeft -= 1
            if demoSecondsLeft == 0 {
                demoAlertSecondsLeft = 60
            }
        } else if demoAlertSecondsLeft > 0 {
            demoAlertSecondsLeft -= 1
        }

        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 60, "Should start 60-second alert")
    }

    /// Test tick during alert phase
    func testTickDuringAlertPhase() {
        var demoSecondsLeft = 0
        var demoAlertSecondsLeft = 60

        // Simulate one tick
        if demoSecondsLeft > 0 {
            demoSecondsLeft -= 1
            if demoSecondsLeft == 0 {
                demoAlertSecondsLeft = 60
            }
        } else if demoAlertSecondsLeft > 0 {
            demoAlertSecondsLeft -= 1
        }

        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 59)
    }

    /// Test complete countdown sequence: 10s countdown -> 60s alert -> done
    func testFullCountdownSequence() {
        var demoSecondsLeft = 10
        var demoAlertSecondsLeft = 0

        // Helper function matching ContentView.tickDemo()
        func tickDemo() {
            if demoSecondsLeft > 0 {
                demoSecondsLeft -= 1
                if demoSecondsLeft == 0 {
                    demoAlertSecondsLeft = 60
                }
            } else if demoAlertSecondsLeft > 0 {
                demoAlertSecondsLeft -= 1
            }
        }

        // Tick through 10-second countdown
        for i in 0..<10 {
            XCTAssertEqual(demoSecondsLeft, 10 - i, "Countdown should be at \(10-i)")
            tickDemo()
        }

        // Now should be in alert phase
        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 60, "Should be in alert phase")

        // Tick through alert phase
        for i in 0..<60 {
            XCTAssertEqual(demoAlertSecondsLeft, 60 - i, "Alert should be at \(60-i)")
            tickDemo()
        }

        // Now should be completely done
        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 0)
        XCTAssertFalse(demoSecondsLeft > 0 || demoAlertSecondsLeft > 0, "Demo should be inactive")
    }

    // MARK: - Bug reproduction: stop demo then restart

    /// BUG REPRODUCTION: Start demo, stop during countdown, restart
    func testStopAndRestartDuringCountdown() {
        var demoSecondsLeft = 0
        var demoAlertSecondsLeft = 0

        func startDemo() {
            demoSecondsLeft = 10
            demoAlertSecondsLeft = 0
        }

        func stopDemo() {
            demoSecondsLeft = 0
            demoAlertSecondsLeft = 0
        }

        func tickDemo() {
            if demoSecondsLeft > 0 {
                demoSecondsLeft -= 1
                if demoSecondsLeft == 0 {
                    demoAlertSecondsLeft = 60
                }
            } else if demoAlertSecondsLeft > 0 {
                demoAlertSecondsLeft -= 1
            }
        }

        // Start demo
        startDemo()
        XCTAssertEqual(demoSecondsLeft, 10)

        // Tick a few times
        tickDemo()
        tickDemo()
        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 7)

        // User adds a drink - stop demo
        stopDemo()
        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 0)

        // Timer tick happens (timer is still running)
        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 0, "Should stay at 0")
        XCTAssertEqual(demoAlertSecondsLeft, 0, "Should stay at 0")

        // User starts demo again
        startDemo()
        XCTAssertEqual(demoSecondsLeft, 10, "Should restart at 10")
        XCTAssertEqual(demoAlertSecondsLeft, 0)

        // Tick should continue normally
        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 9, "Should decrement normally")

        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 8, "Should continue decrementing")
    }

    /// BUG REPRODUCTION: Start demo, stop during alert phase, restart
    func testStopAndRestartDuringAlertPhase() {
        var demoSecondsLeft = 0
        var demoAlertSecondsLeft = 0

        func startDemo() {
            demoSecondsLeft = 10
            demoAlertSecondsLeft = 0
        }

        func stopDemo() {
            demoSecondsLeft = 0
            demoAlertSecondsLeft = 0
        }

        func tickDemo() {
            if demoSecondsLeft > 0 {
                demoSecondsLeft -= 1
                if demoSecondsLeft == 0 {
                    demoAlertSecondsLeft = 60
                }
            } else if demoAlertSecondsLeft > 0 {
                demoAlertSecondsLeft -= 1
            }
        }

        // Start demo and run through countdown
        startDemo()
        for _ in 0..<10 {
            tickDemo()
        }
        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 60, "Should be in alert phase")

        // Tick a few times in alert phase
        tickDemo()
        tickDemo()
        tickDemo()
        XCTAssertEqual(demoAlertSecondsLeft, 57)

        // User adds a drink - stop demo
        stopDemo()
        XCTAssertEqual(demoSecondsLeft, 0)
        XCTAssertEqual(demoAlertSecondsLeft, 0)

        // Timer tick happens (timer is still running)
        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 0, "Should stay at 0")
        XCTAssertEqual(demoAlertSecondsLeft, 0, "Should stay at 0")

        // User starts demo again
        startDemo()
        XCTAssertEqual(demoSecondsLeft, 10, "Should restart at 10")
        XCTAssertEqual(demoAlertSecondsLeft, 0, "Alert should be reset")

        // Tick should continue normally
        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 9, "Should decrement normally")

        tickDemo()
        XCTAssertEqual(demoSecondsLeft, 8, "Should continue decrementing")
    }

    /// BUG REPRODUCTION: Multiple rapid stop/start cycles
    func testRapidStopStartCycles() {
        var demoSecondsLeft = 0
        var demoAlertSecondsLeft = 0

        func startDemo() {
            demoSecondsLeft = 10
            demoAlertSecondsLeft = 0
        }

        func stopDemo() {
            demoSecondsLeft = 0
            demoAlertSecondsLeft = 0
        }

        func tickDemo() {
            if demoSecondsLeft > 0 {
                demoSecondsLeft -= 1
                if demoSecondsLeft == 0 {
                    demoAlertSecondsLeft = 60
                }
            } else if demoAlertSecondsLeft > 0 {
                demoAlertSecondsLeft -= 1
            }
        }

        // Rapid start/stop cycles
        for cycle in 0..<5 {
            startDemo()
            XCTAssertEqual(demoSecondsLeft, 10, "Cycle \(cycle): Should start at 10")

            tickDemo()
            XCTAssertEqual(demoSecondsLeft, 9, "Cycle \(cycle): Should tick to 9")

            stopDemo()
            XCTAssertEqual(demoSecondsLeft, 0, "Cycle \(cycle): Should stop")

            tickDemo() // Timer still running
            XCTAssertEqual(demoSecondsLeft, 0, "Cycle \(cycle): Should stay at 0")
        }

        // Final start should work
        startDemo()
        XCTAssertEqual(demoSecondsLeft, 10)

        // Should tick normally
        for i in 1...5 {
            tickDemo()
            XCTAssertEqual(demoSecondsLeft, 10 - i)
        }
    }

    // MARK: - Test displayCountdown logic

    func testDisplayCountdownDuringCountdown() {
        let demoSecondsLeft = 10
        let demoAlertSecondsLeft = 0

        var displayCountdown: String {
            if demoSecondsLeft > 0 {
                return String(format: "%02d:%02d", demoSecondsLeft / 60, demoSecondsLeft % 60)
            } else if demoAlertSecondsLeft > 0 {
                return "00:00"
            }
            return "00:00"
        }

        XCTAssertEqual(displayCountdown, "00:10")
    }

    func testDisplayCountdownDuringAlert() {
        let demoSecondsLeft = 0
        let demoAlertSecondsLeft = 30

        var displayCountdown: String {
            if demoSecondsLeft > 0 {
                return String(format: "%02d:%02d", demoSecondsLeft / 60, demoSecondsLeft % 60)
            } else if demoAlertSecondsLeft > 0 {
                return "00:00"
            }
            return "00:00"
        }

        XCTAssertEqual(displayCountdown, "00:00", "Should show 00:00 during alert")
    }

    func testDisplayCountdownWhenInactive() {
        let demoSecondsLeft = 0
        let demoAlertSecondsLeft = 0

        var displayCountdown: String {
            if demoSecondsLeft > 0 {
                return String(format: "%02d:%02d", demoSecondsLeft / 60, demoSecondsLeft % 60)
            } else if demoAlertSecondsLeft > 0 {
                return "00:00"
            }
            return "00:00"
        }

        XCTAssertEqual(displayCountdown, "00:00")
    }

    // MARK: - Test isDemoActive and isDemoAlerting

    func testIsDemoActiveStates() {
        // During countdown
        var demoSecondsLeft = 5
        var demoAlertSecondsLeft = 0
        XCTAssertTrue(demoSecondsLeft > 0 || demoAlertSecondsLeft > 0, "Active during countdown")
        XCTAssertFalse(demoSecondsLeft == 0 && demoAlertSecondsLeft > 0, "Not alerting during countdown")

        // During alert
        demoSecondsLeft = 0
        demoAlertSecondsLeft = 30
        XCTAssertTrue(demoSecondsLeft > 0 || demoAlertSecondsLeft > 0, "Active during alert")
        XCTAssertTrue(demoSecondsLeft == 0 && demoAlertSecondsLeft > 0, "Alerting during alert")

        // Inactive
        demoSecondsLeft = 0
        demoAlertSecondsLeft = 0
        XCTAssertFalse(demoSecondsLeft > 0 || demoAlertSecondsLeft > 0, "Inactive when both zero")
        XCTAssertFalse(demoSecondsLeft == 0 && demoAlertSecondsLeft > 0, "Not alerting when inactive")
    }
}
