import Foundation
import Combine

/// Manages the demo countdown timer independently of the view lifecycle
/// This fixes the bug where Timer.publish on a SwiftUI view can get stuck
/// when the view rebuilds due to state changes
@MainActor
class DemoCountdownManager: ObservableObject {
    @Published private(set) var demoSecondsLeft: Int = 0
    @Published private(set) var demoAlertSecondsLeft: Int = 0

    private var timer: Timer?

    /// Callback to sync state to watch - set by ContentView
    var onStateChange: (() -> Void)?

    /// Is demo mode active (either counting down or alerting)?
    var isDemoActive: Bool {
        demoSecondsLeft > 0 || demoAlertSecondsLeft > 0
    }

    /// Should the alert state be shown?
    var isDemoAlerting: Bool {
        demoSecondsLeft == 0 && demoAlertSecondsLeft > 0
    }

    /// What to display on the countdown (formatted as MM:SS)
    /// Returns nil when not in demo mode
    var displayCountdown: String? {
        if demoSecondsLeft > 0 {
            return String(format: "%02d:%02d", demoSecondsLeft / 60, demoSecondsLeft % 60)
        } else if demoAlertSecondsLeft > 0 {
            return "00:00"
        }
        return nil
    }

    init() {}

    /// Start the 10-second demo countdown
    func startDemo() {
        // Stop any existing timer first
        timer?.invalidate()

        // Reset state
        demoSecondsLeft = 10
        demoAlertSecondsLeft = 0

        // Sync to watch at start
        onStateChange?()

        // Create timer and add to .common run loop mode
        // This ensures the timer fires even during scrolling/UI interactions
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Stop demo and clear alert
    func stopDemo() {
        timer?.invalidate()
        timer = nil
        demoSecondsLeft = 0
        demoAlertSecondsLeft = 0

        // Sync to watch when stopped
        onStateChange?()
    }

    /// Called every second by timer
    private func tick() {
        if demoSecondsLeft > 0 {
            demoSecondsLeft -= 1
            // When countdown reaches 0, start 60-second alert
            if demoSecondsLeft == 0 {
                demoAlertSecondsLeft = 60
                // Sync to watch when alert phase starts
                onStateChange?()
            }
        } else if demoAlertSecondsLeft > 0 {
            demoAlertSecondsLeft -= 1
            // When alert finishes, stop the timer
            if demoAlertSecondsLeft == 0 {
                timer?.invalidate()
                timer = nil
                // Sync to watch when demo ends
                onStateChange?()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
