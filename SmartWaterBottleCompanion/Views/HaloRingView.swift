import SwiftUI

struct HaloRingView: View {
    let progress: Double
    let glassesConsumed: Int
    let glassesGoal: Int
    let isAlerting: Bool

    @State private var animateRainbow = false

    private let ringWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: ringWidth)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isAlerting ? rainbowGradient : progressGradient,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                // Center content
                VStack(spacing: 4) {
                    Text("\(glassesConsumed)/\(glassesGoal)")
                        .font(.system(size: size * 0.15, weight: .bold, design: .rounded))

                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.08))
                        .foregroundColor(.blue)
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

#Preview {
    VStack(spacing: 40) {
        HaloRingView(progress: 0.75, glassesConsumed: 6, glassesGoal: 8, isAlerting: false)
            .frame(width: 200, height: 200)

        HaloRingView(progress: 0.5, glassesConsumed: 4, glassesGoal: 8, isAlerting: true)
            .frame(width: 150, height: 150)
    }
    .padding()
}
