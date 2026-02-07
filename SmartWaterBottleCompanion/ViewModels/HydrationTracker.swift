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

        print("🔄 processNewDrinks called with \(drinks.count) drinks")

        // Filter drinks to today only
        let todayDrinks = drinks.filter { drink in
            guard let drinkDate = drink.timestamp else {
                print("   ⚠️ Drink has no timestamp, skipping")
                return false
            }
            let isToday = calendar.isDate(drinkDate, inSameDayAs: today)
            print("   📅 Drink at \(drink.hour):\(drink.minute) - isToday: \(isToday)")
            return isToday
        }

        print("   📊 \(todayDrinks.count) drinks from today")

        // Add new drinks, avoiding duplicates
        var addedCount = 0

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
                addedCount += 1
                print("   ✅ Added drink: \(drink.amountMl)ml at \(drink.hour):\(drink.minute)")
            }
        }

        // Recalculate total from all drinks in history
        let newTotal = state.drinkHistory.reduce(0) { $0 + Int($1.amountMl) }
        state.todayTotalMl = newTotal

        // Update last drink time to the latest in history
        let latestDrinkTime = state.drinkHistory
            .compactMap { $0.timestamp }
            .max()
        state.lastDrinkTime = latestDrinkTime

        print("   📈 State updated: \(addedCount) new drinks, total \(newTotal)ml, \(state.drinkHistory.count) in history")

        // Force SwiftUI to notice the change by reassigning state
        // (struct mutation should trigger @Published, but let's be explicit)
        objectWillChange.send()

        // Sync to Apple Watch
        syncToWatch()
    }

    // MARK: - Watch Sync

    /// Send current state to Apple Watch
    func syncToWatch() {
        PhoneSessionManager.shared.sendHydrationData(state: state, drinks: todayDrinks)
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

    // MARK: - Simulated Drinks (for testing/demo)

    /// Add a simulated drink directly (bypasses BLE)
    func addSimulatedDrink(amountMl: Int) {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: now)

        let drink = DrinkEvent(
            month: UInt8(components.month ?? 1),
            day: UInt8(components.day ?? 1),
            hour: UInt8(components.hour ?? 0),
            minute: UInt8(components.minute ?? 0),
            second: UInt8(components.second ?? 0),
            amountMl: UInt8(min(amountMl, 255))
        )

        state.drinkHistory.append(drink)
        state.todayTotalMl += amountMl
        state.lastDrinkTime = now
        syncToWatch()
    }

    /// Clear all simulated/recorded drinks (for testing)
    func clearAllDrinks() {
        state.drinkHistory = []
        state.todayTotalMl = 0
        state.lastDrinkTime = nil
        syncToWatch()
    }

    // MARK: - Reset

    func resetForNewDay() {
        state.todayTotalMl = 0
        state.drinkHistory = []
        state.lastDrinkTime = nil
        syncToWatch()
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
