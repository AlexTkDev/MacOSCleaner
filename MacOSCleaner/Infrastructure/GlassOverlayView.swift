import SwiftUI

public struct GlassOverlayView: View {
    @Bindable var manager: GlassOverlayManager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public init(manager: GlassOverlayManager) {
        self.manager = manager
    }
    
    public var body: some View {
        ZStack {
            // Backdrop when alert is shown
            if manager.activeAlert != nil {
                Color.black.opacity(reduceTransparency ? 0.65 : 0.25)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    .onTapGesture {
                        // Dismiss alert on clicking background optionally,
                        // but for critical alerts we might want to force button click.
                    }
                
                alertContainer
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.8)),
                        removal: .scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.25, dampingFraction: 0.85))
                    ))
            }
            
            // Toast container (aligned to top right)
            VStack {
                if let toast = manager.activeToast {
                    toastView(toast)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.78)),
                            removal: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.25, dampingFraction: 0.85))
                        ))
                }
                Spacer()
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
    }
    
    @ViewBuilder
    private var alertContainer: some View {
        if let alert = manager.activeAlert {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 18) {
                    // Pulsing Warning Icon
                    Image(systemName: alert.type.systemImage)
                        .font(.system(size: 38))
                        .foregroundColor(alert.type.color)
                        .shadow(color: alert.type.color.opacity(0.3), radius: 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(alert.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(alert.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                Divider()
                
                // Action Buttons
                HStack(spacing: 12) {
                    Spacer()
                    
                    if let secondaryTitle = alert.secondaryButtonTitle {
                        Button {
                            let action = alert.secondaryAction
                            manager.dismissAlert()
                            if let action {
                                action()
                            }
                        } label: {
                            Text(secondaryTitle)
                                .fontWeight(.medium)
                                .frame(width: 80, height: 22)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .glassEffect()
                    }
                    
                    Button {
                        let action = alert.primaryAction
                        manager.dismissAlert()
                        action()
                    } label: {
                        Text(alert.primaryButtonTitle)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 90, height: 22)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(alert.type == .critical ? Color.red : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.015))
            }
            .frame(width: 440)
            .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.35), radius: 24, y: 12)
        }
    }
    
    @ViewBuilder
    private func toastView(_ toast: ToastMessage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.systemImage)
                .font(.title2)
                .foregroundColor(toast.type.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(toast.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 16)
            
            Button {
                manager.dismissToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(width: 320)
        .glassEffect(Glass.regular.tint(toast.type.color), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.20), radius: 12, y: 5)
    }
}
