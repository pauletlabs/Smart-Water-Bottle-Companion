import SwiftUI

/// Animated "Time to Drink!" banner shown when alerting
struct AlertBannerView: View {
    @State private var bounce = false
    @State private var glowOpacity = 0.5

    var body: some View {
        HStack(spacing: 12) {
            // Animated water drop
            Image(systemName: "drop.fill")
                .font(.system(size: 28))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: bounce ? -5 : 5)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: bounce)

            VStack(alignment: .leading, spacing: 2) {
                Text("Time to Drink!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Stay hydrated - grab your water bottle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Pulsing alert icon
            Image(systemName: "bell.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)
                .opacity(glowOpacity)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: glowOpacity)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.orange, .red, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                )
        )
        .onAppear {
            bounce = true
            glowOpacity = 1.0
        }
    }
}

#Preview {
    AlertBannerView()
        .padding()
}
