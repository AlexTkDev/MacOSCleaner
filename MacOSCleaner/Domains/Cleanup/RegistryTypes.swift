import Foundation

public enum PathToken: String, Sendable, CaseIterable {
    case appSupport = "<APP_SUPPORT>"
    case caches = "<CACHES>"
    case prefs = "<PREFS>"
    case containers = "<CONTAINERS>"
    case groupContainers = "<GROUP_CONTAINERS>"
    case logs = "<LOGS>"
    case home = "<HOME>"
    case savedState = "<SAVED_STATE>"
    case userLib = "<USER_LIB>"
    case userConfig = "<USER_CONFIG>"
    case userCache = "<USER_CACHE>"
    case varFolders = "<VAR_FOLDERS>"
    case sysLib = "<SYS_LIB>"
    case sysAppSupport = "<SYS_APP_SUPPORT>"
    case sysLaunchAgents = "<SYS_LAUNCH_AGENTS>"
    case sysLaunchDaemons = "<SYS_LAUNCH_DAEMONS>"
    case sysPrivHelpers = "<SYS_PRIV_HELPERS>"
    case sysCaches = "<SYS_CACHES>"
    case sysPrefs = "<SYS_PREFS>"
    case sysLogs = "<SYS_LOGS>"

    /// Resolves a tokenized template using the current user home directory.
    public func resolveTemplate(_ template: String, home: String) -> String {
        var result = template
        let replacements: [(PathToken, String)] = [
            (.appSupport, Self.appSupport.basePath(home: home)),
            (.caches, Self.caches.basePath(home: home)),
            (.prefs, Self.prefs.basePath(home: home)),
            (.containers, Self.containers.basePath(home: home)),
            (.groupContainers, Self.groupContainers.basePath(home: home)),
            (.logs, Self.logs.basePath(home: home)),
            (.home, Self.home.basePath(home: home)),
            (.savedState, Self.savedState.basePath(home: home)),
            (.userLib, Self.userLib.basePath(home: home)),
            (.userConfig, Self.userConfig.basePath(home: home)),
            (.userCache, Self.userCache.basePath(home: home)),
            (.varFolders, Self.varFolders.basePath(home: home)),
            (.sysLib, Self.sysLib.basePath(home: home)),
            (.sysAppSupport, Self.sysAppSupport.basePath(home: home)),
            (.sysLaunchAgents, Self.sysLaunchAgents.basePath(home: home)),
            (.sysLaunchDaemons, Self.sysLaunchDaemons.basePath(home: home)),
            (.sysPrivHelpers, Self.sysPrivHelpers.basePath(home: home)),
            (.sysCaches, Self.sysCaches.basePath(home: home)),
            (.sysPrefs, Self.sysPrefs.basePath(home: home)),
            (.sysLogs, Self.sysLogs.basePath(home: home)),
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token.rawValue, with: value)
        }
        return result
    }

    private func basePath(home: String) -> String {
        switch self {
        case .appSupport: return "\(home)/Library/Application Support"
        case .caches: return "\(home)/Library/Caches"
        case .prefs: return "\(home)/Library/Preferences"
        case .containers: return "\(home)/Library/Containers"
        case .groupContainers: return "\(home)/Library/Group Containers"
        case .logs: return "\(home)/Library/Logs"
        case .home: return home
        case .savedState: return "\(home)/Library/Saved Application State"
        case .userLib: return "\(home)/Library"
        case .userConfig: return "\(home)/.config"
        case .userCache: return "\(home)/.cache"
        case .varFolders: return "/private/var/folders"
        case .sysLib: return "/Library"
        case .sysAppSupport: return "/Library/Application Support"
        case .sysLaunchAgents: return "/Library/LaunchAgents"
        case .sysLaunchDaemons: return "/Library/LaunchDaemons"
        case .sysPrivHelpers: return "/Library/PrivilegedHelperTools"
        case .sysCaches: return "/Library/Caches"
        case .sysPrefs: return "/Library/Preferences"
        case .sysLogs: return "/Library/Logs"
        }
    }
}

public enum PathPurpose: String, Sendable, Codable, Equatable {
    case cache
    case appData = "app_data"
    case shared
    case userContent = "user_content"
}

public struct RegistryPath: Sendable, Equatable {
    public let template: String
    public let purpose: PathPurpose
    public let isGlob: Bool
    public let requiresAdmin: Bool

    public init(template: String, purpose: PathPurpose, isGlob: Bool = false, requiresAdmin: Bool = false) {
        self.template = template
        self.purpose = purpose
        self.isGlob = isGlob
        self.requiresAdmin = requiresAdmin
    }
}

public struct AppPaths: Sendable {
    public let bundleIDs: [String]
    public let bundleIDPrefixes: [String]
    public let paths: [RegistryPath]
    public let category: CleanupCategory

    public init(
        bundleIDs: [String],
        bundleIDPrefixes: [String] = [],
        paths: [RegistryPath],
        category: CleanupCategory
    ) {
        self.bundleIDs = bundleIDs
        self.bundleIDPrefixes = bundleIDPrefixes
        self.paths = paths
        self.category = category
    }
}
