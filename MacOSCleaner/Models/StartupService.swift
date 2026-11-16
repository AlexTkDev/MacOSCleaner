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

    public var helpText: String {
        switch self {
        case .user: return "startup_help_user".localized
        case .thirdParty: return "startup_help_third_party".localized
        case .system: return "startup_help_system".localized
        }
    }
}

public enum ExecutableLocation: String, Codable, Sendable, Equatable {
    case standard
    case temporaryDirectory
    case hiddenDirectory

    public static func classify(path: String?) -> ExecutableLocation {
        guard let path, !path.isEmpty else { return .standard }
        let lower = path.lowercased()
        if lower.hasPrefix("/tmp/")
            || lower.hasPrefix("/private/tmp/")
            || lower.hasPrefix("/var/tmp/")
            || lower.hasPrefix("/private/var/tmp/") {
            return .temporaryDirectory
        }
        let components = (path as NSString).pathComponents
        if components.contains(where: { $0.hasPrefix(".") && $0 != "." && $0 != ".." }) {
            return .hiddenDirectory
        }
        return .standard
    }
}

public enum StartupFilter: Hashable, CaseIterable, Identifiable, Sendable {
    case all
    case needsAttention
    case user
    case thirdParty
    case system
    case loginItems

    public var id: Self { self }
}

public struct StartupService: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let isEnabled: Bool
    public let category: ServiceCategory
    public let executablePath: String?
    public let executableExists: Bool
    public let executableLocation: ExecutableLocation
    public let signature: CodeSignatureInfo?
    public let isLoginItem: Bool
    public let developerName: String?

    public var requiresRoot: Bool {
        path.hasPrefix("/Library/LaunchDaemons/")
            || path.hasPrefix("/Library/LaunchAgents/")
            || path.hasPrefix("/System/")
    }

    public var isOrphaned: Bool {
        executablePath != nil && !executableExists
    }

    public var needsAttention: Bool {
        if isOrphaned || executableLocation != .standard {
            return true
        }
        if let signature, !signature.isSigned || !signature.isValid {
            return true
        }
        return false
    }

    public init(
        id: String,
        name: String,
        path: String,
        isEnabled: Bool,
        category: ServiceCategory,
        executablePath: String? = nil,
        executableExists: Bool = true,
        executableLocation: ExecutableLocation = .standard,
        signature: CodeSignatureInfo? = nil,
        isLoginItem: Bool = false,
        developerName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.category = category
        self.executablePath = executablePath
        self.executableExists = executableExists
        self.executableLocation = executableLocation
        self.signature = signature
        self.isLoginItem = isLoginItem
        self.developerName = developerName
    }
}
