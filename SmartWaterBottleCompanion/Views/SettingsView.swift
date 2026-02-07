import SwiftUI

struct SettingsView: View {
    @Binding var state: HydrationState
    @Environment(\.dismiss) private var dismiss

    @State private var wakeHour: Int = 6
    @State private var wakeMinute: Int = 45
    @State private var sleepHour: Int = 17
    @State private var sleepMinute: Int = 0
    @State private var goalGlasses: Int = 5

    /// Show simulator controls (ant menu) - persisted
    @AppStorage("showSimulatorControls") private var showSimulatorControls: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper("Glasses: \(goalGlasses)", value: $goalGlasses, in: 4...16)
                    Text("Total: \(goalGlasses * state.mlPerGlass) ml")
                        .foregroundStyle(.secondary)
                }

                Section("Start Measuring From") {
                    HStack {
                        Picker("Hour", selection: $wakeHour) {
                            ForEach(0...23, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)

                        Picker("Minute", selection: $wakeMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: ":%02d", minute)).tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 120)
                }

                Section("Target Complete Time") {
                    HStack {
                        Picker("Hour", selection: $sleepHour) {
                            ForEach(0...23, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)

                        Picker("Minute", selection: $sleepMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: ":%02d", minute)).tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 120)
                    Text("Aim to complete your goal by this time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Developer") {
                    Toggle("Show Simulator Controls", isOn: $showSimulatorControls)
                    Text("Shows the 🐜 menu for testing demos and adding simulated drinks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Glass size: \(state.mlPerGlass) ml")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    private func loadSettings() {
        wakeHour = state.wakeTime.hour ?? 6
        wakeMinute = state.wakeTime.minute ?? 45
        sleepHour = state.sleepTime.hour ?? 17
        sleepMinute = state.sleepTime.minute ?? 0
        goalGlasses = state.glassesGoal
    }

    private func saveSettings() {
        var updatedState = HydrationState(
            dailyGoalMl: goalGlasses * state.mlPerGlass,
            mlPerGlass: state.mlPerGlass
        )
        // Preserve existing data
        updatedState.todayTotalMl = state.todayTotalMl
        updatedState.drinkHistory = state.drinkHistory
        updatedState.lastDrinkTime = state.lastDrinkTime
        // Apply new settings
        updatedState.wakeTime = DateComponents(hour: wakeHour, minute: wakeMinute)
        updatedState.sleepTime = DateComponents(hour: sleepHour, minute: sleepMinute)
        state = updatedState

        // Sync updated settings to Apple Watch
        let drinks = state.drinkHistory.compactMap { drink -> DrinkEvent? in
            return drink
        }
        PhoneSessionManager.shared.sendHydrationData(state: updatedState, drinks: drinks)
    }
}

#Preview {
    SettingsView(state: .constant(HydrationState(dailyGoalMl: 1000)))
}
