//
//  BLEDiscoveryView.swift
//  SmartWaterBottleCompanion
//
//  BLE discovery view for finding the water bottle's real UUIDs
//

import SwiftUI

struct BLEDiscoveryView: View {
    @ObservedObject var bleManager: BLEManager
    @Environment(\.dismiss) private var dismiss
    @State private var filterText: String = ""

    /// Filtered list of devices based on search text
    private var filteredDevices: [DiscoveredDevice] {
        if filterText.isEmpty {
            return bleManager.devices
        }
        let lowercaseFilter = filterText.lowercased()
        return bleManager.devices.filter { device in
            device.name.lowercased().hasPrefix(lowercaseFilter) ||
            device.name.lowercased().contains(lowercaseFilter)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Status header
                HStack {
                    statusIcon
                    Text(statusText)
                        .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(statusColor.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

                // Filter text field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter by name...", text: $filterText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                // Instructions
                Text("Tap a device to connect. Watch Xcode Console for service/characteristic UUIDs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Divider()

                // Discovered devices list
                if bleManager.devices.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Scanning for devices...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No devices match '\(filterText)'")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(bleManager.devices.count) total devices found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Tap to Connect (\(filteredDevices.count) of \(bleManager.devices.count))") {
                            ForEach(filteredDevices) { device in
                                Button {
                                    bleManager.connectToDevice(device)
                                } label: {
                                    HStack {
                                        Image(systemName: deviceIcon(for: device.name))
                                            .foregroundColor(deviceColor(for: device.name))
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.primary)
                                            Text("RSSI: \(device.rssi) dB")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        bleManager.disconnect()
                        bleManager.startScanning()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        bleManager.disconnect()
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("BLE Discovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        bleManager.disconnect()
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch bleManager.connectionState {
            case .scanning:
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.blue)
            case .connecting:
                Image(systemName: "link")
                    .foregroundColor(.orange)
            case .connected, .polling:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            case .disconnected:
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(.gray)
            }
        }
    }

    private var statusText: String {
        switch bleManager.connectionState {
        case .scanning:
            return "Scanning... (\(bleManager.devices.count) found)"
        case .connecting:
            return "Connecting to device..."
        case .connected:
            return "Connected! Check Xcode Console for UUIDs"
        case .polling:
            return "Reading data..."
        case .error(let message):
            return "Error: \(message)"
        case .disconnected:
            return "Disconnected"
        }
    }

    private var statusColor: Color {
        switch bleManager.connectionState {
        case .scanning, .connecting:
            return .blue
        case .connected, .polling:
            return .green
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }

    private func deviceIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("water") || lower.contains("bottle") || lower.contains("h2o") || lower.contains("boost") {
            return "drop.fill"
        } else if lower.contains("watch") {
            return "applewatch"
        } else if lower.contains("phone") || lower.contains("iphone") {
            return "iphone"
        } else if lower.contains("airpod") {
            return "airpodspro"
        } else if lower == "unknown" {
            return "questionmark.circle"
        }
        return "wave.3.right"
    }

    private func deviceColor(for name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("water") || lower.contains("bottle") || lower.contains("h2o") || lower.contains("boost") {
            return .blue
        }
        return .secondary
    }
}

#Preview {
    BLEDiscoveryView(bleManager: BLEManager())
}
