//
//  PhoneSessionManager.swift
//  SmartWaterBottleCompanion
//
//  Manages WatchConnectivity session on the iPhone side
//

import Foundation
import Combine

#if !targetEnvironment(simulator)
import WatchConnectivity
#endif

@MainActor
class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    @Published var isWatchReachable: Bool = false
    @Published var isWatchAppInstalled: Bool = false

    #if !targetEnvironment(simulator)
    private var session: WCSession?
    #endif
    private var pendingHydrationData: [String: Any]?

    override init() {
        super.init()
        #if !targetEnvironment(simulator)
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        #endif
    }

    /// Send hydration data to Watch
    func sendHydrationData(state: HydrationState, drinks: [DrinkEvent]) {
        sendHydrationDataWithOverride(state: state, drinks: drinks, timeUntilNextDrink: nil)
    }

    /// Send hydration data to Watch with optional override for timeUntilNextDrink (for demo mode)
    func sendHydrationDataWithOverride(state: HydrationState, drinks: [DrinkEvent], timeUntilNextDrink: TimeInterval?) {
        #if targetEnvironment(simulator)
        print("⌚ Watch sync skipped (simulator)")
        #else
        guard let session = session, session.activationState == .activated else {
            print("⌚ Watch session not activated")
            return
        }

        let data = buildHydrationDataDictionary(state: state, drinks: drinks, timeUntilNextDrinkOverride: timeUntilNextDrink)
        pendingHydrationData = data

        // Try multiple methods to ensure delivery
        do {
            // Application context - persists and delivers when watch wakes
            try session.updateApplicationContext(data)
            print("✅ Sent application context to Watch")
        } catch {
            print("❌ Failed to update application context: \(error.localizedDescription)")
        }

        // If watch is reachable, also send direct message for immediate update
        if session.isReachable {
            session.sendMessage(data, replyHandler: nil) { error in
                print("❌ Failed to send message: \(error.localizedDescription)")
            }
            print("📤 Sent direct message to Watch")
        }
        #endif
    }

    /// Build dictionary from HydrationState for WatchConnectivity
    private func buildHydrationDataDictionary(state: HydrationState, drinks: [DrinkEvent], timeUntilNextDrinkOverride: TimeInterval? = nil) -> [String: Any] {
        var data: [String: Any] = [
            "todayTotalMl": state.todayTotalMl,
            "dailyGoalMl": state.dailyGoalMl,
            "glassesConsumed": state.glassesConsumed,
            "glassesGoal": state.glassesGoal,
            "wakeHour": state.wakeTime.hour ?? 6,
            "wakeMinute": state.wakeTime.minute ?? 45,
            "sleepHour": state.sleepTime.hour ?? 17,
            "sleepMinute": state.sleepTime.minute ?? 0,
            "timestamp": Date()
        ]

        if let lastDrink = state.lastDrinkTime {
            data["lastDrinkTime"] = lastDrink
        }

        // Use override if provided (for demo mode), otherwise calculate from state
        if let override = timeUntilNextDrinkOverride {
            data["timeUntilNextDrink"] = override
        } else if let timeUntil = state.timeUntilNextDrink(from: Date()) {
            data["timeUntilNextDrink"] = timeUntil
        }

        // Convert drinks to dictionary array
        let drinksArray: [[String: Any]] = drinks.compactMap { drink in
            guard let timestamp = drink.timestamp else { return nil }
            return [
                "id": drink.id.uuidString,
                "timestamp": timestamp,
                "amountMl": Int(drink.amountMl)
            ]
        }
        data["drinks"] = drinksArray

        return data
    }
}

#if !targetEnvironment(simulator)
// MARK: - WCSessionDelegate
extension PhoneSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("❌ Phone session activation failed: \(error.localizedDescription)")
            } else {
                print("✅ Phone session activated: \(activationState.rawValue)")
                isWatchReachable = session.isReachable
                isWatchAppInstalled = session.isWatchAppInstalled
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("⌚ Watch session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("⌚ Watch session deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
            print("⌚ Watch reachability: \(session.isReachable)")

            // Send pending data when watch becomes reachable
            if session.isReachable, let data = pendingHydrationData {
                session.sendMessage(data, replyHandler: nil) { error in
                    print("❌ Failed to send pending data: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Handle requests from Watch
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            if message["request"] as? String == "hydrationData" {
                if let data = pendingHydrationData {
                    replyHandler(data)
                    print("📤 Replied to Watch data request")
                } else {
                    replyHandler([:])
                }
            }
        }
    }
}
#endif
