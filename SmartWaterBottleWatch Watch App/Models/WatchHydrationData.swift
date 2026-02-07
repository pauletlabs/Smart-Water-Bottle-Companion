//
//  WatchHydrationData.swift
//  SmartWaterBottleWatch Watch App
//
//  Lightweight hydration data for Watch display
//

import Foundation

/// Hydration data synced from iPhone to Watch
struct WatchHydrationData: Codable {
    let todayTotalMl: Int
    let dailyGoalMl: Int
    let glassesConsumed: Int
    let glassesGoal: Int
    let lastDrinkTime: Date?
    let timeUntilNextDrink: TimeInterval?
    let wakeHour: Int
    let wakeMinute: Int
    let sleepHour: Int
    let sleepMinute: Int
    let drinks: [WatchDrink]
    let timestamp: Date

    /// Progress as fraction 0-1
    var progress: Double {
        guard dailyGoalMl > 0 else { return 0 }
        return min(Double(todayTotalMl) / Double(dailyGoalMl), 1.0)
    }

    /// Current time until next drink, accounting for elapsed time since sync
    func currentTimeUntilNextDrink(from now: Date = Date()) -> TimeInterval? {
        guard let originalTime = timeUntilNextDrink else { return nil }
        let elapsed = now.timeIntervalSince(timestamp)
        return originalTime - elapsed
    }

    /// Create from dictionary (for WatchConnectivity)
    init?(from dictionary: [String: Any]) {
        guard let todayTotalMl = dictionary["todayTotalMl"] as? Int,
              let dailyGoalMl = dictionary["dailyGoalMl"] as? Int,
              let glassesConsumed = dictionary["glassesConsumed"] as? Int,
              let glassesGoal = dictionary["glassesGoal"] as? Int,
              let wakeHour = dictionary["wakeHour"] as? Int,
              let wakeMinute = dictionary["wakeMinute"] as? Int,
              let sleepHour = dictionary["sleepHour"] as? Int,
              let sleepMinute = dictionary["sleepMinute"] as? Int,
              let timestamp = dictionary["timestamp"] as? Date else {
            return nil
        }

        self.todayTotalMl = todayTotalMl
        self.dailyGoalMl = dailyGoalMl
        self.glassesConsumed = glassesConsumed
        self.glassesGoal = glassesGoal
        self.lastDrinkTime = dictionary["lastDrinkTime"] as? Date
        self.timeUntilNextDrink = dictionary["timeUntilNextDrink"] as? TimeInterval
        self.wakeHour = wakeHour
        self.wakeMinute = wakeMinute
        self.sleepHour = sleepHour
        self.sleepMinute = sleepMinute
        self.timestamp = timestamp

        // Parse drinks array
        if let drinksData = dictionary["drinks"] as? [[String: Any]] {
            self.drinks = drinksData.compactMap { WatchDrink(from: $0) }
        } else {
            self.drinks = []
        }
    }

    /// Default empty state
    static var empty: WatchHydrationData {
        WatchHydrationData(
            todayTotalMl: 0,
            dailyGoalMl: 1000,
            glassesConsumed: 0,
            glassesGoal: 5,
            lastDrinkTime: nil,
            timeUntilNextDrink: nil,
            wakeHour: 6,
            wakeMinute: 45,
            sleepHour: 17,
            sleepMinute: 0,
            drinks: [],
            timestamp: Date()
        )
    }

    private init(todayTotalMl: Int, dailyGoalMl: Int, glassesConsumed: Int, glassesGoal: Int,
                 lastDrinkTime: Date?, timeUntilNextDrink: TimeInterval?,
                 wakeHour: Int, wakeMinute: Int, sleepHour: Int, sleepMinute: Int,
                 drinks: [WatchDrink], timestamp: Date) {
        self.todayTotalMl = todayTotalMl
        self.dailyGoalMl = dailyGoalMl
        self.glassesConsumed = glassesConsumed
        self.glassesGoal = glassesGoal
        self.lastDrinkTime = lastDrinkTime
        self.timeUntilNextDrink = timeUntilNextDrink
        self.wakeHour = wakeHour
        self.wakeMinute = wakeMinute
        self.sleepHour = sleepHour
        self.sleepMinute = sleepMinute
        self.drinks = drinks
        self.timestamp = timestamp
    }
}

/// Lightweight drink event for Watch
struct WatchDrink: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let amountMl: Int

    init?(from dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let id = UUID(uuidString: idString),
              let timestamp = dictionary["timestamp"] as? Date,
              let amountMl = dictionary["amountMl"] as? Int else {
            return nil
        }
        self.id = id
        self.timestamp = timestamp
        self.amountMl = amountMl
    }
}
