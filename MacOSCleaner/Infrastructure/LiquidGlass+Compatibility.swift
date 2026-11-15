import SwiftUI

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

// MARK: - macOS 26+ Content Surfaces & Button Helpers

public extension View {
    /// Clean HIG-compliant content card surface (no glass on content layer).
    func glassCard(cornerRadius: CGFloat = 14, isDestructive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, isDestructive: isDestructive))
    }

    func glassButtonStyle() -> some View {
        self.buttonStyle(.glass)
    }

    func prominentGlassButtonStyle(tint: Color = .accentColor) -> some View {
        self.buttonStyle(.glassProminent)
            .tint(tint)
    }

    func secondaryGlassButtonStyle() -> some View {
        self.buttonStyle(.glass)
    }

    func destructiveGlassButtonStyle() -> some View {
        self.buttonStyle(.glassProminent)
            .tint(.red)
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isDestructive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if isDestructive {
                    shape.fill(Color.red.opacity(reduceTransparency ? 0.14 : 0.08))
                } else if reduceTransparency {
                    shape.fill(Color(NSColor.controlBackgroundColor))
                } else {
                    shape.fill(
                        colorScheme == .dark
                            ? Color(NSColor.controlBackgroundColor).opacity(0.65)
                            : Color(NSColor.controlBackgroundColor).opacity(0.85)
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    isDestructive
                        ? Color.red.opacity(0.32)
                        : Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.08),
                    lineWidth: 1
                )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05),
                radius: 8,
                x: 0,
                y: 2
            )
    }
}
