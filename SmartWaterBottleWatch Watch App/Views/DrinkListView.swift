//
//  DrinkListView.swift
//  SmartWaterBottleWatch Watch App
//
//  Shows today's drink history
//

import SwiftUI

struct DrinkListView: View {
    let drinks: [WatchDrink]
    let totalMl: Int

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text("\(totalMl) ml")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }

            Section("Today's Drinks") {
                if drinks.isEmpty {
                    Text("No drinks yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(drinks.sorted { $0.timestamp > $1.timestamp }) { drink in
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))

                            Text(formatTime(drink.timestamp))
                                .font(.system(size: 14))

                            Spacer()

                            Text("\(drink.amountMl) ml")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Drinks")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        DrinkListView(drinks: [], totalMl: 400)
    }
}
