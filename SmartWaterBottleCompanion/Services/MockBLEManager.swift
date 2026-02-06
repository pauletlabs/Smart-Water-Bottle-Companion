import Foundation
import Combine

/// Mock BLE Manager for testing without physical water bottle
/// Simulates drink events for end-to-end UI testing
@MainActor
class MockBLEManager: ObservableObject, BLEManaging {
    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var lastError: String?

    /// Accumulated simulated drinks for the current session
    @Published private(set) var simulatedDrinks: [DrinkEvent] = []

    /// Whether to simulate connection failures (for error testing)
    var simulateFailure = false

    /// Delay before returning poll results (simulates BLE latency)
    var pollDelay: TimeInterval = 0.5

    private var onDrinksReceived: (([DrinkEvent]) -> Void)?

    func poll(completion: @escaping ([DrinkEvent]) -> Void) {
        self.onDrinksReceived = completion
        connectionState = .scanning

        // Simulate BLE connection sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            if self.simulateFailure {
                self.connectionState = .error("Simulated connection failure")
                self.lastError = "Could not connect to simulated bottle"
                completion([])
                return
            }

            self.connectionState = .connecting
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.simulateFailure else { return }
            self.connectionState = .connected
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pollDelay) { [weak self] in
            guard let self, !self.simulateFailure else { return }
            self.connectionState = .polling
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pollDelay + 0.3) { [weak self] in
            guard let self, !self.simulateFailure else { return }
            self.finishPolling()
        }
    }

    func disconnect() {
        connectionState = .disconnected
        onDrinksReceived = nil
    }

    // MARK: - Simulation Controls

    /// Simulate a drink event with the given amount
    func simulateDrink(amountMl: UInt8 = 200) {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: now)

        let drink = DrinkEvent(
            month: UInt8(components.month ?? 1),
            day: UInt8(components.day ?? 1),
            hour: UInt8(components.hour ?? 12),
            minute: UInt8(components.minute ?? 0),
            second: UInt8(components.second ?? 0),
            amountMl: amountMl
        )

        simulatedDrinks.append(drink)
    }

    /// Simulate multiple drinks at once
    func simulateDrinks(_ amounts: [UInt8]) {
        for amount in amounts {
            simulateDrink(amountMl: amount)
        }
    }

    /// Clear all simulated drinks (reset for new day)
    func clearSimulatedDrinks() {
        simulatedDrinks.removeAll()
    }

    /// Generate a random drink (50-300ml)
    func simulateRandomDrink() {
        let amount = UInt8.random(in: 50...255)
        simulateDrink(amountMl: amount)
    }

    // MARK: - Private

    private func finishPolling() {
        connectionState = .disconnected
        onDrinksReceived?(simulatedDrinks)
        onDrinksReceived = nil
    }
}
