import SwiftUI

public struct GlassOverlayView: View {
    @Bindable var manager: GlassOverlayManager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(manager: GlassOverlayManager) {
        self.manager = manager
    }

    public var body: some View {
        ZStack {
            if manager.activeAlert != nil {
                Color.black.opacity(reduceTransparency ? 0.65 : 0.25)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0 : 0.2)))

                alertContainer
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity).animation(.spring(response: 0.32, dampingFraction: 0.82)),
                                removal: .scale(scale: 0.96).combined(with: .opacity).animation(.spring(response: 0.22, dampingFraction: 0.88))
                            )
                    )
            }
        }
    }

    @ViewBuilder
    private var alertContainer: some View {
        if let alert = manager.activeAlert {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: alert.type.systemImage)
                        .font(.system(size: 36))
                        .foregroundStyle(alert.type.color)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(alert.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(alert.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider()

                HStack(spacing: 12) {
                    Spacer()

                    if let secondaryTitle = alert.secondaryButtonTitle {
                        Button(secondaryTitle) {
                            let action = alert.secondaryAction
                            manager.dismissAlert()
                            action?()
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                    }

                    Button(alert.primaryButtonTitle, role: alert.type == .critical ? .destructive : nil) {
                        let action = alert.primaryAction
                        manager.dismissAlert()
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(alert.type == .critical ? .red : .accentColor)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(width: 440)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                } else {
                    Color.clear
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.30), radius: 24, y: 12)
        }
    }
}
