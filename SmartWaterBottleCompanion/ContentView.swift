//
//  ContentView.swift
//  SmartWaterBottleCompanion
//
//  Created by Charlie Normand on 22/01/2026.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var tracker: HydrationTracker
    @StateObject private var mockBLE: MockBLEManager
    @StateObject private var demoManager = DemoCountdownManager()
    @StateObject private var bleScanner = BLEManager()  // For discovery scanning
    @State private var showSettings = false
    @State private var showBLEDiscovery = false

    /// Current time - updated every second to refresh countdown display
    @State private var currentTime = Date()

    /// Timer to refresh the countdown display
    let displayTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Show simulator controls (ant menu) - persisted, defaults to ON
    @AppStorage("showSimulatorControls") private var showSimulatorControls: Bool = true

    /// What to show on the countdown display
    private var displayCountdown: String {
        if demoManager.demoSecondsLeft > 0 {
            return String(format: "%02d:%02d", demoManager.demoSecondsLeft / 60, demoManager.demoSecondsLeft % 60)
        } else if demoManager.demoAlertSecondsLeft > 0 {
            return "00:00"
        } else if let timeUntil = tracker.state.timeUntilNextDrink(from: currentTime) {
            let secs = max(0, Int(timeUntil))  // Don't show negative
            return String(format: "%02d:%02d", secs / 60, secs % 60)
        }
        return "00:00"
    }

    init() {
        let mock = MockBLEManager()
        _mockBLE = StateObject(wrappedValue: mock)

        #if targetEnvironment(simulator)
        // Always use mock in simulator
        _tracker = StateObject(wrappedValue: HydrationTracker(dailyGoalMl: 1600, bleManager: mock))
        #else
        // On device, use real BLE
        _tracker = StateObject(wrappedValue: HydrationTracker(dailyGoalMl: 1600))
        #endif
    }

    /// Whether the alert state is active (time to drink!)
    private var isAlerting: Bool {
        demoManager.isDemoAlerting || (tracker.state.timeUntilNextDrink(from: currentTime) ?? 1) <= 0
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
                if demoManager.isDemoActive || tracker.state.timeUntilNextDrink(from: currentTime) != nil {
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

                // BLE Connection status indicator
                HStack(spacing: 8) {
                    switch bleScanner.connectionState {
                    case .connected:
                        Image(systemName: "drop.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected to bottle")
                            .font(.caption)
                            .foregroundColor(.green)
                    case .connecting:
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .scanning:
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .disconnected:
                        if bleScanner.savedBottleIdentifier != nil {
                            Image(systemName: "drop.circle")
                                .foregroundColor(.secondary)
                            Text("Bottle disconnected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .foregroundColor(.secondary)
                            Text("No bottle paired")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .error(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange)
                    case .polling:
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reading data...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)

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
                // Simulator controls in toolbar (controlled by Settings toggle)
                if showSimulatorControls {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button {
                                tracker.addSimulatedDrink(amountMl: 200)
                                demoManager.stopDemo()  // Clear alert on drink
                            } label: {
                                Label("Add 200ml", systemImage: "drop.fill")
                            }
                            Button {
                                tracker.addSimulatedDrink(amountMl: 150)
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
                                tracker.clearAllDrinks()
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
                    HStack(spacing: 12) {
                        // BLE Discovery button (device only)
                        #if !targetEnvironment(simulator)
                        Button {
                            showBLEDiscovery = true
                            bleScanner.discoveryMode = true
                            bleScanner.startScanning()
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                        }
                        #endif

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(state: $tracker.state)
            }
            .sheet(isPresented: $showBLEDiscovery) {
                BLEDiscoveryView(bleManager: bleScanner)
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
            .onReceive(displayTimer) { time in
                currentTime = time
            }
            .onReceive(bleScanner.$receivedDrinks) { drinks in
                // Process drink events from the bottle
                guard !drinks.isEmpty else { return }
                print("📥 Received \(drinks.count) drinks from bottle!")

                // Add drinks to tracker
                tracker.processNewDrinks(drinks)

                // Clear any active alert since we detected a drink
                demoManager.stopDemo()
            }
            .onAppear {
                #if !targetEnvironment(simulator)
                // Auto-connect to saved bottle on app launch
                if bleScanner.savedBottleIdentifier != nil {
                    bleScanner.reconnectToSavedBottle()
                }
                #endif
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
