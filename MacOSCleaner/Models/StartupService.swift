import SwiftUI

public enum ServiceCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case user
    case thirdParty
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: return "startup_category_user".localized
        case .thirdParty: return "startup_category_third_party".localized
        case .system: return "startup_category_system".localized
        }
    }

    public var icon: String {
        switch self {
        case .user: return "person.fill"
        case .thirdParty: return "puzzlepiece.fill"
        case .system: return "gearshape.fill"
        }
    }

    public var color: Color {
        switch self {
        case .user: return .green
        case .thirdParty: return .blue
        case .system: return .red
        }
    }
}

public struct StartupService: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let isEnabled: Bool
    public let category: ServiceCategory

    public init(id: String, name: String, path: String, isEnabled: Bool, category: ServiceCategory) {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.category = category
    }
}
