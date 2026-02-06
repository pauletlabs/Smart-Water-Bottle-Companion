import SwiftUI

/// Animated rainbow border that glows around the screen edge when alerting
/// Inspired by Siri's glow effect
struct RainbowBorderView<Content: View>: View {
    let isActive: Bool
    let borderWidth: CGFloat
    let content: Content

    @State private var rotation: Double = 0

    init(isActive: Bool, borderWidth: CGFloat = 5, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.borderWidth = borderWidth
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Rainbow border (only when active)
            if isActive {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                .red, .orange, .yellow, .green,
                                .cyan, .blue, .purple, .pink, .red
                            ],
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: borderWidth
                    )
                    .ignoresSafeArea()
                    .blur(radius: 2)
                    .opacity(0.9)

                // Inner glow layer for more intensity
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                .red, .orange, .yellow, .green,
                                .cyan, .blue, .purple, .pink, .red
                            ],
                            center: .center,
                            startAngle: .degrees(rotation + 180),
                            endAngle: .degrees(rotation + 540)
                        ),
                        lineWidth: borderWidth * 0.6
                    )
                    .ignoresSafeArea()
                    .blur(radius: 4)
                    .opacity(0.6)
            }

            // Main content
            content
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

#Preview {
    RainbowBorderView(isActive: true) {
        VStack {
            Text("Time to drink!")
                .font(.largeTitle)
            Text("The rainbow border is active")
                .foregroundColor(.secondary)
        }
    }
}
