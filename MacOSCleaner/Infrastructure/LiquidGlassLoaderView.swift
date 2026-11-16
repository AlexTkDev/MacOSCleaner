import SwiftUI

public struct LiquidGlassLoaderView: View {
    let size: CGFloat
    let text: String?

    @State private var isAnimating = false
    @State private var dotPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(size: CGFloat = 40, text: String? = nil) {
        self.size = size
        self.text = text
    }

    public var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if reduceTransparency {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: size, height: size)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: size, height: size)
                }

                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
                    .frame(width: size, height: size)

                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                    .frame(width: size * 0.72, height: size * 0.72)

                Circle()
                    .trim(from: 0.0, to: 0.65)
                    .stroke(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: max(2.5, size * 0.07), lineCap: .round)
                    )
                    .frame(width: size * 0.72, height: size * 0.72)
                    .rotationEffect(Angle(degrees: !reduceMotion && isAnimating ? 360 : 0))
                    .animation(
                        reduceMotion ? nil : Animation.linear(duration: 1.1).repeatForever(autoreverses: false),
                        value: isAnimating
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .accentColor, .accentColor.opacity(0.3)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.16
                        )
                    )
                    .frame(width: size * 0.28, height: size * 0.28)
                    .scaleEffect(!reduceMotion && dotPulse ? 1.15 : 0.95)
                    .opacity(!reduceMotion && dotPulse ? 0.95 : 0.78)
                    .animation(
                        reduceMotion ? nil : Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: dotPulse
                    )
            }
            .frame(width: size, height: size)
            .shadow(color: Color.accentColor.opacity(0.25), radius: size * 0.22, y: 2)

            if let text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
            dotPulse = true
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        LiquidGlassLoaderView(size: 40, text: "Scanning system...")
        LiquidGlassLoaderView(size: 80)
    }
    .padding(50)
    .background(Color.black.opacity(0.2))
}
