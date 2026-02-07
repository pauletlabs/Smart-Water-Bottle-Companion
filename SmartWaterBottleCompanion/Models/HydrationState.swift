import Foundation

struct HydrationState {
    let dailyGoalMl: Int
    var todayTotalMl: Int = 0
    let mlPerGlass: Int
    /// Start measuring from this time (previously "wake time")
    var wakeTime: DateComponents = DateComponents(hour: 6, minute: 45)
    /// Target complete time - aim to finish goal by this time (previously "sleep time")
    var sleepTime: DateComponents = DateComponents(hour: 17, minute: 0)
    var drinkHistory: [DrinkEvent] = []
    var lastDrinkTime: Date?

    init(dailyGoalMl: Int, mlPerGlass: Int = 200) {
        self.dailyGoalMl = dailyGoalMl
        self.mlPerGlass = mlPerGlass
    }

    var progress: Double {
        guard dailyGoalMl > 0 else { return 0.0 }
        return min(Double(todayTotalMl) / Double(dailyGoalMl), 1.0)
    }

    var glassesConsumed: Int {
        guard mlPerGlass > 0 else { return 0 }
        return todayTotalMl / mlPerGlass
    }

    var glassesGoal: Int {
        guard mlPerGlass > 0 else { return 0 }
        return dailyGoalMl / mlPerGlass
    }

    /// Maximum interval between drinks (45 minutes)
    static let maxIntervalSeconds: TimeInterval = 45 * 60

    func timeUntilNextDrink(from date: Date) -> TimeInterval? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        let wakeHour = wakeTime.hour ?? 6
        let wakeMinute = wakeTime.minute ?? 45
        let sleepHour = sleepTime.hour ?? 17
        let sleepMinute = sleepTime.minute ?? 0

        let currentMinutes = hour * 60 + minute
        let wakeMinutes = wakeHour * 60 + wakeMinute
        let sleepMinutes = sleepHour * 60 + sleepMinute

        // Before start time, return nil (not tracking yet)
        if currentMinutes < wakeMinutes {
            return nil
        }

        // After target time, continue tracking but use 45-min intervals
        // (goal should be complete but we still show countdown)
        let effectiveEndMinutes: Int
        if currentMinutes >= sleepMinutes {
            // Past target time - use end of day as effective end
            effectiveEndMinutes = 24 * 60
        } else {
            effectiveEndMinutes = sleepMinutes
        }

        // Calculate ideal interval based on remaining glasses
        let glassesRemaining = max(glassesGoal - glassesConsumed, 1)  // At least 1 to avoid division by zero
        let remainingAwakeMinutes = effectiveEndMinutes - currentMinutes
        guard remainingAwakeMinutes > 0 else { return nil }

        // Ideal interval = remaining time / remaining glasses
        let idealIntervalSeconds = (Double(remainingAwakeMinutes) / Double(glassesRemaining)) * 60.0

        // Cap at 45 minutes max
        let cappedIntervalSeconds = min(idealIntervalSeconds, Self.maxIntervalSeconds)

        // Calculate time since last drink (or since wake time if no drinks today)
        let referenceTime: Date
        if let lastDrink = lastDrinkTime {
            referenceTime = lastDrink
        } else {
            // No drinks today - use wake time as reference
            var wakeComponents = calendar.dateComponents([.year, .month, .day], from: date)
            wakeComponents.hour = wakeHour
            wakeComponents.minute = wakeMinute
            referenceTime = calendar.date(from: wakeComponents) ?? date
        }

        let timeSinceReference = date.timeIntervalSince(referenceTime)
        let timeRemaining = cappedIntervalSeconds - timeSinceReference

        return timeRemaining  // Can be negative if overdue
    }
}
