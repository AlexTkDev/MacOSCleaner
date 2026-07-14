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
#endif
