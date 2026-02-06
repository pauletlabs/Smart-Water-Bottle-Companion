import SwiftUI

struct SettingsView: View {
    @Binding var state: HydrationState
    @Environment(\.dismiss) private var dismiss

    @State private var wakeHour: Int = 7
    @State private var wakeMinute: Int = 0
    @State private var sleepHour: Int = 21
    @State private var sleepMinute: Int = 0
    @State private var goalGlasses: Int = 8

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper("Glasses: \(goalGlasses)", value: $goalGlasses, in: 4...16)
                    Text("Total: \(goalGlasses * state.mlPerGlass) ml")
                        .foregroundStyle(.secondary)
                }

                Section("Wake Time") {
                    HStack {
                        Picker("Hour", selection: $wakeHour) {
                            ForEach(4...11, id: \.self) { hour in
                                Text("\(hour):00").tag(hour)
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

                Section("Sleep Time") {
                    HStack {
                        Picker("Hour", selection: $sleepHour) {
                            ForEach(18...23, id: \.self) { hour in
                                Text("\(hour):00").tag(hour)
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
        wakeHour = state.wakeTime.hour ?? 7
        wakeMinute = state.wakeTime.minute ?? 0
        sleepHour = state.sleepTime.hour ?? 21
        sleepMinute = state.sleepTime.minute ?? 0
        goalGlasses = state.glassesGoal
    }

    private func saveSettings() {
        var updatedState = HydrationState(
            dailyGoalMl: goalGlasses * state.mlPerGlass,
            mlPerGlass: state.mlPerGlass
        )
        updatedState.todayTotalMl = state.todayTotalMl
        updatedState.wakeTime = DateComponents(hour: wakeHour, minute: wakeMinute)
        updatedState.sleepTime = DateComponents(hour: sleepHour, minute: sleepMinute)
        state = updatedState
    }
}

#Preview {
    SettingsView(state: .constant(HydrationState(dailyGoalMl: 1600)))
}
