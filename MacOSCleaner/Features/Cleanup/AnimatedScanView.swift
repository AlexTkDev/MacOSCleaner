import SwiftUI

struct AnimatedScanView: View {
    let title: String
    let subtitle: String
    let currentStep: Int
    let totalSteps: Int
    var onCancel: (() -> Void)? = nil

    @State private var pulsePhase: Double = 0
    @State private var particlePositions: [Particle] = []

    private let ringCount = 3
    private let particleCount = 6

    struct Particle: Identifiable {
        let id: Int
        var angle: Double
        var radius: CGFloat
        var opacity: Double
        var speed: Double
    }

    var body: some View {
        VStack(spacing: 28) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            radarView
            infoView
            if let onCancel {
                Button(action: onCancel) {
                    Text("cancel".localized)
                        .fontWeight(.medium)
                        .frame(width: 120, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 2.5).repeatForever(autoreverses: true)) {
                pulsePhase = .pi * 2
            }
            particlePositions = (0..<particleCount).map { i in
                Particle(id: i, angle: Double(i) * 60, radius: 45 + CGFloat.random(in: -5...5), opacity: 0.6, speed: 0.5 + Double.random(in: -0.2...0.2))
            }
        }
    }

    @ViewBuilder
    private var radarView: some View {
        TimelineView(.animation(minimumInterval: 0.016, paused: false)) { timeline in
            let angle = (timeline.date.timeIntervalSince1970 * 90).truncatingRemainder(dividingBy: 360)

            ZStack {
                pulsingRings
                radarBaseRing
                radarArc(angle: angle)
                scanningDot(angle: angle)
                orbitingParticles(angle: angle)
                centerIcon
            }
            .frame(width: 200, height: 200)
        }
    }

    @ViewBuilder
    private var pulsingRings: some View {
        ForEach(0..<ringCount, id: \.self) { i in
            Circle()
                .stroke(Color.accentColor.opacity(0.2 - Double(i) * 0.055), lineWidth: 1.5)
                .frame(width: 150 + CGFloat(i) * 38, height: 150 + CGFloat(i) * 38)
                .scaleEffect(1 + sin(pulsePhase + Double(i) * 0.9) * 0.05)
                .opacity(0.6 + sin(pulsePhase + Double(i) * 0.9) * 0.3)
        }
    }

    @ViewBuilder
    private var radarBaseRing: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.04))
            .frame(width: 116, height: 116)
        Circle()
            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1.5)
            .frame(width: 116, height: 116)
        Circle()
            .stroke(Color.accentColor.opacity(0.08), lineWidth: 0.5)
            .frame(width: 82, height: 82)
    }

    private func radarArc(angle: Double) -> some View {
        RadarArcShape(angle: angle)
            .stroke(
                LinearGradient(
                    colors: [.accentColor.opacity(0.85), .accentColor.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 116, height: 116)
            .rotationEffect(.degrees(angle))
    }

    private func scanningDot(angle: Double) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .shadow(color: .accentColor.opacity(0.7), radius: 6)
            .offset(x: 58)
            .rotationEffect(.degrees(angle))
    }

    private func orbitingParticles(angle: Double) -> some View {
        ForEach(particlePositions) { particle in
            Circle()
                .fill(Color.accentColor.opacity(particle.opacity))
                .frame(width: 3, height: 3)
                .offset(x: particle.radius)
                .rotationEffect(.degrees(angle * particle.speed + particle.angle))
        }
    }

    @ViewBuilder
    private var centerIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(
                LinearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(0.85)
    }

    @ViewBuilder
    private var infoView: some View {
        VStack(spacing: 14) {
            if totalSteps > 1 {
                HStack(spacing: 5) {
                    Text("\(currentStep)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(.accentColor)
                        .contentTransition(.numericText())
                    Text("/")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    Text("\(totalSteps)")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Text(subtitle)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .id(subtitle)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.8)),
                    removal: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.25, dampingFraction: 0.9))
                ))

            if totalSteps > 1 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.55)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(5, geo.size.width * CGFloat(currentStep) / CGFloat(max(1, totalSteps))), height: 5)
                    }
                }
                .frame(width: 260, height: 5)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
            }
        }
    }
}

private struct RadarArcShape: Shape {
    let angle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(degrees: angle - 12),
            endAngle: Angle(degrees: angle - 52),
            clockwise: false
        )
        return path
    }
}
