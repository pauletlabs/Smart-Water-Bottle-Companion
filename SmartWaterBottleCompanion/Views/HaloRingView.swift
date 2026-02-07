import SwiftUI

/// A drink event for display on the halo
struct HaloDrink: Identifiable {
    let id = UUID()
    let timestamp: Date
    let amountMl: Int
}

struct HaloRingView: View {
    let progress: Double
    let glassesConsumed: Int
    let glassesGoal: Int
    let totalMl: Int
    let isAlerting: Bool
    let drinks: [HaloDrink]
    let wakeTime: DateComponents
    let sleepTime: DateComponents
    let currentTime: Date
    let timeUntilNextDrink: TimeInterval?

    @State private var animateRainbow = false

    private let ringWidth: CGFloat = 24
    private let annotationOffset: CGFloat = 45

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = (size - ringWidth) / 2

            ZStack {
                // Background ring (unfilled portion)
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: ringWidth)

                // Progress ring (elapsed time)
                Circle()
                    .trim(from: 0, to: timeProgress)
                    .stroke(
                        isAlerting ? rainbowGradient : progressGradient,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90)) // Start at 12 o'clock

                // Target zone (next drink window)
                if let targetAngle = nextDrinkAngle, timeProgress < 1.0 {
                    Circle()
                        .trim(from: timeProgress, to: min(targetAngle, 1.0))
                        .stroke(
                            Color.orange.opacity(0.4),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }

                // Drink markers (pencil marks)
                ForEach(drinks) { drink in
                    if let angle = angleForTime(drink.timestamp) {
                        DrinkMarker(
                            angle: angle,
                            radius: radius,
                            amountMl: drink.amountMl,
                            ringWidth: ringWidth
                        )
                    }
                }

                // Drink annotations (outer labels)
                ForEach(drinks) { drink in
                    if let angle = angleForTime(drink.timestamp) {
                        DrinkAnnotation(
                            angle: angle,
                            radius: radius + annotationOffset,
                            amountMl: drink.amountMl,
                            timestamp: drink.timestamp
                        )
                    }
                }

                // Current time marker
                CurrentTimeMarker(
                    angle: timeProgress * 360,
                    radius: radius,
                    ringWidth: ringWidth
                )

                // Center content
                VStack(spacing: 2) {
                    Text("\(glassesConsumed)/\(glassesGoal)")
                        .font(.system(size: size * 0.12, weight: .bold, design: .rounded))

                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.06))
                        .foregroundColor(.blue)

                    Text("\(totalMl)ml")
                        .font(.system(size: size * 0.08, weight: .medium, design: .rounded))
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

    /// Total active minutes in the day (wake to sleep)
    private var totalActiveMinutes: Int {
        let wakeMinutes = (wakeTime.hour ?? 7) * 60 + (wakeTime.minute ?? 0)
        let sleepMinutes = (sleepTime.hour ?? 21) * 60 + (sleepTime.minute ?? 0)
        return sleepMinutes - wakeMinutes
    }

    /// Current progress through the day (0.0 to 1.0)
    private var timeProgress: Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        let currentMinutes = hour * 60 + minute

        let wakeMinutes = (wakeTime.hour ?? 7) * 60 + (wakeTime.minute ?? 0)
        let sleepMinutes = (sleepTime.hour ?? 21) * 60 + (sleepTime.minute ?? 0)

        // Before wake time
        if currentMinutes < wakeMinutes { return 0 }
        // After sleep time
        if currentMinutes >= sleepMinutes { return 1.0 }

        let elapsed = currentMinutes - wakeMinutes
        return Double(elapsed) / Double(totalActiveMinutes)
    }

    /// Angle for the next drink target (as fraction 0-1)
    private var nextDrinkAngle: Double? {
        guard let timeUntil = timeUntilNextDrink, timeUntil > 0 else { return nil }
        let targetMinutes = timeUntil / 60
        let additionalProgress = targetMinutes / Double(totalActiveMinutes)
        return min(timeProgress + additionalProgress, 1.0)
    }

    /// Convert a timestamp to an angle (fraction 0-1, where 0 = wake time = 12 o'clock)
    private func angleForTime(_ date: Date) -> Double? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute

        let wakeMinutes = (wakeTime.hour ?? 7) * 60 + (wakeTime.minute ?? 0)
        let sleepMinutes = (sleepTime.hour ?? 21) * 60 + (sleepTime.minute ?? 0)

        // Outside active hours
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

// MARK: - Drink Marker (pencil line on ring)

struct DrinkMarker: View {
    let angle: Double // 0-1 fraction
    let radius: CGFloat
    let amountMl: Int
    let ringWidth: CGFloat

    var body: some View {
        let degrees = angle * 360 - 90 // -90 to start at 12 o'clock
        let markerLength = min(CGFloat(amountMl) / 10 + 8, ringWidth * 0.8)

        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: markerLength)
            .offset(y: -radius)
            .rotationEffect(.degrees(degrees))
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0)
    }
}

// MARK: - Drink Annotation (outer label)

struct DrinkAnnotation: View {
    let angle: Double // 0-1 fraction
    let radius: CGFloat
    let amountMl: Int
    let timestamp: Date

    var body: some View {
        let degrees = angle * 360 - 90
        let radians = degrees * .pi / 180

        let x = cos(radians) * radius
        let y = sin(radians) * radius

        VStack(spacing: 0) {
            Text("\(amountMl)ml")
                .font(.system(size: 8, weight: .medium))
            Text(timeString)
                .font(.system(size: 7))
                .foregroundColor(.secondary)
        }
        .offset(x: x, y: y)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Current Time Marker

struct CurrentTimeMarker: View {
    let angle: Double // degrees (0-360)
    let radius: CGFloat
    let ringWidth: CGFloat

    var body: some View {
        let degrees = angle - 90 // -90 to start at 12 o'clock

        // Triangle marker pointing inward
        Triangle()
            .fill(Color.red)
            .frame(width: 12, height: 10)
            .offset(y: -radius - ringWidth / 2 - 8)
            .rotationEffect(.degrees(degrees))
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
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
    let sampleDrinks: [HaloDrink] = [
        HaloDrink(timestamp: Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date())!, amountMl: 150),
        HaloDrink(timestamp: Calendar.current.date(bySettingHour: 9, minute: 15, second: 0, of: Date())!, amountMl: 200),
        HaloDrink(timestamp: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!, amountMl: 180),
        HaloDrink(timestamp: Calendar.current.date(bySettingHour: 13, minute: 30, second: 0, of: Date())!, amountMl: 120),
    ]

    VStack(spacing: 40) {
        HaloRingView(
            progress: 0.75,
            glassesConsumed: 4,
            glassesGoal: 8,
            totalMl: 650,
            isAlerting: false,
            drinks: sampleDrinks,
            wakeTime: DateComponents(hour: 7, minute: 0),
            sleepTime: DateComponents(hour: 21, minute: 0),
            currentTime: Date(),
            timeUntilNextDrink: 1800
        )
        .frame(width: 280, height: 280)
    }
    .padding()
}
