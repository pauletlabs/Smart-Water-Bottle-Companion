//
//  ContentView.swift
//  SmartWaterBottleCompanion
//
//  Created by Charlie Normand on 22/01/2026.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var tracker = HydrationTracker(dailyGoalMl: 1600)
    @State private var showSettings = false
    @State private var countdown: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Halo ring progress indicator
                HaloRingView(
                    progress: tracker.state.progress,
                    glassesConsumed: tracker.state.glassesConsumed,
                    glassesGoal: tracker.state.glassesGoal,
                    isAlerting: countdown <= 0 && tracker.state.timeUntilNextDrink(from: Date()) != nil
                )
                .frame(width: 200, height: 200)
                .padding(.top, 20)

                // Countdown timer display
                if let _ = tracker.state.timeUntilNextDrink(from: Date()) {
                    VStack(spacing: 4) {
                        Text(formatCountdown(countdown))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("until next drink")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
        }
        .onReceive(timer) { _ in
            updateCountdown()
        }
        .onAppear {
            updateCountdown()
        }
    }

    private func updateCountdown() {
        if let timeUntil = tracker.state.timeUntilNextDrink(from: Date()) {
            countdown = max(0, timeUntil)
        } else {
            countdown = 0
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
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
