import SwiftUI

#if !hasFeature(LiquidGlass)
public struct Glass: Sendable, Hashable {
    public enum Variant: Sendable, Hashable {
        case regular
        case clear
        case identity
    }
    
    public var variant: Variant
    public var tintColor: Color?
    public var isInteractive: Bool
    
    public static let regular = Glass(variant: .regular)
    public static let clear = Glass(variant: .clear)
    public static let identity = Glass(variant: .identity)
    
    public init(variant: Variant = .regular, tintColor: Color? = nil, isInteractive: Bool = false) {
        self.variant = variant
        self.tintColor = tintColor
        self.isInteractive = isInteractive
    }
    
    public func tint(_ color: Color) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }
    
    public func interactive(_ active: Bool = true) -> Glass {
        var copy = self
        copy.isInteractive = active
        return copy
    }
}

public enum GlassEffectTransition: Sendable, Hashable {
    case matchedGeometry
    case materialize
}

public struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat?
    let content: () -> Content
    
    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }
    
    public var body: some View {
        VStack(spacing: spacing) {
            content()
        }
    }
}

public struct LiquidGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let glass: Glass
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    public func body(content: Content) -> some View {
        if glass.variant == .identity {
            content
        } else {
            content
                .background {
                    glassBackground
                }
                .overlay {
                    glassBorder
                }
                .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
                .onHover { hovering in
                    if glass.isInteractive {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isHovered = hovering
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            shape.fill(Color(NSColor.controlBackgroundColor))
        } else {
            ZStack {
                if glass.variant == .clear {
                    shape.fill(.ultraThinMaterial)
                } else {
                    shape.fill(.regularMaterial)
                }

                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered && glass.isInteractive ? 0.16 : 0.10),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                if let tint = glass.tintColor {
                    shape.fill(tint.opacity(isHovered && glass.isInteractive ? 0.24 : 0.16))
                }
            }
        }
    }

    private var glassBorder: some View {
        shape.strokeBorder(
            LinearGradient(
                stops: [
                    .init(color: specularHighlightColor, location: 0.0),
                    .init(color: Color.white.opacity(0.14), location: 0.4),
                    .init(color: Color.white.opacity(0.06), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
    }

    private var specularHighlightColor: Color {
        if let tint = glass.tintColor {
            return tint.opacity(isHovered && glass.isInteractive ? 0.55 : 0.35)
        }
        return Color.white.opacity(isHovered && glass.isInteractive ? 0.36 : 0.26)
    }
}

public extension View {
    func glassEffect() -> some View {
        glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 12))
    }
    
    func glassEffect<S: InsettableShape>(_ glass: Glass = .regular, in shape: S = RoundedRectangle(cornerRadius: 12)) -> some View {
        modifier(LiquidGlassSurfaceModifier(glass: glass, shape: shape))
    }
    
    func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View {
        self
    }
    
    func glassEffectTransition(_ transition: GlassEffectTransition) -> some View {
        self
    }
    
    func glassEffectTransition(_ transition: Any) -> some View {
        self
    }
}

public struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    public init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif

// MARK: - macOS 27 Shared Surfaces

public extension View {
    /// Liquid Glass card surface with macOS 27 rounded chrome (opaque content + hairline border + soft shadow).
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Capsule Liquid Glass surface for chips and search fields.
    func glassCapsule() -> some View {
        glassEffect(Glass.regular, in: Capsule())
    }
    
    /// Concentric corner container helper (macOS 27+).
    @ViewBuilder
    func containerConcentric(cornerRadius: CGFloat = 16) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                        
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.28), location: 0.0),
                                .init(color: Color.white.opacity(0.14), location: 0.35),
                                .init(color: Color.white.opacity(0.05), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.32), radius: 18, x: 0, y: 7)
            .shadow(color: Color.black.opacity(0.16), radius: 3, x: 0, y: 1)
    }
}

public extension View {
    func glassButtonStyle() -> some View {
        self.buttonStyle(SecondaryGlassButtonStyle())
    }
    
    func prominentGlassButtonStyle(tint: Color = .accentColor) -> some View {
        self.buttonStyle(ProminentGlassButtonStyle(tint: tint))
    }
    
    func secondaryGlassButtonStyle() -> some View {
        self.buttonStyle(SecondaryGlassButtonStyle())
    }
    
    func destructiveGlassButtonStyle() -> some View {
        self.buttonStyle(ProminentGlassButtonStyle(tint: .red))
    }
}

public struct SecondaryGlassButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        SecondaryGlassButton(configuration: configuration)
    }
}

private struct SecondaryGlassButton: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        configuration.label
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? (isHovered ? 0.16 : 0.08) : 0.03),
                                    Color.white.opacity(isEnabled ? (isHovered ? 0.08 : 0.04) : 0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isEnabled ? (isHovered ? 0.45 : 0.24) : 0.08), location: 0.0),
                                .init(color: Color.white.opacity(isEnabled ? (isHovered ? 0.20 : 0.12) : 0.04), location: 0.5),
                                .init(color: Color.white.opacity(isEnabled ? 0.08 : 0.03), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.10), radius: isHovered ? 8 : 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered && isEnabled ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.15, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public struct ProminentGlassButtonStyle: ButtonStyle {
    let tint: Color
    
    public init(tint: Color = .accentColor) {
        self.tint = tint
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        ProminentGlassButton(configuration: configuration, tint: tint)
    }
}

private struct ProminentGlassButton: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(isEnabled ? (isHovered ? 0.88 : 0.76) : 0.25),
                                    tint.opacity(isEnabled ? (isHovered ? 0.72 : 0.62) : 0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? (isHovered ? 0.26 : 0.14) : 0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isEnabled ? (isHovered ? 0.55 : 0.38) : 0.15), location: 0.0),
                                .init(color: tint.opacity(isEnabled ? 0.5 : 0.2), location: 0.5),
                                .init(color: Color.white.opacity(isEnabled ? 0.12 : 0.05), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(isEnabled ? (isHovered ? 0.40 : 0.22) : 0), radius: isHovered ? 10 : 6, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered && isEnabled ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.15, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public struct DestructiveGlassButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        ProminentGlassButton(configuration: configuration, tint: .red)
    }
}
