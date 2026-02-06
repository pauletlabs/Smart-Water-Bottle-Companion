//
//  ContentView.swift
//  SmartWaterBottleCompanion
//
//  Created by Charlie Normand on 22/01/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tracker: HydrationTracker
    @StateObject private var mockBLE: MockBLEManager
    @StateObject private var demoManager = DemoCountdownManager()
    @State private var showSettings = false
    @State private var showSimulator = false

    /// What to show on the countdown display
    private var displayCountdown: String {
        if demoManager.demoSecondsLeft > 0 {
            return String(format: "%02d:%02d", demoManager.demoSecondsLeft / 60, demoManager.demoSecondsLeft % 60)
        } else if demoManager.demoAlertSecondsLeft > 0 {
            return "00:00"
        } else if let timeUntil = tracker.state.timeUntilNextDrink(from: Date()) {
            let secs = Int(timeUntil)
            return String(format: "%02d:%02d", secs / 60, secs % 60)
        }
        return "00:00"
    }

    /// Use simulator mode when running on iOS Simulator or when explicitly enabled
    private let isSimulatorMode: Bool

    init() {
        let mock = MockBLEManager()
        _mockBLE = StateObject(wrappedValue: mock)

        #if targetEnvironment(simulator)
        // Always use mock in simulator
        _tracker = StateObject(wrappedValue: HydrationTracker(dailyGoalMl: 1600, bleManager: mock))
        isSimulatorMode = true
        #else
        // On device, use real BLE (can add debug toggle later)
        _tracker = StateObject(wrappedValue: HydrationTracker(dailyGoalMl: 1600))
        isSimulatorMode = false
        #endif
    }

    /// Whether the alert state is active (time to drink!)
    private var isAlerting: Bool {
        demoManager.isDemoAlerting || (tracker.state.timeUntilNextDrink(from: Date()) ?? 1) <= 0
    }

    var body: some View {
        RainbowBorderView(isActive: isAlerting, borderWidth: 20) {
            NavigationStack {
                VStack(spacing: 20) {
                    // Halo ring progress indicator
                    HaloRingView(
                        progress: tracker.state.progress,
                        glassesConsumed: tracker.state.glassesConsumed,
                        glassesGoal: tracker.state.glassesGoal,
                        isAlerting: isAlerting
                    )
                .frame(width: 200, height: 200)
                .padding(.top, 20)

                // Countdown timer display
                if demoManager.isDemoActive || tracker.state.timeUntilNextDrink(from: Date()) != nil {
                    VStack(spacing: 4) {
                        Text(displayCountdown)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(isAlerting ? .red : .primary)

                        Text(demoManager.isDemoActive ? "DEMO MODE" : "until next drink")
                            .font(.subheadline)
                            .foregroundColor(demoManager.isDemoActive ? .orange : .secondary)
                    }
                } else {
                    Text("Outside drinking hours")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding()
                }

                Divider()
                    .padding(.horizontal)

                // Today section with drink history
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.headline)
                        .padding(.horizontal)

                    if tracker.todayDrinks.isEmpty {
                        Text("No drinks recorded yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(tracker.todayDrinks) { drink in
                                    DrinkRowView(drink: drink)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 200)
                    }
                }

                Spacer()

                // Connection status indicator
                if tracker.isPolling {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting to bottle...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                }

                // Error display
                if let error = tracker.connectionError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Hydration")
            .toolbar {
                // Simulator controls in toolbar (simulator mode only)
                if isSimulatorMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button {
                                mockBLE.simulateDrink(amountMl: 200)
                                tracker.pollOnce()
                                demoManager.stopDemo()  // Clear alert on drink
                            } label: {
                                Label("Add 200ml", systemImage: "drop.fill")
                            }
                            Button {
                                mockBLE.simulateDrink(amountMl: 150)
                                tracker.pollOnce()
                                demoManager.stopDemo()  // Clear alert on drink
                            } label: {
                                Label("Add 150ml", systemImage: "drop")
                            }
                            Button {
                                demoManager.startDemo()
                            } label: {
                                Label("10s Demo", systemImage: "play.circle.fill")
                            }
                            Divider()
                            Button(role: .destructive) {
                                mockBLE.clearSimulatedDrinks()
                                tracker.pollOnce()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ant.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(state: $tracker.state)
            }
            .overlay(alignment: .bottom) {
                // Alert banner as overlay at bottom
                if isAlerting {
                    AlertBannerView()
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.5), value: isAlerting)
                }
            }
        }
        } // RainbowBorderView
    }
}

struct DrinkRowView: View {
    let drink: DrinkEvent

    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(drink))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(drink.amountMl) ml")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func formatTime(_ drink: DrinkEvent) -> String {
        if let timestamp = drink.timestamp {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        }
        return String(format: "%02d:%02d", drink.hour, drink.minute)
    }
}

#Preview {
    ContentView()
}
