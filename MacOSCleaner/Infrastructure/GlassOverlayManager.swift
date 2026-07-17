import SwiftUI
import Observation

public enum ToastType: Sendable {
    case info
    case success
    case warning
    case error
    
    var systemImage: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

public enum GlassAlertType: Sendable {
    case info
    case warning
    case critical
    
    var systemImage: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

public struct ToastMessage: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let type: ToastType
    public let duration: Double
}

public struct GlassAlertMessage: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let type: GlassAlertType
    public let primaryButtonTitle: String
    public let primaryAction: @MainActor () -> Void
    public let secondaryButtonTitle: String?
    public let secondaryAction: (@MainActor () -> Void)?
    
    public init(
        title: String,
        message: String,
        type: GlassAlertType = .warning,
        primaryButtonTitle: String,
        primaryAction: @escaping @MainActor () -> Void,
        secondaryButtonTitle: String? = nil,
        secondaryAction: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.type = type
        self.primaryButtonTitle = primaryButtonTitle
        self.primaryAction = primaryAction
        self.secondaryButtonTitle = secondaryButtonTitle
        self.secondaryAction = secondaryAction
    }
}

@Observable
@MainActor
public final class GlassOverlayManager {
    public static let shared = GlassOverlayManager()
    
    public var activeToast: ToastMessage?
    public var activeAlert: GlassAlertMessage?
    
    private var toastTask: Task<Void, Never>?
    
    private init() {}
    
    public func showToast(title: String, message: String, type: ToastType = .info, duration: Double = 3.5) {
        toastTask?.cancel()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeToast = ToastMessage(title: title, message: message, type: type, duration: duration)
        }
        
        toastTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }
    
    public func dismissToast() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeToast = nil
        }
    }
    
    public func showAlert(
        title: String,
        message: String,
        type: GlassAlertType = .warning,
        primaryButtonTitle: String,
        primaryAction: @escaping @MainActor () -> Void,
        secondaryButtonTitle: String? = "cancel".localized,
        secondaryAction: (@MainActor () -> Void)? = nil
    ) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            activeAlert = GlassAlertMessage(
                title: title,
                message: message,
                type: type,
                primaryButtonTitle: primaryButtonTitle,
                primaryAction: primaryAction,
                secondaryButtonTitle: secondaryButtonTitle,
                secondaryAction: secondaryAction
            )
        }
    }
    
    public func dismissAlert() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeAlert = nil
        }
    }
}
