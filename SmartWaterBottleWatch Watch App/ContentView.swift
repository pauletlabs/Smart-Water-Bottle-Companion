//
//  ContentView.swift
//  SmartWaterBottleWatch Watch App
//
//  Main watch face showing hydration status
//

import SwiftUI
import Combine
import UserNotifications

struct ContentView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var currentTime = Date()
    @State private var showDrinkList = false
    @State private var wasAlerting = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Format the countdown timer
    private var countdownText: String {
        if let timeUntil = sessionManager.hydrationData.currentTimeUntilNextDrink(from: currentTime) {
            let seconds = max(0, Int(timeUntil))
            let mins = seconds / 60
            let secs = seconds % 60
            return String(format: "%02d:%02d", mins, secs)
        }
        return "--:--"
    }

    /// Whether it's time to drink
    private var isAlerting: Bool {
        if let timeUntil = sessionManager.hydrationData.currentTimeUntilNextDrink(from: currentTime) {
            return timeUntil <= 0
        }
        return false
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 4) {
                    // Halo ring - tap to see drink list
                    WatchHaloView(
                        data: sessionManager.hydrationData,
                        currentTime: currentTime
                    )
                    .frame(width: geometry.size.width * 0.85, height: geometry.size.width * 0.85)
                    .onTapGesture {
                        showDrinkList = true
                    }

                    // Countdown timer
                    HStack(spacing: 4) {
                        Image(systemName: isAlerting ? "bell.fill" : "timer")
                            .font(.system(size: 12))
                            .foregroundColor(isAlerting ? .red : .secondary)

                        Text(countdownText)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(isAlerting ? .red : .primary)
                    }
                    .padding(.top, 2)

                    // Sync status (small indicator)
                    if !sessionManager.isReachable {
                        HStack(spacing: 2) {
                            Image(systemName: "iphone.slash")
                                .font(.system(size: 8))
                            Text("Not connected")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationDestination(isPresented: $showDrinkList) {
                DrinkListView(
                    drinks: sessionManager.hydrationData.drinks,
                    totalMl: sessionManager.hydrationData.todayTotalMl
                )
            }
        }
        .onReceive(timer) { time in
            currentTime = time
            checkAlertTransition()
        }
        .onAppear {
            sessionManager.requestUpdate()
            requestNotificationPermission()
        }
    }

    /// Check if we just transitioned to alert state and send notification
    private func checkAlertTransition() {
        if isAlerting && !wasAlerting {
            sendDrinkReminder()
        }
        wasAlerting = isAlerting
    }

    /// Request permission for notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
        }
    }

    /// Send a local notification to remind user to drink
    private func sendDrinkReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Time to Drink!"
        content.body = "Stay hydrated - have a glass of water"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
