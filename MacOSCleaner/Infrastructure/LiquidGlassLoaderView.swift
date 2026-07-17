import SwiftUI

public struct LiquidGlassLoaderView: View {
    let size: CGFloat
    let text: String?
    
    @State private var isAnimating = false
    @State private var dotPulse = false
    
    public init(size: CGFloat = 40, text: String? = nil) {
        self.size = size
        self.text = text
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background glass disk
                Circle()
                    .fill(Color.primary.opacity(0.03))
                    .glassEffect()
                    .frame(width: size, height: size)
                
                // Outer tracking border
                Circle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: size * 0.08)
                    .frame(width: size * 0.8, height: size * 0.8)
                
                // Spinning gradient arc
                Circle()
                    .trim(from: 0.0, to: 0.6)
                    .stroke(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round)
                    )
                    .frame(width: size * 0.8, height: size * 0.8)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1.0)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // Glowing glass core dot
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.accentColor, .accentColor.opacity(0.2)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.15
                        )
                    )
                    .frame(width: size * 0.3, height: size * 0.3)
                    .scaleEffect(dotPulse ? 1.2 : 0.85)
                    .opacity(dotPulse ? 0.9 : 0.6)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: dotPulse
                    )
            }
            .frame(width: size, height: size)
            .shadow(color: .accentColor.opacity(0.15), radius: size * 0.25)
            
            if let text {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
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
