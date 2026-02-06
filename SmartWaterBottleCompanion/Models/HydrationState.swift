import Foundation

struct HydrationState {
    let dailyGoalMl: Int
    var todayTotalMl: Int = 0
    let mlPerGlass: Int
    var wakeTime: DateComponents = DateComponents(hour: 7, minute: 0)
    var sleepTime: DateComponents = DateComponents(hour: 21, minute: 0)
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

    func timeUntilNextDrink(from date: Date) -> TimeInterval? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        let wakeHour = wakeTime.hour ?? 7
        let wakeMinute = wakeTime.minute ?? 0
        let sleepHour = sleepTime.hour ?? 21
        let sleepMinute = sleepTime.minute ?? 0

        let currentMinutes = hour * 60 + minute
        let wakeMinutes = wakeHour * 60 + wakeMinute
        let sleepMinutes = sleepHour * 60 + sleepMinute

        // During sleep hours, return nil
        if currentMinutes < wakeMinutes || currentMinutes >= sleepMinutes {
            return nil
        }

        // Calculate remaining glasses needed
        let glassesRemaining = glassesGoal - glassesConsumed
        guard glassesRemaining > 0 else { return nil }

        // Calculate remaining awake time in minutes
        let remainingAwakeMinutes = sleepMinutes - currentMinutes
        guard remainingAwakeMinutes > 0 else { return nil }

        // Distribute remaining drinks evenly across remaining awake time
        let intervalMinutes = Double(remainingAwakeMinutes) / Double(glassesRemaining)

        return intervalMinutes * 60.0  // Convert to seconds
    }
}
