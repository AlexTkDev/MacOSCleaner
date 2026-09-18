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
        VStack(spacing: 14) {
            ZStack {
                // Background circular glass lens (no square box or opaque content)
                Circle()
                    .fill(Color.clear)
                    .frame(width: size, height: size)
                    .glassEffect(Glass.regular.tint(.accentColor), in: Circle())
                
                // Subtle inner guide track
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                    .frame(width: size * 0.72, height: size * 0.72)
                
                // Spinning gradient arc
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
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1.1)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // Glowing glass core dot
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
                    .scaleEffect(dotPulse ? 1.15 : 0.88)
                    .opacity(dotPulse ? 0.95 : 0.7)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                        value: dotPulse
                    )
            }
            .frame(width: size, height: size)
            .shadow(color: Color.accentColor.opacity(0.30), radius: size * 0.25, y: 2)
            
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
