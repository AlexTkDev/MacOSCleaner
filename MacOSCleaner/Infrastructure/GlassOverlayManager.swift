import SwiftUI
import Observation

public enum GlassAlertType: Sendable {
    case warning
    case critical

    var systemImage: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .warning: return .orange
        case .critical: return .red
        }
    }
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

    public var activeAlert: GlassAlertMessage?

    private init() {}

    public func showAlert(
        title: String,
        message: String,
        type: GlassAlertType = .warning,
        primaryButtonTitle: String,
        primaryAction: @escaping @MainActor () -> Void,
        secondaryButtonTitle: String? = "cancel".localized,
        secondaryAction: (@MainActor () -> Void)? = nil
    ) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            activeAlert = nil
        }
    }
}
