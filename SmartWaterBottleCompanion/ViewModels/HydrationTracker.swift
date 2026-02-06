import Foundation
import Combine

@MainActor
class HydrationTracker: ObservableObject {
    @Published var state: HydrationState
    @Published var isPolling: Bool = false
    @Published var connectionError: String?

    private var realBLEManager: BLEManager?
    private var mockBLEManager: MockBLEManager?
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Initialize with real BLE manager (for device use)
    init(dailyGoalMl: Int, mlPerGlass: Int = 200) {
        self.state = HydrationState(dailyGoalMl: dailyGoalMl, mlPerGlass: mlPerGlass)
        self.realBLEManager = BLEManager()

        // Observe BLE errors
        self.realBLEManager?.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                Task { @MainActor in
                    self?.connectionError = error
                }
            }
            .store(in: &cancellables)
    }

    /// Initialize with mock BLE manager (for simulator/testing)
    init(dailyGoalMl: Int, mlPerGlass: Int = 200, bleManager: MockBLEManager) {
        self.state = HydrationState(dailyGoalMl: dailyGoalMl, mlPerGlass: mlPerGlass)
        self.mockBLEManager = bleManager

        // Observe mock BLE errors
        bleManager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                Task { @MainActor in
                    self?.connectionError = error
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Polling Control

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollOnce()
        scheduleNextPoll()
    }

    func stopPolling() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
        realBLEManager?.disconnect()
        mockBLEManager?.disconnect()
    }

    func pollOnce() {
        connectionError = nil

        let completion: ([DrinkEvent]) -> Void = { [weak self] drinks in
            Task { @MainActor in
                self?.processNewDrinks(drinks)
            }
        }

        if let mock = mockBLEManager {
            mock.poll(completion: completion)
        } else {
            realBLEManager?.poll(completion: completion)
        }
    }

    // MARK: - Process Drinks

    func processNewDrinks(_ drinks: [DrinkEvent]) {
        let calendar = Calendar.current
        let today = Date()

        // Filter drinks to today only
        let todayDrinks = drinks.filter { drink in
            guard let drinkDate = drink.timestamp else { return false }
            return calendar.isDate(drinkDate, inSameDayAs: today)
        }

        // Add new drinks, avoiding duplicates
        var newTotal = 0
        var latestDrinkTime: Date?

        for drink in todayDrinks {
            // Check for duplicate by comparing all fields except id
            let isDuplicate = state.drinkHistory.contains { existing in
                existing.month == drink.month &&
                existing.day == drink.day &&
                existing.hour == drink.hour &&
                existing.minute == drink.minute &&
                existing.second == drink.second &&
                existing.amountMl == drink.amountMl
            }

            // Also check by ID for drinks we may have already processed
            let idExists = state.drinkHistory.contains { $0.id == drink.id }

            if !isDuplicate && !idExists {
                state.drinkHistory.append(drink)
            }
        }

        // Recalculate total from all drinks in history
        newTotal = state.drinkHistory.reduce(0) { $0 + Int($1.amountMl) }
        state.todayTotalMl = newTotal

        // Update last drink time to the latest in history
        latestDrinkTime = state.drinkHistory
            .compactMap { $0.timestamp }
            .max()
        state.lastDrinkTime = latestDrinkTime
    }

    // MARK: - Adaptive Poll Interval

    func calculatePollInterval(timeUntilReminder: TimeInterval) -> TimeInterval {
        switch timeUntilReminder {
        case _ where timeUntilReminder <= 0:
            return 60  // 1 minute when at or past reminder time
        case _ where timeUntilReminder < 5 * 60:
            return 2 * 60  // 2 minutes when less than 5 minutes
        case _ where timeUntilReminder <= 10 * 60:
            return 5 * 60  // 5 minutes when 5-10 minutes
        default:
            return 10 * 60  // 10 minutes when more than 10 minutes
        }
    }

    // MARK: - Convenience Properties

    /// Returns today's drink history sorted by time (most recent first)
    var todayDrinks: [DrinkEvent] {
        state.drinkHistory.sorted { drink1, drink2 in
            guard let time1 = drink1.timestamp, let time2 = drink2.timestamp else {
                return false
            }
            return time1 > time2
        }
    }

    // MARK: - Reset

    func resetForNewDay() {
        state.todayTotalMl = 0
        state.drinkHistory = []
        state.lastDrinkTime = nil
    }

    // MARK: - Private

    private func scheduleNextPoll() {
        pollTimer?.invalidate()

        let timeUntilReminder = state.timeUntilNextDrink(from: Date()) ?? 10 * 60
        let pollInterval = calculatePollInterval(timeUntilReminder: timeUntilReminder)

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPolling else { return }
                self.pollOnce()
                self.scheduleNextPoll()
            }
        }
    }
}
