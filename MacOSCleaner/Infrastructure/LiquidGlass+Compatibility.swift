import SwiftUI

#if !hasFeature(LiquidGlass)
public struct Glass: Sendable, Hashable {
    public static let regular = Glass()
    public static let clear = Glass()
    public static let identity = Glass()
    
    public func tint(_ color: Color) -> Glass { self }
    public func interactive(_ active: Bool = true) -> Glass { self }
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

public extension View {
    func glassEffect() -> some View {
        self.background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 12)))
    }
    
    func glassEffect(_ glass: Glass, in shape: some Shape = RoundedRectangle(cornerRadius: 12)) -> some View {
        self.background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(shape))
    }
    
    func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View {
        self
    }
    
    func glassEffectTransition(_ transition: Any) -> some View {
        self
    }
    
    func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View {
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
    /// Liquid Glass card surface with macOS 27 rounded chrome (hairline border + soft shadow).
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Capsule Liquid Glass surface for chips and search fields.
    func glassCapsule() -> some View {
        // Explicit Glass type avoids ambiguity between the shim and SwiftUI.Glass (SDK 26+).
        glassEffect(Glass.regular, in: Capsule())
    }

    /// Wallpaper-tinted screen background behind glass panels (macOS 27 look).
    func macOS27ScreenBackground() -> some View {
        modifier(MacOS27ScreenBackgroundModifier())
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let borderColor: Color = Color.primary.opacity(0.07)

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            } else {
                content.glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Self.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }
}

private struct MacOS27ScreenBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            } else {
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    LinearGradient(
                        stops: [
                            .init(color: warmTint, location: 0.0),
                            .init(color: .clear, location: 0.55),
                            .init(color: coolTint, location: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    // Warm champagne → cool lavender-grey, echoing the macOS 27 wallpaper palette.
    private var warmTint: Color {
        Color(red: 0.95, green: 0.86, blue: 0.70).opacity(colorScheme == .dark ? 0.10 : 0.26)
    }

    private var coolTint: Color {
        Color(red: 0.56, green: 0.58, blue: 0.72).opacity(colorScheme == .dark ? 0.14 : 0.18)
    }
}

public extension View {
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
    
    func destructiveGlassButtonStyle() -> some View {
        self.buttonStyle(DestructiveGlassButtonStyle())
    }
}

public struct DestructiveGlassButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        DestructiveGlassButton(configuration: configuration)
    }
}

private struct DestructiveGlassButton: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    
    var body: some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .frame(maxWidth: 300)
            .background(
                ZStack {
                    if #available(macOS 26.0, *) {
                        #if hasFeature(LiquidGlass)
                        Color.clear.glassEffect(.regular.tint(isHovered ? .red : Color(white: 0.15)).interactive())
                        #else
                        Color.clear.background(.ultraThinMaterial)
                        #endif
                    } else {
                        Color.clear.background(.ultraThinMaterial)
                    }
                    
                    if isHovered {
                        Color.red.opacity(configuration.isPressed ? 0.35 : 0.2)
                    } else {
                        Color(white: 0.1).opacity(configuration.isPressed ? 0.5 : 0.3)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.red.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.5)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
