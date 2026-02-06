import SwiftUI

/// Debug view for simulating BLE drink events
/// Only shown when using MockBLEManager (simulator/debug builds)
struct SimulatorControlView: View {
    @ObservedObject var mockManager: MockBLEManager
    let onDrinkSimulated: () -> Void
    let onDemoCountdown: () -> Void

    @State private var selectedAmount: Double = 200

    var body: some View {
        VStack(spacing: 12) {
            // Header with demo button
            HStack {
                Image(systemName: "ant.circle.fill")
                    .foregroundColor(.orange)
                Text("BLE Simulator")
                    .font(.headline)
                Spacer()

                Button {
                    onDemoCountdown()
                } label: {
                    Label("10s Demo", systemImage: "play.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Divider()

            // Amount slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Amount: \(Int(selectedAmount)) ml")
                    .font(.subheadline)
                Slider(value: $selectedAmount, in: 50...300, step: 25)
                    .tint(.blue)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    mockManager.simulateDrink(amountMl: UInt8(selectedAmount))
                    onDrinkSimulated()
                } label: {
                    Label("Add Drink", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    mockManager.simulateRandomDrink()
                    onDrinkSimulated()
                } label: {
                    Label("Random", systemImage: "dice.fill")
                }
                .buttonStyle(.bordered)
            }

            // Quick presets
            HStack(spacing: 8) {
                ForEach([100, 150, 200, 250], id: \.self) { amount in
                    Button("\(amount)ml") {
                        mockManager.simulateDrink(amountMl: UInt8(amount))
                        onDrinkSimulated()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Connection state
            HStack {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear All") {
                    mockManager.clearSimulatedDrinks()
                    onDrinkSimulated()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var connectionColor: Color {
        switch mockManager.connectionState {
        case .disconnected: return .gray
        case .scanning: return .yellow
        case .connecting: return .orange
        case .connected: return .green
        case .polling: return .blue
        case .error: return .red
        }
    }

    private var connectionText: String {
        switch mockManager.connectionState {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .polling: return "Polling..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

#Preview {
    SimulatorControlView(
        mockManager: MockBLEManager(),
        onDrinkSimulated: {},
        onDemoCountdown: {}
    )
    .padding()
}
