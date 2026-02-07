//
//  WatchHaloView.swift
//  SmartWaterBottleWatch Watch App
//
//  Compact halo ring for Apple Watch display
//

import SwiftUI

struct WatchHaloView: View {
    let data: WatchHydrationData
    let currentTime: Date

    @State private var animateRainbow = false

    private let ringWidth: CGFloat = 12

    /// Whether we're in alert mode (time to drink!)
    private var isAlerting: Bool {
        if let timeUntil = data.timeUntilNextDrink {
            return timeUntil <= 0
        }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = (size - ringWidth) / 2

            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: ringWidth)

                // Progress ring (time elapsed)
                Circle()
                    .trim(from: 0, to: timeProgress)
                    .stroke(
                        isAlerting ? rainbowGradient : progressGradient,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))

                // Target zone
                if let targetAngle = nextDrinkAngle, timeProgress < 1.0 {
                    Circle()
                        .trim(from: timeProgress, to: min(targetAngle, 1.0))
                        .stroke(
                            Color.orange.opacity(0.5),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }

                // Drink markers (small notches)
                ForEach(data.drinks) { drink in
                    if let angle = angleForTime(drink.timestamp) {
                        WatchDrinkMarker(
                            angle: angle,
                            radius: radius,
                            ringWidth: ringWidth
                        )
                    }
                }

                // Current time marker
                WatchTimeMarker(
                    angle: timeProgress * 360,
                    radius: radius,
                    ringWidth: ringWidth
                )

                // Center content
                VStack(spacing: 0) {
                    Text("\(data.glassesConsumed)/\(data.glassesGoal)")
                        .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)

                    Text("cups")
                        .font(.system(size: size * 0.08, weight: .medium))
                        .foregroundColor(.secondary)

                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.08))
                        .foregroundColor(.blue)
                        .padding(.top, 2)

                    Text("\(data.todayTotalMl)ml")
                        .font(.system(size: size * 0.10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: isAlerting) { _, alerting in
            if alerting {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    animateRainbow = true
                }
            } else {
                animateRainbow = false
            }
        }
    }

    // MARK: - Time Calculations

    private var totalActiveMinutes: Int {
        let wakeMinutes = data.wakeHour * 60 + data.wakeMinute
        let sleepMinutes = data.sleepHour * 60 + data.sleepMinute
        return max(sleepMinutes - wakeMinutes, 1)
    }

    private var timeProgress: Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        let currentMinutes = hour * 60 + minute

        let wakeMinutes = data.wakeHour * 60 + data.wakeMinute
        let sleepMinutes = data.sleepHour * 60 + data.sleepMinute

        if currentMinutes < wakeMinutes { return 0 }
        if currentMinutes >= sleepMinutes { return 1.0 }

        let elapsed = currentMinutes - wakeMinutes
        return Double(elapsed) / Double(totalActiveMinutes)
    }

    private var nextDrinkAngle: Double? {
        guard let timeUntil = data.timeUntilNextDrink, timeUntil > 0 else { return nil }
        let targetMinutes = timeUntil / 60
        let additionalProgress = targetMinutes / Double(totalActiveMinutes)
        return min(timeProgress + additionalProgress, 1.0)
    }

    private func angleForTime(_ date: Date) -> Double? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute

        let wakeMinutes = data.wakeHour * 60 + data.wakeMinute
        let sleepMinutes = data.sleepHour * 60 + data.sleepMinute

        if timeMinutes < wakeMinutes || timeMinutes >= sleepMinutes { return nil }

        let elapsed = timeMinutes - wakeMinutes
        return Double(elapsed) / Double(totalActiveMinutes)
    }

    // MARK: - Gradients

    private var progressGradient: AngularGradient {
        AngularGradient(
            colors: [.blue, .cyan, .blue],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }

    private var rainbowGradient: AngularGradient {
        AngularGradient(
            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
            center: .center,
            startAngle: .degrees(animateRainbow ? 360 : 0),
            endAngle: .degrees(animateRainbow ? 720 : 360)
        )
    }
}

// MARK: - Watch Drink Marker

struct WatchDrinkMarker: View {
    let angle: Double
    let radius: CGFloat
    let ringWidth: CGFloat

    var body: some View {
        let degrees = angle * 360 - 90

        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: ringWidth * 0.6)
            .offset(y: -radius)
            .rotationEffect(.degrees(degrees))
            .shadow(color: .black.opacity(0.3), radius: 1)
    }
}

// MARK: - Watch Time Marker

struct WatchTimeMarker: View {
    let angle: Double
    let radius: CGFloat
    let ringWidth: CGFloat

    var body: some View {
        let degrees = angle - 90

        // Small triangle
        WatchTriangle()
            .fill(Color.red)
            .frame(width: 8, height: 6)
            .offset(y: -radius - ringWidth / 2 - 4)
            .rotationEffect(.degrees(degrees))
    }
}

struct WatchTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    WatchHaloView(
        data: WatchHydrationData.empty,
        currentTime: Date()
    )
    .frame(width: 150, height: 150)
}
